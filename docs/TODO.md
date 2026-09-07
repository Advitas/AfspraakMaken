# TODO

- [ ] Controleer en vul aan: `docs/ARCHITECTURE.md` — vooral de secties die onbekend bleven (CI/CD, hosting-details buiten Azure Functions)
- [ ] Controleer en vul aan: `docs/CONVENTIONS.md` — voeg patronen toe die nog ontbreken (stijlgids/linting, teststrategie)
- [ ] Voer een bouwcheck uit: `pip install -r requirements.txt` gevolgd door `func start`
- [ ] Zoek de `routePrefix`-discrepantie uit: `host.json` zet `"api"`, README/USER_MANUAL claimen geen prefix — verifieer tegen productiegedrag en corrigeer de docs
- [ ] Schrijf eerste tests — er is momenteel geen testframework/testbestanden in het project
- [x] `/availability` roept nu ook `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan bij `vorm_afspraak=buitendienst` (zie `docs/DECISIONS.md`, 2026-09-01 en 2026-09-01 vervolg). **Opgelost 2026-09-01:** root cause was ontbrekende rechten voor `svc-AppMaakAfspraak` op productie (bevestigd via AgendaPicker end-to-end-test na het zetten van `GRANT EXECUTE`/`GRANT SELECT`). Werkt nu correct in productie.
- [ ] Reserverings-mail naar planning@advitas.nl (zie `docs/DECISIONS.md`, 2026-09-01, vervangen door Mandrill) vereist dat env-var `MANDRILL_API_KEY` in de Function App's App Settings staat. Nog niet geverifieerd — controleer via een test-reservering en check of de mail daadwerkelijk aankomt (bij een ontbrekende/ongeldige key faalt dit stil; zie Application Insights voor de echte foutmelding).
- [x] **Uitgevoerd 2026-09-03:** alle SQL uit `sql/alles_in_1_wijzig_afspraak.sql` (tabel
  `WijzigAfspraakPincodes` + 4 stored procedures + GRANT's) staat nu op de database — geen
  compilatiefouten meer. Dit bevestigt daarmee ook impliciet de kolomnaam-aannames die daarvoor open
  stonden: `[dbo].[Afspraak].[afspraak-id]`, `[dbo].[Klanten].[klant_id]`/`[email]`/`[postcode]`, en
  `dbo.users.[id]` bestaan allemaal zoals aangenomen (anders had `CREATE PROCEDURE` een "Invalid column
  name"-fout gegeven, zoals eerder gebeurde met `afspraak_id` vs `afspraak-id`).
  **Nog wél open** (dit zijn data-/businessaannames, niet kolomnamen — worden niet door `CREATE PROCEDURE`
  gecontroleerd): (1) `[vorm_afspraak]` = `'Buitendienst'` (Titel-case) is nog steeds een aanname naar
  analogie met het bevestigde `'Online'` — pas te verifiëren door een echte buitendienst-wijziging te
  testen; (2) een aantal `[actions]`-kolommen (direction, product_id, tag, communication, Oorsprong,
  Oorsprong_categorie, insteek_id, field_contents_4 t/m 12) staan op `NULL` — check of dat businessmatig
  klopt voor het "Afspraakwijziging"-scenario.
- [ ] Bevestigen dat `MANDRILL_API_KEY` correct in de Function App's App Settings staat voor de
  wijzig-pincode-mail. `AzureWebJobsStorage` is sinds het herontwerp naar SQL-opslag niet meer relevant
  voor deze feature (blijft uiteraard wel nodig voor de Function App zelf).
- [x] **Routes hernoemd naar underscore (2026-09-03):** `/wijzig-aanvraag`/`/wijzig-verificatie`/
  `/wijzig-opslaan` (koppelteken) zijn hernoemd naar `/wijzig_aanvraag`/`/wijzig_verificatie`/
  `/wijzig_opslaan` (underscore) — bewust gelijkgetrokken met de Python-functienamen, die Azure Portal's
  Functions-lijst toont (Python staat geen koppeltekens toe in functienamen, dus die kolom toonde altijd
  al underscore, terwijl de URL voorheen apart op koppelteken stond via `route=`). Dit voorkwam
  herhaaldelijke verwarring bij het aflezen van de juiste URL uit Azure Portal. **Vereist een nieuwe
  AfspraakMaken-deploy**, en de env vars `AFSPRAAK_WIJZIG_AANVRAAG_URL`/`AFSPRAAK_WIJZIG_VERIFICATIE_URL`/
  `AFSPRAAK_WIJZIG_OPSLAAN_URL` in AgendaPicker's App Settings moeten naar de underscore-paden wijzen.
- [ ] `/wijzig_aanvraag`, `/wijzig_verificatie`, `/wijzig_opslaan` zijn nog niet live getest tegen
  `SQL_DATABASE_TEST` — de SQL-kant staat er nu (zie boven), enige blocker is nu een lokale
  `local.settings.json`, die niet in deze sessie is aangemaakt. **Let op:** de curl-voorbeelden in
  `docs/superpowers/plans/2026-09-03-wijzig-afspraak-pincode.md` zijn verouderd (afspraak_id-gebaseerd
  én koppelteken-routes) — gebruik in plaats daarvan:
  ```bash
  curl -X POST http://localhost:7071/api/wijzig_aanvraag \
    -H "Content-Type: application/json" \
    -d '{"email": "klant@voorbeeld.nl", "run": "test"}'

  curl -X POST http://localhost:7071/api/wijzig_verificatie \
    -H "Content-Type: application/json" \
    -d '{"email": "klant@voorbeeld.nl", "pincode": "123456", "run": "test"}'

  curl -X POST http://localhost:7071/api/wijzig_opslaan \
    -H "Content-Type: application/json" \
    -d '{"email": "klant@voorbeeld.nl", "pincode": "123456", "adviseur_id": 42, "datum": "2026-09-10", "tijd": "14:30", "duur_kwartieren": 2, "vorm_afspraak": "online", "run": "test"}'
  ```
- [x] **Mail-omleiding nu run-afhankelijk (2026-09-07):** eerst volledig uitgezet, daarna genuanceerd
  op verzoek van de gebruiker ("als run = test dan moet rvader geactiveerd"): `_resolve_wijzig_mail_
  override_to(run_value)` stuurt bij `run=test` automatisch naar `rvader@advitas.nl`, bij `run=prod`
  naar het echte klant-e-mailadres — zonder dat de env var `WIJZIG_MAIL_OVERRIDE_TO` gezet hoeft te
  worden. Die env var blijft wel bestaan en wint altijd als 'ie expliciet gezet is (ook als lege
  string), voor het geval dit gedrag handmatig overruled moet worden. Geldt voor zowel de pincode-mail
  als de afspraak-bevestigingsmail.
- [ ] **Nieuw, UIT by default:** `/afspraak` kan nu optioneel een bevestigingsmail met "Afspraak
  wijzigen"-knop naar de klant sturen (`_try_send_afspraak_bevestiging_email`), maar alleen als
  `AFSPRAAK_BEVESTIGING_MAIL_ENABLED=true` staat — standaard `false`, juist omdat `/afspraak` een
  bestaand, al in productie actief endpoint is. Zet deze env var pas op `true` nadat de hele
  wijzig-afspraak-flow (inclusief de nog te bouwen `spWijzigAfspraakDatumTijd`) end-to-end getest is,
  anders krijgen klanten een "Afspraak wijzigen"-knop die nog niet werkt.
- [ ] `AFSPRAAK_BEVESTIGING_MAIL_ENABLED` toevoegen aan de App Settings (staat al met default `false`
  in `local.settings.json.example`).
- [x] **Herontwerp 2026-09-03: e-mail-eerst i.p.v. afspraak_id-in-link.** Op verzoek van de gebruiker start
  de wijzig-flow nu met een e-mailadres (niet meer met `afspraak_id` uit een link) — de klant typt zijn
  e-mailadres in, het systeem zoekt zelf de bijbehorende afspraak op. De 3 nieuwe stored procedures +
  nieuwe SQL-tabel (`WijzigAfspraakPincodes_tabel.sql`, `spZoekAfspraakVoorWijziging.sql`,
  `spBewaarWijzigPincode.sql`, `spValideerWijzigPincode.sql`, `WijzigAfspraakPincodes_rechten.sql`) staan
  nu uitgevoerd op de database (zie hierboven) — inclusief de aanname over `[dbo].[Klanten]`'s kolommen,
  die daarmee impliciet bevestigd is.
- [x] `function_app.py` is bijgewerkt: de Azure Table Storage-helpers en de `azure-data-tables`-dependency
  zijn vervangen door `_call_sp_zoek_afspraak_voor_wijziging`/`_call_sp_bewaar_wijzig_pincode`/
  `_call_sp_valideer_wijzig_pincode`. `/wijzig-aanvraag` en `/wijzig-verificatie`/`/wijzig-opslaan`
  accepteren nu `email` i.p.v. `afspraak_id` als belangrijkste input (`afspraak_id` wordt server-side uit
  de gevalideerde pincode gehaald, nooit meer van de client vertrouwd). **Nog niet live getest** — de
  SQL-kant staat er nu, enige blocker is een lokale `local.settings.json` (zie curl-item hierboven).
- [x] **`agenda` toegevoegd aan `/wijzig_verificatie`-response (2026-09-07):** AgendaPicker's
  kalenderstap (`/api/availability`) heeft `agenda`/`adviseur_id`/`duur` nodig, afkomstig uit de te
  wijzigen afspraak zelf. `spValideerWijzigPincode` leidt `@agenda` nu af uit `insteek_id`/`prodcat_id`
  van `[dbo].[Afspraak]` (mapping door de gebruiker aangeleverd: insteek_id=5 → hypotheek, insteek_id=1
  → vermogen, insteek_id=35+prodcat_id=22 → schade). **NIET bevestigd:** of `[dbo].[Afspraak]`'s kolommen
  `[insteek-id]`/`[prodcat-id]` een koppelteken gebruiken (aangenomen, naar analogie van
  `[afspraakstate-id]`) — controleer dit vóór de volgende SQL-deploy, anders geeft
  `spValideerWijzigPincode` een "Invalid column name"-fout (zelfde foutklasse als de eerdere
  `afspraak-id`-typo). Vereist een nieuwe deploy van zowel deze stored procedure
  (`sql/spValideerWijzigPincode.sql`, ook bijgewerkt in `sql/alles_in_1_wijzig_afspraak.sql`) als
  `function_app.py`.
- [x] **Knop verwijderd uit de pincode-mail (2026-09-07):** op verzoek van de gebruiker bevat
  `_build_wijzig_email` geen "Wijzig uw afspraak"-knop meer — de klant staat al op
  `wijzig-afspraak.html` wanneer de pincode-mail binnenkomt, dus de knop was overbodig. Zie
  `docs/DECISIONS.md`.
- [x] **BEVEILIGINGSAFWIJKING, expliciet gevraagd (2026-09-07):** `/wijzig_opslaan` controleert de
  pincode niet meer — `afspraak_id` komt nu rechtstreeks van de client i.p.v. server-side afgeleid uit
  een pincode-hervalidatie (was het patroon sinds het e-mail-eerst-herontwerp van 2026-09-03). Reden:
  de 5-minuten-vervaltermijn van de pincode gaf een "verlopen pincode"-fout als een klant lang in de
  kalender aan het kiezen was. Zie de ADR van 2026-09-07 in `docs/DECISIONS.md` voor de volledige
  afweging en het overwogen alternatief (alleen de tijdslimiet loslaten, wat de identiteitscontrole
  wél had behouden). **Risico dat nog open staat:** wie een afspraak_id kent of raadt, kan die
  wijzigen — er is geen enkele identiteitscontrole meer bij het opslaan zelf. Overweeg dit alsnog te
  verzachten (bijv. een kortlevende, ondertekende token i.p.v. kale afspraak_id) als dit in productie
  gaat.
- [x] **Postcode voor buitendienst-beschikbaarheid komt nu uit het afspraak-adres (2026-09-07):**
  AgendaPicker's `/api/availability` gaf een 400 ("Parameter postcode is verplicht...") bij
  `vorm_afspraak=Buitendienst`, omdat `@postcode` tot nu toe uit `[dbo].[Klanten]` kwam (vaak leeg/niet
  representatief voor de afspraak zelf). `spZoekAfspraakVoorWijziging` en `spValideerWijzigPincode`
  leiden `@postcode` nu af uit het afspraak-adres: `[dbo].[Afspraak].[adres_sleutel]` ->
  `[dbo].[Adres].[Adres-id]` -> `LEFT([PKD], 4)`. **NIET geverifieerd** tegen het echte schema —
  kolomnamen `adres_sleutel`/`Adres-id`/`PKD` zijn door de gebruiker als tekst aangeleverd, niet
  gecontroleerd via `sp_help`. Vereist een nieuwe deploy van beide stored procedures
  (`sql/spZoekAfspraakVoorWijziging.sql`, `sql/spValideerWijzigPincode.sql`, ook bijgewerkt in
  `sql/alles_in_1_wijzig_afspraak.sql`) vóórdat buitendienst-afspraken via deze flow gewijzigd kunnen
  worden.
- [x] **Alle SQL idempotent gemaakt, "zonder nadenken" te draaien (2026-09-07):** op verzoek van de
  gebruiker (*"kan je alles sql zo maken dat ik die kan runnen zonder na e denken"*) is
  `sql/alles_in_1_wijzig_afspraak.sql` (en de losse `sql/WijzigAfspraakPincodes_tabel.sql`) aangepast
  zodat het hele bestand veilig herhaald uitgevoerd kan worden, ook na een eerdere (gedeeltelijke)
  run: de `CREATE TABLE`/`CREATE INDEX`-statements zijn nu `IF NOT EXISTS`-gewrapt (voorheen gaf een
  herhaalde run een "already exists"-fout op de tabel). De stored procedures gebruikten al
  `CREATE OR ALTER` (was al idempotent). Bij deze gelegenheid ook een ontbrekende
  `GRANT SELECT ON [dbo].[Adres]` toegevoegd (nodig sinds de postcode-uit-adres-wijziging hierboven,
  was er nog niet) aan zowel het gecombineerde bestand als `sql/WijzigAfspraakPincodes_rechten.sql`
  (dat laatste was sowieso stale t.o.v. het gecombineerde bestand — nu gelijkgetrokken).
- [x] **`doorgepland`-vlag toegevoegd aan `/wijzig_verificatie` (2026-09-07):** AgendaPicker krijgt een
  nieuwe "toon meer mogelijke tijden"-optie waarmee de klant het adviseur-filter kan uitzetten (zie
  AgendaPicker's `docs/DECISIONS.md`). Dat mag echter NIET als de afspraak "doorgepland" is —
  `spValideerWijzigPincode` retourneert nu `@doorgepland` (BIT), afgeleid uit
  `[dbo].[Afspraak].[pre_aid] IS NOT NULL`. **NIET geverifieerd:** kolomnaam `pre_aid` komt alleen uit
  tekst van de gebruiker. Vereist dezelfde SQL/code-deploy als de andere nog openstaande wijzigingen
  hierboven.
- [x] **Fallback naar Klanten-postcode als er geen afspraak-adres is (2026-09-07):** in de praktijk
  bleek een buitendienst-afspraak zonder gekoppeld adres (`adres_sleutel IS NULL`) te bestaan — dan
  bleef `@postcode` leeg en gaf `/api/availability` een 400-fout. `spZoekAfspraakVoorWijziging` en
  `spValideerWijzigPincode` vallen nu terug op `[dbo].[Klanten].[postcode]` (via `klant_id`) als het
  afspraak-adres geen postcode oplevert — het gedrag van vóór de "postcode uit adres"-wijziging,
  maar nu als fallback i.p.v. als enige bron. Vereist dezelfde SQL-deploy als de andere nog
  openstaande wijzigingen hierboven.
- [x] **`/availability` doet MonthView-loop server-side voor buitendienst (2026-09-07, ADR-020):**
  op verzoek van de gebruiker ("kan dat niet efficiënter? met een echte stored procedure") — geen
  wijziging aan de bestaande, onbekende SQL van `psAgendaPicker_GetAvailabilityBuitendienst` zelf
  (risico op gok-fouten, zie eerdere incidenten deze sessie), maar een nieuwe Python-helper
  `_call_buitendienst_month_view` die de bestaande SP per dag aanroept binnen dezelfde Azure
  Function-invocatie/DB-connectie en de resultaten samenvoegt. AgendaPicker's kant is teruggedraaid
  naar één request per maandwissel (was tijdelijk 31 losse browser-requests, zie de vorige fix in
  AgendaPicker's `docs/DECISIONS.md`). Geverifieerd met gemockte `_call_sp_dynamic` (geen echte
  DB-connectie nodig): correcte dag-range voor een gewone maand, jaarwissel (december→januari) en
  schrikkeljaar (29 dagen in februari).
- [x] **Bug gevonden en gefixt: transactiefout in `spWijzigAfspraakDatumTijd` (2026-09-07):**
  `/wijzig_opslaan` gaf een 500 met "Transaction count after EXECUTE indicates a mismatching number
  of BEGIN and COMMIT statements" (SQL-foutcode 266). Root cause: pyodbc gebruikt `autocommit=False`,
  dus er staat al een ambient transactie open (`@@TRANCOUNT=1`) vóórdat de SP wordt aangeroepen. De
  SP's onvoorwaardelijke `ROLLBACK TRANSACTION` bij "afspraak niet gevonden" rolt in SQL Server
  ALTIJD terug tot `TRANCOUNT=0` (ongeacht nesting), en rolt dus ook de ambient transactie van de
  Python-caller weg. Gefixt met een nesting-safe patroon (`@ownsTransaction`-vlag): de SP doet alleen
  zelf `BEGIN`/`COMMIT`/`ROLLBACK TRANSACTION` als hij `@@TRANCOUNT=0` aantreft bij binnenkomst;
  anders laat hij het transactiebeheer aan de caller (die dat al correct deed via `conn.commit()`/
  `conn.rollback()` in `wijzig_opslaan`). Vereist een nieuwe deploy van
  `sql/spWijzigAfspraakDatumTijd.sql` (en `sql/alles_in_1_wijzig_afspraak.sql`).
- [ ] **Zelfde sluimerende risico gespot in `sql/spBewaarWijzigPincode.sql`:** die procedure heeft
  hetzelfde patroon (onvoorwaardelijke `BEGIN TRANSACTION` + `ROLLBACK TRANSACTION` in de CATCH,
  aangeroepen via dezelfde niet-autocommit pyodbc-connectie). Nog niet daadwerkelijk geraakt — er zit
  geen vroege "business logic"-return-met-rollback in, alleen een DELETE+INSERT die zelden faalt —
  maar bij een onverwachte databasefout zou dezelfde transactiecount-mismatch (SQL-foutcode 266) hier
  ook kunnen optreden. Niet stilzwijgend meegefixt (buiten scope van het gerapporteerde incident) —
  overweeg hetzelfde `@ownsTransaction`-patroon toe te passen als hier ooit een vergelijkbare fout
  optreedt, of proactief bij een volgende SQL-deploy.
- [x] **Vervolgfout na de vorige fix: "Uncommittable transaction" (SQL-foutcode 3998), gefixt
  (2026-09-07):** na de `@ownsTransaction`-fix trad een nieuwe fout op bij een echte runtime-fout
  (niet het "niet gevonden"-pad): `SET XACT_ABORT ON` maakt de transactie bij zo'n fout meestal
  volledig "doomed" (`XACT_STATE() = -1`), ook bij `@ownsTransaction = 0` — de aanroepende batch kon
  daardoor geen enkel statement meer uitvoeren (ook niet de `SELECT @foutmelding` erna), wat de
  verwarrende "Uncommittable transaction is detected at the end of the batch"-fout gaf i.p.v. de
  échte onderliggende oorzaak. Gefixt: de CATCH-blok checkt nu `XACT_STATE()` en doet `THROW` (de
  oorspronkelijke fout opnieuw opgooien) zodra de transactie doomed is, i.p.v. te proberen netjes
  `@foutmelding` te zetten en door te gaan. `function_app.py`'s bestaande `except pyodbc.Error`-tak
  in `wijzig_opslaan` vangt dit al correct af (`conn.rollback()` + `_extract_db_error_details`) —
  geen Python-wijziging nodig. **Let op:** dit fixt de transactie-afhandeling, niet de onderliggende
  échte fout die de CATCH triggert — die was tot nu toe onzichtbaar door dit bug-op-bug-effect. Na
  deze deploy zou de eerstvolgende poging de daadwerkelijke SQL-foutmelding moeten tonen, wat helpt om
  de eigenlijke oorzaak te vinden.
