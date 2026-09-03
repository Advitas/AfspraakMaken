# TODO

- [ ] Controleer en vul aan: `docs/ARCHITECTURE.md` — vooral de secties die onbekend bleven (CI/CD, hosting-details buiten Azure Functions)
- [ ] Controleer en vul aan: `docs/CONVENTIONS.md` — voeg patronen toe die nog ontbreken (stijlgids/linting, teststrategie)
- [ ] Voer een bouwcheck uit: `pip install -r requirements.txt` gevolgd door `func start`
- [ ] Zoek de `routePrefix`-discrepantie uit: `host.json` zet `"api"`, README/USER_MANUAL claimen geen prefix — verifieer tegen productiegedrag en corrigeer de docs
- [ ] Schrijf eerste tests — er is momenteel geen testframework/testbestanden in het project
- [x] `/availability` roept nu ook `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan bij `vorm_afspraak=buitendienst` (zie `docs/DECISIONS.md`, 2026-09-01 en 2026-09-01 vervolg). **Opgelost 2026-09-01:** root cause was ontbrekende rechten voor `svc-AppMaakAfspraak` op productie (bevestigd via AgendaPicker end-to-end-test na het zetten van `GRANT EXECUTE`/`GRANT SELECT`). Werkt nu correct in productie.
- [ ] Reserverings-mail naar planning@advitas.nl (zie `docs/DECISIONS.md`, 2026-09-01, vervangen door Mandrill) vereist dat env-var `MANDRILL_API_KEY` in de Function App's App Settings staat. Nog niet geverifieerd — controleer via een test-reservering en check of de mail daadwerkelijk aankomt (bij een ontbrekende/ongeldige key faalt dit stil; zie Application Insights voor de echte foutmelding).
- [ ] `spWijzigAfspraakDatumTijd` moet gebouwd worden in SQL Server (buiten deze repo, door een DBA) met
  contract `@afspraak_id, @adviseur_id, @datum, @tijd, @duur_kwartieren, @vorm_afspraak, @foutmelding
  OUTPUT` — zie `docs/superpowers/specs/2026-09-03-wijzig-afspraak-pincode-design.md`. Tot dan geeft
  `/wijzig-opslaan` een databasefout ("procedure niet gevonden").
- [ ] Bevestigen dat `MANDRILL_API_KEY` en `AzureWebJobsStorage` correct in de Function App's App Settings
  staan voor de nieuwe wijzig-pincode-mail en pincode-opslag.
- [ ] `/wijzig-aanvraag`, `/wijzig-verificatie`, `/wijzig-opslaan` zijn nog niet live getest tegen
  `SQL_DATABASE_TEST`/een echte Storage Account (dit vereist een lokale `local.settings.json`, die niet in
  deze sessie is aangemaakt) — zie `docs/superpowers/plans/2026-09-03-wijzig-afspraak-pincode.md` voor de
  curl-commando's om dat handmatig te doen.
