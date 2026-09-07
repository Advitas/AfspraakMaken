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
- [ ] **TIJDELIJK, moet ongedaan gemaakt worden vóór een release naar echte klanten:** de pincode-mail
  én de nieuwe afspraak-bevestigingsmail gaan momenteel altijd naar `rvader@advitas.nl` in plaats van
  naar het opgegeven klant-e-mailadres (`WIJZIG_MAIL_OVERRIDE_TO_DEFAULT` in `function_app.py`, expliciet
  aangevraagd 2026-09-03 voor testdoeleinden). Verwijder deze default (of zet env var
  `WIJZIG_MAIL_OVERRIDE_TO` leeg) zodra er weer naar echte klant-e-mailadressen gemaild moet worden.
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
