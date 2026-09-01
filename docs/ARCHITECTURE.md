# Architecture

## Systeem-overzicht

AfspraakMaken is een backend-only Azure Function die door interne systemen (bijv. campagne-/marketingsystemen — zie de `SALEOP_*`-omgevingsvariabelen in `local.settings.json.example`, die wijzen op een gekoppeld "SaleOp"-achtig campagnesysteem) wordt aangeroepen om:

1. een afspraak aan te maken (`/afspraak`),
2. een reservering aan te maken (`/reservering`),
3. beschikbaarheid van adviseurs op te vragen (`/availability`).

Er is geen frontend/UI in deze repo — de functie wordt aangeroepen via HTTP (function-level auth key) door andere systemen of scripts. De enige externe afhankelijkheid buiten Azure zelf is de SQL Server database, die via stored procedures wordt aangesproken.

## Tech Stack

| Laag | Techniek |
|---|---|
| Taal/runtime | Python (Azure Functions Python worker) |
| Framework | Azure Functions v2, decorator-stijl (`@app.route`, package `azure-functions`) |
| Database | SQL Server, via `pyodbc` + ODBC Driver 18 for SQL Server |
| Hosting | Azure Functions (Function App), function-level auth (`func.AuthLevel.FUNCTION`) |
| Monitoring | Application Insights (sampling-config in `host.json`) |
| Build | geen — geen bundel/compile-stap, alleen `pip install` |
| CI/CD | <!-- onbekend — vul aan (geen .github/workflows of andere CI-config aangetroffen in de scan) --> |

## Data Model

Geen ORM/modellen in deze repo — het schema leeft volledig in SQL Server. Op basis van stored-procedure-parameters en payload-velden in `function_app.py` zijn de volgende domeinentiteiten af te leiden:

| Entiteit | Herkenbaar aan |
|---|---|
| Klant | `klant_id` (0 = nieuwe klant via SP), `naam`, `email` |
| Adviseur | `adviseur_id` (int, lijst, of CSV-string — `_parse_adviseur_ids`) |
| Afspraak | route `/afspraak`, `spMaakAfspraak`, velden `datum`, `tijd`, `duur_kwartieren`, `vorm_afspraak`, `afspraak_type`, `is_nieuwe_afspraak` |
| Reservering | route `/reservering`, `spMaakReservering`, dynamisch gematchte velden |
| Campagne | `campagne_id`/`campaign_id`, `campagne_naam` (output van beide SP's) |
| Product | `productnaam` |
| Opportunity | `create_opportunity_if_missing` |
| Insteek | `insteek_id` |
| Productcategorie (prodcat) | `prodcat_id` |
| Adviescategorie (advcat) | `advcat_id` |
| Agenda/Availability | route `/availability`, `psAgendaPicker_GetAvailability` |

## Request Flows

**`/afspraak` (POST) — vaste parameter-mapping:**
1. Body wordt geparsed als JSON (`req.get_json()`).
2. `_parse_payload` valideert en normaliseert verplichte velden (`datum`, `tijd`, `duur_kwartieren`, `adviseur_id`, `klant_id`, `campagne_id`) en optionele velden; gooit `ValidationError` (→ HTTP 400) bij fouten.
3. `_get_connection` bouwt een connection string (uit `SQL_CONNECTION_STRING`, of losse `SQL_*`-variabelen) — welke database gekozen wordt hangt af van de `run`-payloadwaarde (`_resolve_database_for_run`: `run=prod` → `SQL_DATABASE_PROD`, anders → `SQL_DATABASE_TEST`, met `SQL_DATABASE` als fallback).
4. `_call_sp_maak_afspraak` roept `[dbo].[spMaakAfspraak]` aan met een vaste parameterlijst en leest output-parameters (`klant_id`, `campagne_id`, `afspraak_id`, `campagne_naam`, `foutmelding`) plus resultsets.
5. Bij succes: `conn.commit()` en HTTP 200 met JSON-response. Bij databasefout of onverwachte exceptie: `conn.rollback()` en HTTP 500.

**`/reservering` (POST) — dynamische parameter-matching:**
1. Body wordt gevalideerd (`_validate_make_reservation_payload`: verplicht `datum`, `tijd`, `adviseur_id`, `run`, `duur_kwartieren`, `campaign_id`/`campagne_id`; `MMJO/funnel` extra verplicht bij `campagne_id`/`campaign_id` 230).
2. `_prepare_make_reservation_payload` normaliseert `adviseur_id` naar CSV en mapt `MMJO/funnel` naar `mmjo_funnel`.
3. `_call_sp_dynamic` leest de daadwerkelijke parameters van `[dbo].[spMaakReservering]` via `sys.parameters`, matcht ze case-insensitief tegen de payload (met aliassen zoals `campaignid`/`campagneid`), en bouwt de EXEC-statement dynamisch op. Als er geen parameters gevonden worden, valt de code terug op `_call_sp_maak_reservering_fallback` (vaste mapping).
4. Bij een `foutcode != 0` in de SP-output: rollback en HTTP 500 met de SP-foutdetails. Anders: commit en HTTP 200.

**`/availability` (GET/POST):**
1. Payload komt uit querystring en/of JSON body (`_extract_request_payload`).
2. `_call_sp_dynamic` roept `[dbo].[psAgendaPicker_GetAvailability]` aan, op dezelfde dynamische manier als `/reservering`.
3. Response bevat `matched_parameters`, `stored_procedure_output` en `stored_procedure_result`.

## Deployment

- **Lokaal:** `python -m venv .venv` → activeren → `pip install -r requirements.txt` → `func start`. Vereist Azure Functions Core Tools v4 en ODBC Driver 18 for SQL Server lokaal geïnstalleerd.
- **Deploy:** `func azure functionapp publish <FUNCTION_APP_NAME>` vanuit de projectmap.
- **Productie-URL:** `https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net`
- **Route-prefix:** `host.json` zet `extensions.http.routePrefix` op `"api"` — lokaal en (vermoedelijk) in productie zijn de routes dus `/api/afspraak`, `/api/reservering`, `/api/availability`. `README.txt`/`USER_MANUAL.md` beschrijven de routes echter zonder `/api`-prefix — dit is niet geverifieerd tegen het huidige productiegedrag, zie `docs/TODO.md`.
- **CI/CD:** <!-- onbekend — vul aan, geen CI-config aangetroffen in de scan -->

## Externe Afhankelijkheden

| Dienst | Doel | Config |
|---|---|---|
| SQL Server | Opslag klant/afspraak/reservering-data; alle writes via stored procedures | `SQL_CONNECTION_STRING`, of `SQL_SERVER`/`SQL_PORT`/`SQL_DATABASE_PROD`/`SQL_DATABASE_TEST`/`SQL_DATABASE`/`SQL_USER`/`SQL_PASSWORD` |
| ODBC Driver 18 for SQL Server | DB-connectiviteit vanuit `pyodbc` | `SQL_ODBC_DRIVER` (default ingesteld in code), moet lokaal/op de Function App geïnstalleerd zijn |
| Application Insights | Logging/monitoring van de Function App | `host.json` (sampling-config); connectiestring wordt door Azure zelf beheerd via app settings |
| Azure Functions runtime | Hosting, HTTP-trigger, function-level auth (`code`-key) | `host.json`, Azure Function App-instellingen |
