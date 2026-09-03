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
