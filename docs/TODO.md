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
  het "Afspraakwijziging"-scenario (beide aangeleverd 2026-09-03). **Nog te verifiëren vóór uitvoering**
  (zie ook de opsomming bovenaan `sql/spWijzigAfspraakDatumTijd.sql`): (1) de PK-kolomnaam van
  `[dbo].[Afspraak]` is aangenomen als `[afspraak_id]`; (2) `[vorm_afspraak]` = `'Buitendienst'` is een
  aanname naar analogie met het bevestigde `'Online'`; (3) `dbo.users` heeft een PK-kolom `[id]` (voor de
  `creator_id`-fallback); (4) een aantal `[actions]`-kolommen (direction, product_id, tag, communication,
  Oorsprong, Oorsprong_categorie, insteek_id, en field_contents_4 t/m 12) staan op `NULL` omdat daar geen
  waarde voor is aangeleverd — check of dat businessmatig klopt. Tot uitvoering + verificatie geeft
  `/wijzig-opslaan` een databasefout ("procedure niet gevonden").
- [ ] Rechten controleren/zetten voor `svc-AppMaakAfspraak` op de nieuwe SP + onderliggende tabellen
  (`EXECUTE` op `spWijzigAfspraakDatumTijd`, `SELECT`/`UPDATE` op `Afspraak`, `INSERT` op `actions`,
  `SELECT` op `users`) — de GRANT-statements staan onderaan `sql/spWijzigAfspraakDatumTijd.sql`. Zelfde
  soort probleem als de buitendienst-500 uit `docs/DECISIONS.md` (2026-09-01) trad eerder al op zonder
  deze rechten.
- [ ] Bevestigen dat `MANDRILL_API_KEY` en `AzureWebJobsStorage` correct in de Function App's App Settings
  staan voor de nieuwe wijzig-pincode-mail en pincode-opslag.
- [ ] `/wijzig-aanvraag`, `/wijzig-verificatie`, `/wijzig-opslaan` zijn nog niet live getest tegen
  `SQL_DATABASE_TEST`/een echte Storage Account (dit vereist een lokale `local.settings.json`, die niet in
  deze sessie is aangemaakt) — zie `docs/superpowers/plans/2026-09-03-wijzig-afspraak-pincode.md` voor de
  curl-commando's om dat handmatig te doen.
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
- [ ] `_bewaar_pincode_record`/`_haal_pincode_record`/`_verwijder_pincode_record`/`_verhoog_pincode_pogingen`
  (Azure Table Storage, `function_app.py`) en de `azure-data-tables`-dependency moeten vervangen worden
  door aanroepen naar de nieuwe SP's hierboven — nog te doen (zie ADR in `docs/DECISIONS.md`).
  `/wijzig-aanvraag` en `/wijzig-verificatie` accepteren straks `email` i.p.v. `afspraak_id` als
  belangrijkste input.
