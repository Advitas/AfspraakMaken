# Decisions (ADR's)

Append-only. Nieuwe beslissingen worden onderaan toegevoegd, niet bewerkt.

**Format per entry:**

```
## YYYY-MM-DD — Titel

**Context:** waarom moest dit besloten worden
**Beslissing:** wat is gekozen
**Gevolgen:** wat betekent dit voor de rest van het project
```

---

## 2026-08-25 — Alle database-writes uitsluitend via stored procedures

**Context:** De Azure Function moet klantafspraken en -reserveringen kunnen aanmaken in SQL Server. Directe INSERT/UPDATE-statements vanuit de functie-code zouden business-logica (bijv. campagne-koppeling, klant-matching, foutafhandeling) dupliceren of laten afwijken van wat elders in het systeem al in de database is vastgelegd.

**Beslissing:** `function_app.py` doet nooit een directe INSERT/UPDATE. Alle writes lopen via stored procedures: `spMaakAfspraak` (vaste parameter-mapping, `_call_sp_maak_afspraak`) en `spMaakReservering` (dynamische parameter-matching via `sys.parameters`, `_call_sp_dynamic`). `psAgendaPicker_GetAvailability` wordt op dezelfde dynamische manier aangeroepen voor het ophalen van beschikbaarheid. Dit is expliciet vastgelegd in `README.txt`.

**Gevolgen:** Elke nieuwe of gewijzigde databasebewerking moet als stored procedure worden geïmplementeerd/aangepast in SQL Server, niet als inline SQL in Python. De Python-laag blijft daarmee een dunne aanroep-/validatielaag; schemawijzigingen en business-regels leven in de database, buiten deze repo.

## 2026-09-01 — Buitendienst-beschikbaarheid in /availability zonder het gedeelde alias-mechanisme te wijzigen

**Context:** `AfspraakPlanner` (een apart project) riep al `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan voor `vorm_afspraak=buitendienst`, maar `AfspraakMaken`'s `/availability`-endpoint deed dat nog niet — die riep altijd de vaste `psAgendaPicker_GetAvailability` aan via `_call_sp_dynamic`. De nieuwe Buitendienst-SP verwacht `@Postcode4`, terwijl de inkomende payload (vanuit AgendaPicker) de key `postcode` gebruikt. `_call_sp_dynamic`'s gedeelde matching-logica (`_build_value_lookup`) wordt ook door `/reservering` gebruikt, en CLAUDE.md waarschuwt expliciet om dat mechanisme niet te wijzigen zonder de gevolgen voor beide endpoints te overzien.

**Beslissing:** in plaats van het gedeelde alias-mechanisme uit te breiden, bouwt een nieuwe helper `_prepare_availability_call` een lokale kopie van de payload met een `postcode4`-key erin, uitsluitend binnen `_handle_availability`. `/reservering` en zijn alias-mechanisme blijven volledig ongewijzigd. Welke stored procedure wordt aangeroepen (`psAgendaPicker_GetAvailability` vs. `psAgendaPicker_GetAvailabilityBuitendienst`) hangt af van `vorm_afspraak`, met dezelfde validatie als `AfspraakPlanner` (`vorm_afspraak` moet `'online'`/`'buitendienst'` zijn; `postcode` moet 4 cijfers zijn bij buitendienst).

**Gevolgen:** `/availability` ondersteunt nu zowel online- als buitendienst-beschikbaarheid, consistent met `AfspraakPlanner`'s implementatie. `psAgendaPicker_GetAvailabilityBuitendienst` moet nog op `Advitas_test`/productie uitgevoerd worden voordat dit end-to-end getest kan worden (zie `docs/TODO.md`) — tot die tijd geeft de buitendienst-tak een databasefout terug (procedure niet gevonden, of een rechten-gerelateerde fout als de procedure wel bestaat maar de gebruikte databasegebruiker er geen toegang toe heeft).

## 2026-09-01 — Root cause buitendienst-500 bevestigd: ontbrekende rechten voor svc-AppMaakAfspraak

**Context:** Na productie-deploy van de wijziging hierboven gaf `/availability` met `vorm_afspraak=buitendienst&run=prod` een generieke HTTP 500 (`"Interne fout bij uitvoeren van stored procedure."`) terug via AgendaPicker. `_handle_availability` heeft geen aparte `pyodbc.Error`-tak (anders dan `/reservering`), dus de echte SQL-foutmelding kwam niet in de response terecht. Handmatig uitvoeren van `dbo.psAgendaPicker_GetAvailabilityBuitendienst` in SSMS met dezelfde parameters (`@Date='20260907'`, `@Postcode4=N'1704'`) gaf wél correct resultaat (`Ardi Groot`) — dat sloot uit dat de SP zelf kapot was of ontbrak, en wees de aandacht naar rechtenverschil tussen de (persoonlijke) SSMS-login en het service-account `svc-AppMaakAfspraak` waarmee de Azure Function verbindt.

**Beslissing/Bevinding:** root cause was inderdaad ontbrekende rechten voor `svc-AppMaakAfspraak` op de productiedatabase — op `dbo.psAgendaPicker_GetAvailabilityBuitendienst` zelf en/of op de onderliggende tabellen (`PowerBI.AdviseurRegio`, `PowerBI.AgendaBuitenDienst`, `dbo.Adviseurs`) die de SP intern leest. Na het zetten van `GRANT EXECUTE`/`GRANT SELECT` op deze objecten werkt de buitendienst-flow end-to-end correct in AgendaPicker.

**Gevolgen:** het `docs/TODO.md`-item over deze blocker is afgevinkt. Openstaand vervolgpunt (niet in deze sessie opgepakt): `_handle_availability` mist nog een specifieke `pyodbc.Error`-tak met `_extract_db_error_details` (zoals `/reservering` die wel heeft) — zonder die tak zijn toekomstige databasefouten op `/availability` alleen zichtbaar via Application Insights, niet in de HTTP-response zelf.

## 2026-09-01 — pyodbc.Error-tak toegevoegd aan /availability

**Context:** het vervolgpunt hierboven — tijdens het debuggen van de buitendienst-500 was de echte SQL-foutmelding niet zichtbaar in de HTTP-response, omdat `_handle_availability` elke databasefout liet vallen in de generieke `except Exception`-tak (alleen `"Interne fout bij uitvoeren van stored procedure."`, geen details). `/reservering` heeft dit probleem niet: die heeft een aparte `except pyodbc.Error`-tak die `_extract_db_error_details(ex)` teruggeeft.

**Beslissing:** `_handle_availability` heeft nu dezelfde `except pyodbc.Error as ex`-tak vóór de generieke `except Exception`, met `conn.rollback()`, `logging.exception(...)`, en `_extract_db_error_details(ex)` in de response — identiek patroon aan `/reservering`. De generieke `except Exception`-tak blijft ongewijzigd voor niet-database-fouten.

**Gevolgen:** een toekomstige databasefout (bijv. een rechten-fout zoals in de vorige entry) is nu direct zichtbaar in de HTTP-response van `/availability`, zonder dat Application Insights geraadpleegd hoeft te worden.

## 2026-09-01 — Emailnotificatie naar planning@advitas.nl bij nieuwe reservering

**Context:** Het planningsteam (planning@advitas.nl) moet handmatig actie ondernemen op elke nieuwe reservering, maar had daar geen automatisch signaal voor. `/reservering` had tot nu toe geen enkele uitgaande afhankelijkheid buiten SQL Server.

**Beslissing:** bij elke succesvolle `/reservering`-aanroep (zowel het dynamische als het fallback-SP-pad) stuurt de functie een HTML-mail naar `planning@advitas.nl` via Microsoft Graph's `sendMail`-API, met dezelfde OAuth2 client-credentials-authenticatie als `PhytonFuncties/sharepoint_pdf_sync.py` (env-vars `SHAREPOINT_TENANT_ID`/`SHAREPOINT_CLIENT_ID`/`SHAREPOINT_CLIENT_SECRET`, met `AZURE_TENANT_ID`/`AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET` als fallback). De mail bevat het reserveringsnummer, kernvelden (datum/tijd/adviseur_id/duur_kwartieren/klant_id/campagne_id/campagne_naam/naam/email) en een vangnet voor overige SP-output-velden. De stap is non-blocking: een mislukte mail (`_try_send_reservering_email`) wordt alleen gelogd en verandert de `/reservering`-response nooit. De mail wordt altijd verstuurd, ook bij testruns (`run` != `prod`) — met een `[TEST]`-prefix in het onderwerp en een waarschuwingsbanner in de body, zodat het planningsteam een testreservering niet aanziet voor een echte.

**Gevolgen:** `/reservering` heeft nu voor het eerst een uitgaande HTTP-afhankelijkheid buiten SQL Server (nieuwe dependency `requests`). De app-registratie die `SHAREPOINT_TENANT_ID`/`CLIENT_ID`/`CLIENT_SECRET` (of `AZURE_*`) vertegenwoordigt moet `Mail.Send`-rechten hebben voor `planning@advitas.nl` — dat is niet in deze sessie geverifieerd of geregeld (geen tenant-toegang). Zonder die rechten faalt het versturen stil (alleen zichtbaar in Application Insights via `logging.exception`), de reservering zelf blijft wél gewoon succesvol.

## 2026-09-01 — Reserverings-mail: Microsoft Graph vervangen door Mandrill

**Context:** Advitas gebruikt Mandrill al elders (een bestaande Logic App verstuurt herzend-campagnemails via Mandrill's transactional-send-API, met `from_email: planning@advitas.nl`) — een werkende Mandrill API-key met verstuurrechten was dus al beschikbaar. Dat maakt de nog onopgeloste `Mail.Send`-rechten-afhankelijkheid van de Graph-aanpak hierboven overbodig: Mandrill heeft alleen een API-key nodig, geen tenant-admin-actie voor app-registratie-permissies.

**Beslissing:** `_send_reservering_email` roept nu `https://mandrillapp.com/api/1.0/messages/send.json` aan met de API-key uit env-var `MANDRILL_API_KEY` (nooit hardcoded, ondanks dat de bestaande Logic App dat wél doet — expliciet zo gehouden, zie Kritieke Regels in `CLAUDE.md`). `_get_graph_access_token` is verwijderd (dode code); `_require_any_env` blijft en wordt nu voor `MANDRILL_API_KEY` gebruikt. `_build_reservering_email` (de pure content-bouwer voor onderwerp/HTML-body) is ongewijzigd — die is transportmechanisme-onafhankelijk gebleven, wat de vervanging tot een geïsoleerde wijziging maakte. De non-blocking garantie (`_try_send_reservering_email`) is ongewijzigd van toepassing.

**Gevolgen:** de eerdere `SHAREPOINT_TENANT_ID`/`CLIENT_ID`/`CLIENT_SECRET`-vermelding in `local.settings.json.example` is vervangen door `MANDRILL_API_KEY`. Enige overgebleven open punt: bevestigen dat de env-var `MANDRILL_API_KEY` in de Function App's App Settings staat (nog niet geverifieerd in deze sessie).

## 2026-09-01 — Reserverings-mail uitgebreid: link naar Agenda Tool, adviseursnaam bewust weggelaten

**Context:** het planningsteam wilde ook de adviseursnaam, klantnaam, klant-e-mailadres en een link naar de reserveringsdetails in Agenda Tool (`https://agendatooling-f7ffdgaheqgbhnb0.westeurope-01.azurewebsites.net?reservering=<nummer>`) in de mail. Klantnaam/e-mailadres stonden al in de mail (payload-velden `naam`/`email`), alleen generiek gelabeld. De adviseursnaam staat nergens in de payload of in de SP-output (alleen het numerieke `adviseur_id`) — tonen zou een nieuwe, losse `SELECT` op `dbo.Adviseurs` vereisen, buiten `spMaakReservering` om. Dat is geen write dus niet in strijd met de "nooit directe INSERT/UPDATE"-regel, maar wél een nieuw patroon voor `/reservering` (dat tot nu toe uitsluitend via de stored procedure met de database praat) — voorgelegd aan de gebruiker.

**Beslissing:** de gebruiker koos ervoor de adviseursnaam te laten vervallen — `/reservering` blijft dus uitsluitend via `spMaakReservering` communiceren, geen nieuwe losse SELECT. De labels "Naam"/"Email" in `_build_reservering_email` zijn hernoemd naar "Klant naam"/"Klant e-mailadres" ter verduidelijking. Een knop-achtige link naar Agenda Tool is toegevoegd, maar alleen wanneer `reservering_id` bekend is (anders zou de link naar `?reservering=onbekend` wijzen, wat niets nuttigs oplevert).

**Gevolgen:** adviseur-informatie in de mail blijft beperkt tot het numerieke `adviseur_id` (zoals het al was). Mocht de adviseursnaam later alsnog gewenst zijn, dan is een nieuwe SELECT op `dbo.Adviseurs` (met ondersteuning voor meerdere adviseur_id's, aangezien dat veld een CSV kan zijn) de aangewezen aanpak — opnieuw voorleggen vóór implementatie.

## 2026-09-03 — Afspraak wijzigen via e-mail-pincode, pincode-opslag in Azure Table Storage

**Context:** een klant moest zonder in te loggen de datum/tijd/adviseur/vorm van een bestaande afspraak
kunnen wijzigen. Een letterlijk "tijdelijk bestand" op de Function App (zoals oorspronkelijk gevraagd) is
niet betrouwbaar op een Azure Functions Consumption-plan (meerdere instanties, geen gegarandeerd gedeelde
lokale schijf tussen aanroepen).

**Beslissing:** de pincode (+ afspraak_id, adviseur_id, duur_kwartieren, vorm_afspraak, postcode, run)
wordt 5 minuten bewaard in Azure Table Storage, via de bestaande `AzureWebJobsStorage`-connectie (geen
nieuwe externe dienst, wel de nieuwe dependency `azure-data-tables`). Drie nieuwe endpoints
(`/wijzig-aanvraag`, `/wijzig-verificatie`, `/wijzig-opslaan`) volgen dezelfde vaste-parameter-mapping-stijl
als `/afspraak`. De daadwerkelijke opslag loopt via een nieuwe stored procedure
`spWijzigAfspraakDatumTijd` die nog gebouwd moet worden buiten deze repo (zie `docs/TODO.md`).

**Gevolgen:** `/wijzig-opslaan` faalt met een databasefout totdat de stored procedure bestaat in
`SQL_DATABASE_TEST`/productie. Pincodes zijn one-time-use (verwijderd na succesvolle opslag), 5 minuten
geldig, max. 5 foute pogingen; foutmeldingen bij verificatie lekken bewust geen detail over de exacte
reden van afwijzing. De drie nieuwe endpoints zijn alleen syntactisch/statisch geverifieerd in deze sessie
— `local.settings.json` ontbrak in de checkout (mag ook niet door Claude aangemaakt worden, zie
Kritieke Regels in `CLAUDE.md`), dus live curl-verificatie tegen `SQL_DATABASE_TEST` en een echte Storage
Account staat nog open (zie `docs/TODO.md`).

## 2026-09-03 — Concreet voorstel voor spWijzigAfspraakDatumTijd op basis van het echte Afspraak-schema

**Context:** de gebruiker deelde de broncode van `[PowerBI].[usp_Reservering_OmzettenNaarAfspraak]` (de
bestaande SP die een reservering omzet naar een afspraak), wat voor het eerst het echte schema van
`[dbo].[Afspraak]` blootlegt: kolommen `klant_id`, `saleop_id`, `adviseur_id`, `datum_adviesgesprek`,
`tijd_adviesgesprek`, `[afspraakstate-id]`, `[insteek-id]`, `[prodcat-id]`, `vorm_afspraak`, `duur`,
`opm_afspraak`, `datum_gepland`, `Check_belangrijk`, `check_inbehandeling`, `created_at`, `updated_at`.
Opvallend: `tijd_adviesgesprek` bevat (via de COALESCE/TRY_CONVERT-fallback in die SP) de volle datum+tijd,
niet alleen het tijdsdeel; `vorm_afspraak` wordt daar hardcoded als `N'Online'` weggeschreven (Titel-case).

**Beslissing:** een concreet voorstel voor `spWijzigAfspraakDatumTijd` is toegevoegd als
`sql/spWijzigAfspraakDatumTijd.sql` (nieuwe map, naar analogie van het `sql/`-mapje dat AgendaPicker en
AfspraakPlanner al gebruiken voor SP-scripts). Het contract (parameternamen/types) is ongewijzigd t.o.v. de
eerdere ADR — alleen het `UPDATE`-lichaam is nu ingevuld, met dezelfde TRY/CATCH/transactie-stijl als
`usp_Reservering_OmzettenNaarAfspraak`. Twee aannames zijn NIET bevestigd en moeten vóór uitvoering
geverifieerd worden: (1) de PK-kolom van `[dbo].[Afspraak]` heet `[afspraak_id]` — het aangeleverde
script bevat geen WHERE-lookup op de PK, dus dit is puur naamgevingsconsistentie met de rest van de
codebase, geen bevestigd feit; (2) `vorm_afspraak = 'Buitendienst'` is een aanname naar analogie met het
bevestigde `'Online'`.

**Gevolgen:** dit script is NIET uitgevoerd en NIET getest — Claude heeft geen SQL-uitvoeringstoegang.
Een DBA (of Rob/Daniel) moet het reviewen, de twee aannames verifiëren tegen het echte
`[dbo].[Afspraak]`-schema, en het handmatig uitvoeren op `SQL_DATABASE_TEST` vóór `/wijzig-opslaan`
end-to-end getest kan worden.

## 2026-09-03 — spWijzigAfspraakDatumTijd logt de wijziging ook in [dbo].[actions]

**Context:** de gebruiker gaf aan dat een afspraakwijziging, net als de bestaande
`usp_Reservering_OmzettenNaarAfspraak`-flow, ook een rij in `[dbo].[actions]` moet wegschrijven, en
leverde de exacte `INSERT`-kolomlijst plus een parametertabel met de waarden voor het
"Afspraakwijziging"-scenario aan: `action_type_id` = `PLANNING_MOVE_ACTION_TYPE_ID`
(`17AE20FB-8E45-4201-8FB8-952FB2C8CA4F`), `state_id` = `35` (hardcoded), `source` = `'Manual (Swap)'`,
`role` = `'telemarketer'`, `field_contents_1/2/3` = afspraak-ID/nieuwe adviseur-ID/nieuwe datum+tijd,
`auto_type` = `'manual'`, `creator_id` = "FK-veilig opgelost (ingelogde gebruiker, anders eerste rij
dbo.users)".

**Beslissing:** `sql/spWijzigAfspraakDatumTijd.sql` voegt, ná de succesvolle `UPDATE` op
`[dbo].[Afspraak]` en binnen dezelfde transactie, deze `actions`-insert toe met exact de aangeleverde
kolomlijst en waarden. Omdat deze SP wordt aangeroepen door de AfspraakMaken Azure Function
(function-key-auth, geen ingelogde gebruiker) is er nooit een "ingelogde gebruiker"-context beschikbaar —
`creator_id` gebruikt daarom altijd de fallback naar de eerste rij van `dbo.users` (`SELECT TOP 1 [id]
FROM dbo.users`, zonder `ORDER BY`). Kolommen die niet in de aangeleverde parametertabel stonden
(`direction`, `product_id`, `tag`, `communication`, `Oorsprong`, `Oorsprong_categorie`,
`field_contents_4` t/m `field_contents_12` behalve 1-3, `insteek_id`) zijn op `NULL` gezet.

**Gevolgen:** nog twee aannames toegevoegd aan de openstaande verificatielijst (zie
`sql/spWijzigAfspraakDatumTijd.sql`, bovenaan): (1) `dbo.users` heeft een PK-kolom `[id]`; (2) `TOP 1`
zonder `ORDER BY` op `dbo.users` is voor deze SP acceptabel — als er een vaste systeemgebruiker moet zijn,
moet dat vóór uitvoering aangepast worden. De NULL-gezette kolommen moeten door de business
gecontroleerd worden op of ze daadwerkelijk leeg mogen blijven voor dit scenario.

## 2026-09-03 — Pincode-mail tijdelijk omgeleid naar rvader@advitas.nl

**Context:** tijdens het testen van deze feature wilde de gebruiker de pincode-mail niet naar echte
klant-e-mailadressen laten gaan, maar naar zijn eigen adres, zonder daarvoor eerst een lokale
`local.settings.json` te hoeven opzetten (die ontbreekt in deze checkout, zie eerdere ADR's).

**Beslissing:** `_send_wijzig_email` leest env var `WIJZIG_MAIL_OVERRIDE_TO`; als die leeg is, valt de
code terug op de hardcoded constante `WIJZIG_MAIL_OVERRIDE_TO_DEFAULT = "rvader@advitas.nl"` in plaats van
het opgegeven klant-e-mailadres. De mail zelf krijgt in dat geval een extra gele notitie
("Tijdelijke testmail-omleiding: normaal zou dit bericht naar `<echte adres>` zijn verstuurd.") zodat
tijdens het testen nog te zien is voor welke klant de mail eigenlijk bedoeld was. Dit is bewust als
code-default geïmplementeerd (niet alleen als optionele env var) zodat het meteen werkt zonder
`local.settings.json`-wijziging.

**Gevolgen:** zolang deze default in de code staat, komt GEEN pincode-mail ooit bij een echte klant aan —
ook niet in productie als `WIJZIG_MAIL_OVERRIDE_TO` daar niet expliciet leeg gezet wordt. Dit moet
verwijderd worden vóór een release naar echte klanten (zie `docs/TODO.md`). Om het te deactiveren: zet
`WIJZIG_MAIL_OVERRIDE_TO` op een lege string in de App Settings, of verwijder de default-constante uit de
code.

## 2026-09-03 — Afspraak-bevestigingsmail met wijzig-knop, UIT by default

**Context:** de wijzig-afspraak-flow (pincode + AgendaPicker) is af, maar er was nog geen manier voor een
klant om 'm daadwerkelijk te starten — de "autostart"-link (ADR-003 in AgendaPicker) heeft een
afzender nodig. De gebruiker vroeg om een "Afspraak wijzigen"-knop in de afspraak-bevestiging.

**Beslissing:** `/afspraak` (POST) kan nu, ná een succesvolle aanmaak, een bevestigingsmail naar de klant
sturen (`_build_afspraak_bevestiging_email`/`_send_afspraak_bevestiging_email`/
`_try_send_afspraak_bevestiging_email`, non-blocking zoals de andere mail-helpers). De mail toont
datum/tijd/vorm (geen interne ids zoals adviseur_id — bewust weggelaten, consistent met de eerdere
beslissing om adviseur-info aan klanten te beperken) en een "Afspraak wijzigen"-knop die naar
`wijzig-afspraak.html` linkt met `autostart=1` + alle velden die `/wijzig-aanvraag` nodig heeft
(afspraak_id, email, adviseur_id — de eerste uit de lijst, duur_kwartieren, vorm_afspraak, postcode bij
buitendienst, run). `_parse_payload` accepteert nu ook een optioneel `postcode`-veld (nodig voor de
buitendienst-tak van de link). **Bewust UIT by default** (`AFSPRAAK_BEVESTIGING_MAIL_ENABLED`, default
`"false"`): `/afspraak` is een bestaand, al in productie actief endpoint dat door andere systemen wordt
aangeroepen — een e-mail-side-effect zomaar aanzetten zou ongemerkt echte klanten gaan mailen zodra deze
wijziging gedeployed wordt. De mail respecteert (tijdelijk) dezelfde `WIJZIG_MAIL_OVERRIDE_TO` als de
pincode-mail (zie vorige ADR).

**Gevolgen:** zonder `AFSPRAAK_BEVESTIGING_MAIL_ENABLED=true` verandert er niets aan het bestaande gedrag
van `/afspraak`. Pas nadat de hele wijzig-flow end-to-end getest is (incl. `spWijzigAfspraakDatumTijd`,
zie eerdere ADR's) moet deze env var op `true` gezet worden — anders krijgen klanten een knop die naar
een nog niet werkende flow leidt. De knop verschijnt alleen als er een `afspraak_id`, minstens één
`adviseur_id` én een `email` bekend zijn; ontbreekt een van die, dan wordt de bevestigingsmail wel
verstuurd (als er een e-mailadres is) maar zonder wijzig-knop.

## 2026-09-03 — Herontwerp: wijzig-flow start met e-mailadres, pincode-opslag verhuist naar SQL

**Context:** de tot dan toe gebouwde flow ging uit van een `afspraak_id` in de link (uit de
bevestigingsmail) — de klant hoefde alleen een pincode in te vullen. De gebruiker wilde in plaats daarvan
dat de klant zelf zijn e-mailadres invult op een neutraal startscherm, waarna het systeem zelf de
bijbehorende afspraak opzoekt (en afwijst als er geen geldige afspraak is). Dit sluit meteen het
beveiligingsgat dat de eerdere `autostart`-link had geïntroduceerd (iemand kon een willekeurige
`afspraak_id` + eigen e-mailadres in de URL zetten en zo een pincode voor andermans afspraak krijgen) —
met e-mail-eerst moet je eerst bewijzen dat je bij dat postvak kunt, ongeacht welk `afspraak_id` erbij
hoort. Daarnaast wilde de gebruiker de pincode-opslag in een SQL-tabel i.p.v. Azure Table Storage.

**Beslissing:** drie nieuwe stored procedures (`spZoekAfspraakVoorWijziging`, `spBewaarWijzigPincode`,
`spValideerWijzigPincode`) + een nieuwe tabel `dbo.WijzigAfspraakPincodes` vervangen de Azure Table
Storage-opslag volledig (zie `sql/`). `spZoekAfspraakVoorWijziging` zoekt via een (aangenomen) `Klanten`-
tabel naar de klant bij een e-mailadres, en pakt diens eerstvolgende toekomstige afspraak met status
'Open' — wordt die niet gevonden, dan wordt er bewust geen pincode gegenereerd/verstuurd (zelfde
informatie-lek-preventie als bij pincode-verificatie: niet laten zien of een e-mailadres wel/niet bekend
is). `spWijzigAfspraakDatumTijd` is uitgebreid met een `DELETE` op de pincode-tabel na succesvolle
opslag (one-time use), zodat Python dat niet los hoeft te doen.

**Gevolgen:** dit vervangt het net gebouwde `autostart`-mechanisme (AgendaPicker ADR-003) grotendeels —
een link hoeft alleen nog naar de wijzig-pagina te wijzen, zonder `afspraak_id`/`adviseur_id`/etc. als
query-parameters (die kwamen uit de aanroeper, nu uit de database). Er komen nu in totaal **4 nieuwe SP's
+ 1 nieuwe tabel** te wachten op uitvoering tegen `SQL_DATABASE_TEST`/productie, bovenop de al bestaande
`spWijzigAfspraakDatumTijd` (zie `docs/TODO.md`). De aanname over de Klanten-tabel (`dbo.Klanten`,
kolommen `klant_id`/`email`) is niet bevestigd — AgendaPicker's eigen `server.js` detecteert dit
schema juist dynamisch omdat het kan variëren.

## 2026-09-03 — function_app.py bijgewerkt naar de e-mail-eerst-flow

**Context:** vervolg op de vorige ADR — de SQL-laag (3 nieuwe SP's + tabel) was ontworpen, nu is de
Python-kant (`function_app.py`) daadwerkelijk aangepast om die aan te roepen.

**Beslissing:** de Azure Table Storage-helpers (`_bewaar_pincode_record`/`_haal_pincode_record`/
`_verwijder_pincode_record`/`_verhoog_pincode_pogingen`/`_get_pincode_table_client`) en de
`azure-data-tables`-dependency zijn volledig verwijderd, vervangen door `_call_sp_zoek_afspraak_voor_wijziging`/
`_call_sp_bewaar_wijzig_pincode`/`_call_sp_valideer_wijzig_pincode`. `/wijzig-aanvraag` accepteert nu
alleen `{ email, run }` — geen afspraak_id/adviseur_id/duur_kwartieren/vorm_afspraak/postcode meer van de
aanroeper nodig, die komen nu uit `spZoekAfspraakVoorWijziging`. Wordt er geen afspraak gevonden: HTTP 404,
geen mail verstuurd. `/wijzig-verificatie` en `/wijzig-opslaan` accepteren nu `email`+`pincode` i.p.v.
`afspraak_id`+`pincode`; `/wijzig-opslaan` haalt `afspraak_id` server-side uit de pincode-validatie in
plaats van een door de client meegestuurde waarde te vertrouwen — een extra beveiligingsverbetering
bovenop het email-eerst-principe zelf. De afspraak-bevestigingsmail's "Afspraak wijzigen"-knop
(`_build_afspraak_bevestiging_email`) is vereenvoudigd: linkt nu naar `wijzig-afspraak.html?email=...`
(alleen ter voorinvulling) in plaats van de oude `autostart=1`-link met alle losse parameters.

**Gevolgen:** de code is syntactisch geverifieerd maar nog niet live getest (vereist de 4 nieuwe SP's +
tabel + een lokale `local.settings.json`, zie `docs/TODO.md` voor de bijgewerkte curl-voorbeelden).
AgendaPicker's `wijzig-afspraak.html`/`.js` en de proxy-routes in `server.js` moeten nog aangepast worden
aan dit nieuwe contract (autostart-mechanisme wordt vervangen door een echt e-mail-invoerscherm) — dat is
de volgende stap.

## 2026-09-03 — [dbo].[Afspraak]'s PK-kolom bevestigd als [afspraak-id] (met koppelteken)

**Context:** alle SQL-voorstellen tot nu toe namen aan dat de PK-kolom van `[dbo].[Afspraak]`
`[afspraak_id]` (underscore) heette — expliciet gemarkeerd als onbevestigde aanname, omdat het
aangeleverde `usp_Reservering_OmzettenNaarAfspraak`-script geen directe lookup op die kolom deed (alleen
een `INSERT` + `SCOPE_IDENTITY()`). De gebruiker bevestigde dat de kolom `[afspraak-id]` heet, **met
koppelteken** — consistent met het al zichtbare patroon `[afspraakstate-id]`/`[insteek-id]`/`[prodcat-id]`
in datzelfde script.

**Beslissing:** alle `WHERE`/`SELECT`-referenties naar `[dbo].[Afspraak]`'s PK in
`sql/spZoekAfspraakVoorWijziging.sql`, `sql/spValideerWijzigPincode.sql`, `sql/spWijzigAfspraakDatumTijd.sql`
en `sql/alles_in_1_wijzig_afspraak.sql` zijn aangepast naar `[afspraak-id]`. Expliciet **niet** gewijzigd:
(1) de `@afspraak_id`-parameternamen van onze eigen SP's (ons eigen contract, geen bestaande kolom); (2)
`[dbo].[actions].[afspraak_id]` (die tabel gebruikt bevestigd wél underscore, letterlijk zo aangeleverd in
het originele script); (3) `[dbo].[WijzigAfspraakPincodes].[afspraak_id]` (onze eigen nieuwe tabel, eigen
naamgevingsconventie, sluit niet aan op een bestaand schema).

**Gevolgen:** dit lost aanname #1 uit alle eerdere ADR's/TODO-items op — de belangrijkste onzekerheid in
`spWijzigAfspraakDatumTijd`/`spZoekAfspraakVoorWijziging`/`spValideerWijzigPincode` is nu weggenomen. De
resterende aannames (Klanten-tabelschema, vorm_afspraak-schrijfwijze 'Buitendienst', dbo.users-PK, NULL-
gezette actions-kolommen) staan nog open, zie `docs/TODO.md`.

## 2026-09-03 — Alle wijzig-afspraak-SQL succesvol uitgevoerd tegen de database

**Context:** de gebruiker heeft `sql/alles_in_1_wijzig_afspraak.sql` uitgevoerd. Een eerste poging gaf
"Invalid column name 'afspraak_id'"-fouten — bleek een verouderde, niet-ververste kopie van het script te
zijn (van vóór de `[afspraak-id]`-koppelteken-fix). Na het opnieuw ophalen van de actuele versie is alles
zonder fouten uitgevoerd.

**Beslissing/Bevinding:** de tabel `dbo.WijzigAfspraakPincodes` en de vier stored procedures
(`spZoekAfspraakVoorWijziging`, `spBewaarWijzigPincode`, `spValideerWijzigPincode`,
`spWijzigAfspraakDatumTijd`) staan nu op de database, met de bijbehorende GRANT's voor
`svc-AppMaakAfspraak`. Dit bevestigt impliciet ook de eerder openstaande kolomnaam-aannames
(`[dbo].[Klanten].[klant_id]`/`[email]`/`[postcode]`, `dbo.users.[id]`) — `CREATE PROCEDURE` had anders
dezelfde "Invalid column name"-fout gegeven als bij `afspraak-id`.

**Gevolgen:** de wijzig-afspraak-flow heeft geen openstaande database-blockers meer. Enige resterende
stap vóór live testen: een lokale `local.settings.json` (AfspraakMaken) en `.env` (AgendaPicker), plus
deployen van beide apps naar Azure (zie `docs/TODO.md`). De data-/businessaannames (vorm_afspraak =
'Buitendienst', NULL-gezette actions-kolommen) zijn nog niet functioneel geverifieerd — dat vergt een
echte end-to-end-test, niet alleen een geslaagde SP-compilatie.

## 2026-09-03 — Route-namen hernoemd naar underscore, gelijk aan de Python-functienamen

**Context:** tijdens het testen bleek Azure Portal's Functions-lijst de drie nieuwe functies te tonen
als `wijzig_aanvraag`/`wijzig_opslaan`/`wijzig_verificatie` (underscore — dat is simpelweg de
Python-functienaam, Python staat geen koppeltekens toe in identifiers). De HTTP-route zelf werd echter
apart bepaald via `@app.route(route="wijzig-aanvraag", ...)` (koppelteken). Dit verschil tussen de naam
in Portal en de echte URL zorgde herhaaldelijk voor verwarring bij het configureren van
`AFSPRAAK_WIJZIG_*_URL` in AgendaPicker — een env var werd meermaals op de verkeerde variant gezet,
telkens resulterend in een lege-body-404 (route-laag kent de URL niet).

**Beslissing:** de `route=`-parameter van alle drie de routes is aangepast naar underscore
(`wijzig_aanvraag`, `wijzig_verificatie`, `wijzig_opslaan`), zodat de URL nu exact overeenkomt met wat
Azure Portal al toonde. Dit is een bewuste afwijking van de bestaande routenaam-conventie in dit project
(`afspraak`, `reservering`, `availability`, `wijzig-aanvraag` gebruikten tot nu toe geen underscores) —
maar de verwarring die het koppelteken-verschil veroorzaakte woog zwaarder dan naamgevingsconsistentie
met de oudere routes.

**Gevolgen:** dit is een breaking change voor de URL-contracten — vereist een nieuwe deploy van
AfspraakMaken, én het aanpassen van `AFSPRAAK_WIJZIG_AANVRAAG_URL`/`AFSPRAAK_WIJZIG_VERIFICATIE_URL`/
`AFSPRAAK_WIJZIG_OPSLAAN_URL` in AgendaPicker's App Settings naar de underscore-paden (bijv.
`.../api/wijzig_aanvraag`). Zie `docs/TODO.md` voor de bijgewerkte curl-voorbeelden.

---

## 2026-09-07 — `agenda` afgeleid en toegevoegd aan `/wijzig_verificatie`-response

**Context:** AgendaPicker's kalenderstap in de wijzig-flow roept `/api/availability` aan, en die
procedure (`dbo.psAgendaPicker_GetAvailability`) heeft `agenda`, `duur` en `adviseur_id` nodig om de
juiste beschikbaarheid te tonen. Deze gegevens moeten uit de te wijzigen afspraak zelf komen (verzoek
van de gebruiker: *"De payload naar de availability moet ook nog allelrlei info mee krijgen. agenda,
duur, adviseur_id. Die moeten uit de tewijzigen afspraak komen"*). `duur` en `adviseur_id` kwamen al
terug via `/wijzig_verificatie` (zie de 2026-09-03 e-mail-eerst-herontwerp hierboven); `agenda` niet —
die staat niet direct als kolom op `[dbo].[Afspraak]`, maar moet worden afgeleid.

**Beslissing:** `agenda` afleiden uit `insteek_id`/`prodcat_id` van de afspraak, volgens een mapping die
de gebruiker expliciet heeft aangeleverd:
- `insteek_id = 5` → `hypotheek`
- `insteek_id = 1` → `vermogen`
- `insteek_id = 35` én `prodcat_id = 22` → `schade`

(De gebruiker noemde voor die laatste combinatie ook `oakk` en `service` als mogelijke betekenis, maar
AgendaPicker's `/api/availability` accepteert alleen `hypotheek`/`vermogen`/`schade` als agenda-filter
— dus `schade` is in deze context de enige bruikbare waarde.) De afleiding zit in
`spValideerWijzigPincode` (nieuwe `@agenda NVARCHAR(20) OUTPUT`-parameter, ook bijgewerkt in
`sql/alles_in_1_wijzig_afspraak.sql`), en `function_app.py`'s `/wijzig_verificatie`-route geeft
`agenda` nu mee in de response.

**Gevolgen:** vereist een nieuwe deploy van zowel de aangepaste stored procedure als `function_app.py`
vóórdat AgendaPicker's kalenderstap er iets mee kan doen. **Niet bevestigd:** of `[dbo].[Afspraak]`'s
kolommen `[insteek-id]`/`[prodcat-id]` een koppelteken gebruiken (aangenomen, naar analogie van
`[afspraakstate-id]`) — vóór uitvoeren van de SQL controleren, anders geeft de procedure een "Invalid
column name"-fout (zelfde foutklasse als de eerdere `afspraak-id`-typo, zie ADR hierboven van
2026-09-03).

---

## 2026-09-07 — Knop verwijderd uit de pincode-mail

**Context:** de pincode-mail (`_build_wijzig_email`) bevatte een "Wijzig uw afspraak"-knop die naar
`wijzig-afspraak.html?email=...` linkte. Sinds het e-mail-eerst-herontwerp (zie ADR van 2026-09-03) is
die knop overbodig: de klant is al op die pagina wanneer de pincode wordt aangevraagd (het is de pagina
zélf die het e-mailadres uitvraagt en de aanvraag triggert), dus de knop leidde alleen terug naar waar
de klant al stond. Expliciet verzoek van de gebruiker: *"in het pincode mailtje hoeft geen knop te
zitten"*.

**Beslissing:** de knop (en de nu ongebruikte `link_url`/`agendapicker_base`-opbouw) verwijderd uit
`_build_wijzig_email` in `function_app.py`. De mail toont alleen nog de pincode zelf plus de
test-/override-banners.

**Gevolgen:** geen — dit is een geïsoleerde wijziging in de e-mail-body, geen wijziging aan de
`AGENDAPICKER_BASE_URL`-env var (die blijft in gebruik voor de link in de afspraak-bevestigingsmail,
zie eerdere ADR).

---

## 2026-09-07 — `/wijzig_opslaan` controleert de pincode niet meer bij opslaan

**Context:** sinds het e-mail-eerst-herontwerp (ADR van 2026-09-03) werd `afspraak_id` bij zowel
`/wijzig_verificatie` als `/wijzig_opslaan` altijd server-side afgeleid uit een geslaagde
pincode-hervalidatie — bewust, om te voorkomen dat een client een willekeurige `afspraak_id` kon
meesturen. In de praktijk bleek dit te knellen: de pincode is 5 minuten geldig, en een klant die
langer dan dat in de AgendaPicker-kalender aan het kiezen is (bijv. tussen meerdere maanden bladert),
kreeg bij het klikken op "Opslaan" een "ongeldige of verlopen pincode"-fout, ondanks dat diezelfde
klant een paar minuten eerder wél een geldige pincode had ingevoerd. De gebruiker vroeg expliciet:
*"als ik in het datum keuze grid zit en ik wil opslaan dan moet er niet meer gekontroleerd te worden
of de pin nog geldig is"*.

Voordat dit geïmplementeerd werd, is de gebruiker gevraagd te kiezen tussen twee opties: (1) alleen de
5-minuten-vervaltermijn loslaten bij opslaan, met behoud van de pincode-juistheidscontrole (en dus
behoud van de server-side afspraak_id-afleiding), of (2) de pincode-controle bij opslaan volledig
weglaten. De gebruiker koos expliciet voor optie (2), met de beschreven consequentie (afspraak_id moet
dan van de client komen) vooraf duidelijk gemaakt.

**Beslissing:** `/wijzig_opslaan` roept `_call_sp_valideer_wijzig_pincode` niet meer aan.
`_parse_wijzig_opslaan_payload` vereist nu `afspraak_id` (int) in de request body i.p.v.
`email`/`pincode`, en dat `afspraak_id` wordt rechtstreeks doorgegeven aan
`[dbo].[spWijzigAfspraakDatumTijd]`. `/wijzig_verificatie` is **niet** gewijzigd — die blijft de
pincode volledig valideren (juistheid, vervaltermijn, max pogingen) zoals voorheen, dat is en blijft de
enige plek waar de identiteit van de klant daadwerkelijk gecontroleerd wordt in deze flow.

**Gevolgen:** dit is een bewuste, expliciet door de gebruiker gekozen afwijking van het eerder
vastgelegde beveiligingsprincipe "`afspraak_id` komt nooit van de client". Concreet risico: wie een
`afspraak_id` kent of raadt (het is een oplopend integer, dus optellen/aftrekken van een bekende waarde
volstaat al), kan via `/wijzig_opslaan` diens datum/tijd/adviseur wijzigen zonder enige
identiteitscontrole op dat moment — de eerdere pincode-verificatie bij `/wijzig_verificatie` garandeert
niets meer over wie uiteindelijk de opslaan-aanroep doet. AgendaPicker's `server.js` en
`wijzig-afspraak.js` zijn aangepast om `afspraak_id` (uit de eerdere verificatiestap, lokaal
onthouden) mee te sturen i.p.v. `email`/`pincode` — zie AgendaPicker's `docs/DECISIONS.md`. Overweeg
bij een go-live naar echte klanten alsnog een lichtere vorm van bescherming (bijv. een kortlevende,
ondertekende token die bij `/wijzig_verificatie` wordt afgegeven en bij `/wijzig_opslaan` wordt
geverifieerd, zonder de 5-minuten-tijdsdruk van de pincode zelf).

---

## 2026-09-07 — Postcode voor buitendienst-beschikbaarheid komt uit het afspraak-adres, niet uit Klanten

**Context:** de gebruiker meldde een 400-fout vanuit `/api/availability` bij `vorm_afspraak=Buitendienst`
("Parameter postcode is verplicht..."), met de volgende toelichting: *"bij een buitendienst moet een
postcod worden meegestuurd. Die staat in in de afspraak via de adressid naar dbo.adres [Adres-id]
afspraak adres_sleutel. De PKD (eerste 4 moet worden doorgegeven"*. Tot nu toe kwam `@postcode` in
`spZoekAfspraakVoorWijziging` uit `[dbo].[Klanten].[postcode]` (klantgegevens), en `spValideerWijzigPincode`
gaf simpelweg de eerder opgeslagen waarde uit `[dbo].[WijzigAfspraakPincodes]` terug (kon dus verouderd
zijn, in tegenstelling tot alle andere afspraak-velden die daar wél vers herquery't worden). Beide
kloppen niet met wat de gebruiker aangeeft: de postcode hoort bij het **afspraak-adres**, niet bij de
klant in het algemeen.

**Beslissing:** beide stored procedures leiden `@postcode` nu af via
`[dbo].[Afspraak].[adres_sleutel]` (FK) -> `[dbo].[Adres].[Adres-id]` (PK) -> `LEFT([PKD], 4)`.
`spValideerWijzigPincode` doet dit vers bij elke aanroep (consistent met hoe de andere afspraak-velden
daar al werken), niet meer uit de opgeslagen pincode-rij. `[dbo].[WijzigAfspraakPincodes]`'s eigen
`postcode`-kolom blijft ongebruikt bestaan (geen schemawijziging, buiten scope van deze fix).

**Gevolgen:** vereist een nieuwe deploy van `spZoekAfspraakVoorWijziging.sql` en
`spValideerWijzigPincode.sql` (en de bijgewerkte `alles_in_1_wijzig_afspraak.sql`) vóórdat
buitendienst-afspraken via deze flow gewijzigd kunnen worden. **Niet geverifieerd:** de kolomnamen
`adres_sleutel`/`Adres-id`/`PKD` komen alleen uit de tekst van de gebruiker, niet gecontroleerd tegen
het echte schema (bijv. via `sp_help '[dbo].[Adres]'`) — bij een afwijkende naam geeft dit dezelfde
"Invalid column name"-fout als eerdere schema-aannames in deze flow.

---

## 2026-09-07 — Alle wijzig-afspraak-SQL idempotent gemaakt

**Context:** de gebruiker vroeg: *"kan je alles sql zo maken dat ik die kan runnen zonder na e
denken"*. `sql/alles_in_1_wijzig_afspraak.sql` bevatte een plain `CREATE TABLE`/`CREATE INDEX` voor
`[dbo].[WijzigAfspraakPincodes]` — die tabel staat inmiddels al op de database (zie de eerdere ADR
"Alle wijzig-afspraak-SQL succesvol uitgevoerd"), dus een herhaalde run van het hele bestand (bijv. na
een volgende SP-wijziging zoals de agenda- of postcode-aanpassing hierboven) zou daar meteen op
stuklopen met een "already exists"-fout — de gebruiker zou dan zelf moeten weten welk deel van het
bestand over te slaan. Bovendien bleek `sql/WijzigAfspraakPincodes_rechten.sql` (het losse
rechten-bestand) stale te zijn geworden t.o.v. het GRANT-blok in het gecombineerde bestand (miste
`spWijzigAfspraakDatumTijd`-EXECUTE, `Afspraak`-UPDATE, `actions`-INSERT, `users`-SELECT,
`WijzigAfspraakPincodes`-DELETE), en beide misten de nieuw benodigde `GRANT SELECT` op `[dbo].[Adres]`
(nodig sinds de postcode-uit-adres-wijziging, zie ADR hierboven).

**Beslissing:** `CREATE TABLE`/`CREATE INDEX` in zowel `sql/alles_in_1_wijzig_afspraak.sql` als het
losse `sql/WijzigAfspraakPincodes_tabel.sql` zijn gewrapt in `IF OBJECT_ID(...) IS NULL`/
`IF NOT EXISTS (SELECT 1 FROM sys.indexes ...)`-checks. De stored procedures gebruikten al
`CREATE OR ALTER` (waren al idempotent) en GRANT-statements zijn van zichzelf al veilig om te
herhalen — daar was geen wijziging nodig. `sql/WijzigAfspraakPincodes_rechten.sql` is
gelijkgetrokken met het GRANT-blok in het gecombineerde bestand (inclusief de nieuwe
`GRANT SELECT ON [dbo].[Adres]`), en hetzelfde GRANT is ook toegevoegd aan
`sql/alles_in_1_wijzig_afspraak.sql`.

**Gevolgen:** `sql/alles_in_1_wijzig_afspraak.sql` kan nu in zijn geheel geselecteerd en uitgevoerd
worden in SSMS, ongeacht of (delen van) het bestand al eerder gedraaid zijn — geen handmatige
selectie van "welk stuk nog moet" meer nodig. Geverifieerd: de procedure-bodies in de losse bestanden
en het gecombineerde bestand zijn met `diff` gecontroleerd en zijn byte-identiek; BEGIN/END-statements
in het gecombineerde bestand zijn in balans (21/21).

---

## 2026-09-07 — `doorgepland`-vlag (pre_aid) toegevoegd voor het adviseur-filter in AgendaPicker

**Context:** de gebruiker wil in AgendaPicker's kalenderstap een keuze aanbieden om het adviseur-filter
uit te zetten en zo meer mogelijke tijden te zien: *"ik wil graag een check box of button waarbij ik
meer mogelijke slots kan laten zien. Dan niet meer filteren op adviseur."* Maar met een belangrijke
uitzondering: *"Als een afspraak een pre_aid kolom gevuld heeft dan is het doorgeplanned en moet er
altijd worden gefilterd op adviseur. dan geen keus aanbieden"* — sommige afspraken zijn specifiek aan
één adviseur "doorgepland" en mogen dan nooit voor een andere adviseur ingepland worden.

**Beslissing:** `spValideerWijzigPincode` krijgt een nieuwe `@doorgepland BIT OUTPUT`-parameter,
afgeleid uit `[dbo].[Afspraak].[pre_aid] IS NOT NULL` (vers herquery't, zelfde plek als
insteek_id/prodcat_id/adres_sleutel). `/wijzig_verificatie` geeft dit nu mee als `doorgepland` in de
JSON-respons. AgendaPicker gebruikt dit om de "toon meer tijden"-toggle te tonen of juist te verbergen
(zie AgendaPicker's `docs/DECISIONS.md`).

**Gevolgen:** vereist een nieuwe deploy van `spValideerWijzigPincode.sql` (en
`alles_in_1_wijzig_afspraak.sql`) en `function_app.py`. **Niet geverifieerd:** kolomnaam `pre_aid` komt
alleen uit tekst van de gebruiker, niet gecontroleerd tegen het echte schema — zelfde risico als de
eerdere schema-aannames in deze flow.

---

## 2026-09-07 — Fallback naar Klanten-postcode als er geen afspraak-adres gekoppeld is

**Context:** direct na het testen van de vorige ADR (postcode uit afspraak-adres) bleek in de praktijk
dat een buitendienst-afspraak zonder gekoppeld adres bestaat: `/api/availability` gaf een 400
("Parameter postcode is verplicht...") omdat `@adres_sleutel IS NULL` was voor die afspraak, en de
`IF @adres_sleutel IS NOT NULL`-guard de hele postcode-lookup dan overslaat zonder fout — `@postcode`
bleef simpelweg leeg. De gebruiker: *"als er geen adres is gekoppeld dan de postcode gebruikten uit
klanten data"* — expliciet verzoek om terug te vallen op de oude bron (Klanten) in dat geval.

**Beslissing:** beide stored procedures (`spZoekAfspraakVoorWijziging`, `spValideerWijzigPincode`)
vallen nu terug op `[dbo].[Klanten].[postcode]` als de afspraak-adres-lookup geen postcode oplevert
(`IF @postcode IS NULL`). `spZoekAfspraakVoorWijziging` haalt de klant-postcode op in dezelfde query
als `klant_id` (heeft daar al een e-mail-match); `spValideerWijzigPincode` haalt `klant_id` erbij in
de al bestaande fresh-herquery van `[dbo].[Afspraak]` en doet daarna een aparte `Klanten`-lookup. Dit
herstelt `[dbo].[Klanten]`'s `postcode`-kolom als (nu secundaire) bron — die was in de vorige ADR juist
losgelaten.

**Gevolgen:** vereist een nieuwe deploy van beide stored procedures (en
`sql/alles_in_1_wijzig_afspraak.sql`). Geen wijziging aan `function_app.py` of AgendaPicker nodig — dit
is puur een SQL-interne fallback, de output-contractvorm (`postcode` in de response) blijft ongewijzigd.

---

## 2026-09-07 — MonthView voor buitendienst-availability server-side opgelost (i.p.v. client-side)

**Context:** AgendaPicker loste het ontbreken van MonthView-ondersteuning in
`psAgendaPicker_GetAvailabilityBuitendienst` (zie die repo's ADR-019) op door zelf 31 losse
browser-requests te doen, één per dag. De gebruiker vroeg: *"kan dat niet efficiënter? met een echte
stored procedure"*. Voorgelegd aan de gebruiker: (1) een nieuwe/aangepaste T-SQL stored procedure die
zelf een datumreeks doorloopt, of (2) een server-side loop in Python binnen `_handle_availability`. De
gebruiker koos expliciet voor optie (2) — de bestaande SQL van `psAgendaPicker_GetAvailabilityBuitendienst`
zelf is niet in deze repo bekend (staat alleen op de database), dus een T-SQL-wrapper bouwen zou
gokken naar de exacte parameter-/kolomnamen vergen, met hetzelfde risico op "Invalid parameter/column"-
fouten die deze sessie al meerdere keren voorkwamen bij vergelijkbare aannames.

**Beslissing:** nieuwe helpers in `function_app.py`: `_is_month_view_requested(payload)` herkent een
MonthView-vlag (verschillende schrijfwijzen/types) in de request-payload; `_call_buitendienst_month_view
(cursor, sp_payload)` berekent de kalendermaand (1e t/m laatste dag) van de opgegeven `date`, roept
`_call_sp_dynamic(..., "psAgendaPicker_GetAvailabilityBuitendienst", ...)` per dag aan binnen dezelfde
Azure Function-invocatie/DB-connectie, en voegt alle result sets samen tot één vlakke lijst. `_handle_
availability` gebruikt deze helper i.p.v. de gewone enkele SP-aanroep wanneer `procedure_name ==
"psAgendaPicker_GetAvailabilityBuitendienst"` én MonthView is aangevraagd — voor alle andere gevallen
(inclusief online) verandert er niets.

**Gevolgen:** AgendaPicker kon hierdoor terug naar één request per maandwissel voor buitendienst (i.p.v.
de tijdelijke 31-requests-aanpak) — zie AgendaPicker's `docs/DECISIONS.md`. Geverifieerd door
`_call_sp_dynamic` te mocken (geen echte DB-connectie nodig): correcte dag-range voor een gewone maand,
de jaarwissel december→januari, en een schrikkeljaar (29 dagen in februari 2028). Vereist een nieuwe
`function_app.py`-deploy — geen SQL-wijziging.
