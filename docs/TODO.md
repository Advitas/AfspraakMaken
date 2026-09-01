# TODO

- [ ] Controleer en vul aan: `docs/ARCHITECTURE.md` — vooral de secties die onbekend bleven (CI/CD, hosting-details buiten Azure Functions)
- [ ] Controleer en vul aan: `docs/CONVENTIONS.md` — voeg patronen toe die nog ontbreken (stijlgids/linting, teststrategie)
- [ ] Voer een bouwcheck uit: `pip install -r requirements.txt` gevolgd door `func start`
- [ ] Zoek de `routePrefix`-discrepantie uit: `host.json` zet `"api"`, README/USER_MANUAL claimen geen prefix — verifieer tegen productiegedrag en corrigeer de docs
- [ ] Schrijf eerste tests — er is momenteel geen testframework/testbestanden in het project
- [ ] `/availability` roept nu ook `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan bij `vorm_afspraak=buitendienst` (zie `docs/DECISIONS.md`, 2026-09-01). Deze SP staat nog niet op `Advitas_test`/productie (zie `AfspraakPlanner/docs/TODO.md`) — voer eerst het `CREATE OR ALTER PROCEDURE`-script uit en controleer of de databasegebruiker die `AfspraakMaken` gebruikt EXECUTE-rechten heeft op deze SP en SELECT-rechten op `PowerBI.AdviseurRegio`, vóór een end-to-end test tegen `SQL_DATABASE_TEST`.
