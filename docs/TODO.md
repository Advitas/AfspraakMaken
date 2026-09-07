# TODO

- [ ] Controleer en vul aan: `docs/ARCHITECTURE.md` — vooral de secties die onbekend bleven (CI/CD, hosting-details buiten Azure Functions)
- [ ] Controleer en vul aan: `docs/CONVENTIONS.md` — voeg patronen toe die nog ontbreken (stijlgids/linting, teststrategie)
- [ ] Voer een bouwcheck uit: `pip install -r requirements.txt` gevolgd door `func start`
- [ ] Zoek de `routePrefix`-discrepantie uit: `host.json` zet `"api"`, README/USER_MANUAL claimen geen prefix — verifieer tegen productiegedrag en corrigeer de docs
- [ ] Schrijf eerste tests — er is momenteel geen testframework/testbestanden in het project
- [x] `/availability` roept nu ook `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan bij `vorm_afspraak=buitendienst` (zie `docs/DECISIONS.md`, 2026-09-01 en 2026-09-01 vervolg). **Opgelost 2026-09-01:** root cause was ontbrekende rechten voor `svc-AppMaakAfspraak` op productie (bevestigd via AgendaPicker end-to-end-test na het zetten van `GRANT EXECUTE`/`GRANT SELECT`). Werkt nu correct in productie.
- [ ] Reserverings-mail naar planning@advitas.nl (zie `docs/DECISIONS.md`, 2026-09-01, vervangen door Mandrill) vereist dat env-var `MANDRILL_API_KEY` in de Function App's App Settings staat. Nog niet geverifieerd — controleer via een test-reservering en check of de mail daadwerkelijk aankomt (bij een ontbrekende/ongeldige key faalt dit stil; zie Application Insights voor de echte foutmelding).
- [ ] `spWijzigAfspraakDatumTijd` moet uitgevoerd worden op `SQL_DATABASE_TEST`/productie — het voorstel
  staat in `sql/spWijzigAfspraakDatumTijd.sql`, gebaseerd op het schema van `[dbo].[Afspraak]` zoals
  zichtbaar in `[PowerBI].[usp_Reservering_OmzettenNaarAfspraak]`, plus een `[dbo].[actions]`-insert voor
  het "Afspraakwijziging"-scenario (beide aangeleverd 2026-09-03). **Bevestigd 2026-09-03:** de PK-kolom
  van `[dbo].[Afspraak]` heet `[afspraak-id]` **met koppelteken** (niet underscore) — zelfde patroon als
  `[afspraakstate-id]`/`[insteek-id]`/`[prodcat-id]`; `[dbo].[actions]` gebruikt wél `[afspraak_id]` met
  underscore. Alle SQL-bestanden in `sql/` zijn hierop bijgewerkt. **Nog te verifiëren vóór uitvoering**
  (zie ook de opsomming bovenaan `sql/spWijzigAfspraakDatumTijd.sql`): (1) `[vorm_afspraak]` =
  `'Buitendienst'` is een aanname naar analogie met het bevestigde `'Online'`; (2) `dbo.users` heeft een
  PK-kolom `[id]` (voor de `creator_id`-fallback); (3) een aantal `[actions]`-kolommen (direction,
  product_id, tag, communication, Oorsprong, Oorsprong_categorie, insteek_id, en field_contents_4 t/m 12)
  staan op `NULL` omdat daar geen waarde voor is aangeleverd — check of dat businessmatig klopt. Tot
  uitvoering + verificatie geeft `/wijzig-opslaan` een databasefout ("procedure niet gevonden").
- [ ] Rechten controleren/zetten voor `svc-AppMaakAfspraak` op de nieuwe SP + onderliggende tabellen
  (`EXECUTE` op `spWijzigAfspraakDatumTijd`, `SELECT`/`UPDATE` op `Afspraak`, `INSERT` op `actions`,
  `SELECT` op `users`) — de GRANT-statements staan onderaan `sql/spWijzigAfspraakDatumTijd.sql`. Zelfde
  soort probleem als de buitendienst-500 uit `docs/DECISIONS.md` (2026-09-01) trad eerder al op zonder
  deze rechten.
- [ ] Bevestigen dat `MANDRILL_API_KEY` correct in de Function App's App Settings staat voor de
  wijzig-pincode-mail. `AzureWebJobsStorage` is sinds het herontwerp naar SQL-opslag niet meer relevant
  voor deze feature (blijft uiteraard wel nodig voor de Function App zelf).
- [ ] `/wijzig-aanvraag`, `/wijzig-verificatie`, `/wijzig-opslaan` zijn nog niet live getest tegen
  `SQL_DATABASE_TEST` (dit vereist zowel een lokale `local.settings.json`, die niet in deze sessie is
  aangemaakt, als de 4 nieuwe SP's + tabel hierboven). **Let op:** de curl-voorbeelden in
  `docs/superpowers/plans/2026-09-03-wijzig-afspraak-pincode.md` zijn verouderd (die gingen nog uit van
  `afspraak_id` in de body) — gebruik in plaats daarvan:
  ```bash
  curl -X POST http://localhost:7071/api/wijzig-aanvraag \
    -H "Content-Type: application/json" \
    -d '{"email": "klant@voorbeeld.nl", "run": "test"}'

  curl -X POST http://localhost:7071/api/wijzig-verificatie \
    -H "Content-Type: application/json" \
    -d '{"email": "klant@voorbeeld.nl", "pincode": "123456", "run": "test"}'

  curl -X POST http://localhost:7071/api/wijzig-opslaan \
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
- [ ] **Herontwerp 2026-09-03: e-mail-eerst i.p.v. afspraak_id-in-link.** Op verzoek van de gebruiker start
  de wijzig-flow nu met een e-mailadres (niet meer met `afspraak_id` uit een link) — de klant typt zijn
  e-mailadres in, het systeem zoekt zelf de bijbehorende afspraak op. Dit vereist 3 NIEUWE stored
  procedures (bovenop de al openstaande `spWijzigAfspraakDatumTijd`), plus een nieuwe SQL-tabel die de
  eerdere Azure Table Storage-opslag vervangt:
  - `sql/WijzigAfspraakPincodes_tabel.sql` — nieuwe tabel (vervangt Table Storage volledig)
  - `sql/spZoekAfspraakVoorWijziging.sql` — e-mail → eerstvolgende toekomstige 'Open'-afspraak
  - `sql/spBewaarWijzigPincode.sql` — pincode opslaan
  - `sql/spValideerWijzigPincode.sql` — pincode valideren + afspraak-info teruggeven
  - `sql/WijzigAfspraakPincodes_rechten.sql` — GRANT-statements voor `svc-AppMaakAfspraak`
  Alle vier moeten (in volgorde: tabel → 3 SP's → rechten) uitgevoerd worden op `SQL_DATABASE_TEST`/
  productie. **Belangrijke aanname, nog te verifiëren:** de Klanten-tabel heet `[dbo].[Klanten]` met
  kolommen `[klant_id]`/`[email]` — AgendaPicker's eigen code (`server.js`, `getKlantenTableInfo`)
  detecteert dit juist dynamisch omdat kolomnamen kunnen variëren (bijv. `e-mailadres`); deze nieuwe SP's
  gaan uit van vaste namen. Zie de aannames bovenaan `sql/spZoekAfspraakVoorWijziging.sql`.
- [x] `function_app.py` is bijgewerkt: de Azure Table Storage-helpers en de `azure-data-tables`-dependency
  zijn vervangen door `_call_sp_zoek_afspraak_voor_wijziging`/`_call_sp_bewaar_wijzig_pincode`/
  `_call_sp_valideer_wijzig_pincode`. `/wijzig-aanvraag` en `/wijzig-verificatie`/`/wijzig-opslaan`
  accepteren nu `email` i.p.v. `afspraak_id` als belangrijkste input (`afspraak_id` wordt server-side uit
  de gevalideerde pincode gehaald, nooit meer van de client vertrouwd). **Nog niet live getest** — wacht op
  uitvoering van de 4 nieuwe SP's + tabel (zie hierboven).
