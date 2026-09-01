# Conventions

## Naamgeving

- Eén platte module `function_app.py` — geen packages/submodules.
- Publieke route-handlers: kort en zonder prefix, genoemd naar de route zelf (`afspraak`, `reservering`, `availability`).
- Private helpers: `_`-prefix, snake_case, beschrijvende werkwoordsvorm (`_parse_payload`, `_get_connection`, `_call_sp_dynamic`, `_extract_db_error_details`).
- Domeinbegrippen in het Nederlands, ook in variabelenamen: `klant_id`, `adviseur_id`, `campagne_id`, `datum`, `tijd`, `duur_kwartieren`, `foutmelding`.
- SQL-gerelateerde helpers hebben vaak `sp`/`sql` in de naam (`_get_sp_parameters`, `_call_sp_dynamic`, `_to_sql_value`, `_declare_sql_type`).
- Custom exception: `ValidationError` (PascalCase, standaard Python-exceptionconventie) voor input-validatiefouten.

## Projectstructuur

```
AfspraakMaken/
├── function_app.py                 Alle routes, validatie en SQL-aanroepen (single-file)
├── host.json                       Host-configuratie (routePrefix, Application Insights)
├── requirements.txt                azure-functions, pyodbc
├── local.settings.json.example     Voorbeeld env-config (niet gecommit als echt bestand)
├── README.txt                      Korte endpoint-documentatie (Nederlands)
├── USER_MANUAL.md                  Uitgebreide handleiding incl. curl-voorbeelden (Engels)
└── .funcignore                     Sluit .venv uit van functie-deployment
```

Geen `src/`, geen aparte modules per route — alles staat in `function_app.py`.

## Patronen die we gebruiken

- **Azure Functions v2 decorator-stijl**: routes worden gedefinieerd met `@app.route(route="...", methods=[...])` op een `func.FunctionApp()`-instantie.
- **Stored-procedure-only writes**: geen directe SQL INSERT/UPDATE — zie `CLAUDE.md` → Kritieke Regels.
- **Twee aanroep-strategieën voor stored procedures:**
  - *Vaste parameter-mapping* voor `spMaakAfspraak` (`_call_sp_maak_afspraak`) — expliciete parameterlijst in vaste volgorde.
  - *Dynamische parameter-matching* voor `spMaakReservering` en `psAgendaPicker_GetAvailability` (`_call_sp_dynamic`) — leest de daadwerkelijke SP-parameters op via `sys.parameters` en matcht ze case-insensitief tegen de request-payload (genormaliseerd met `_normalize_name`, met alias-ondersteuning zoals `campaignid`/`campagneid`).
- **Expliciete connectiebeheer**: elke route opent zelf een `pyodbc`-connectie en cursor, en sluit ze in een `finally`-block.
- **Expliciete commit/rollback**: `conn.commit()` bij succes, `conn.rollback()` bij elke foutafhandelingstak.
- **Consistente JSON-response-shape**: `{"result": "success", "input": ..., "matched_parameters": ..., "stored_procedure_output": ..., "stored_procedure_result": ...}` bij succes; `{"error": "..."}` (soms met `details`) bij fouten.
- **`run`-parameter bepaalt databasekeuze**: `run=prod` → productiedatabase, elke andere waarde → testdatabase (`_resolve_database_for_run`).

## Patronen die we NIET gebruiken

<!-- onbekend — vul aan -->

## Error Handling

- `ValidationError` (custom exception) voor invalide input → HTTP 400 met `{"error": "<boodschap>"}`.
- `pyodbc.Error` → HTTP 500 met `{"error": "...", "details": {...}}` (via `_extract_db_error_details`), altijd met `conn.rollback()` en `logging.exception(...)`.
- Generieke `RuntimeError` (bijv. ontbrekende DB-config, onbekende SP) → HTTP 500 met de foutboodschap.
- Overige onverwachte `Exception` → HTTP 500 met generieke Nederlandse boodschap ("Interne fout bij uitvoeren van stored procedure."), met `logging.exception(...)` voor de volledige stacktrace in Application Insights.
- Bij een `foutcode != 0` teruggegeven door `spMaakReservering` zelf: expliciete rollback en HTTP 500 met de SP-foutdetails (niet als Python-exceptie, maar als data uit de output-parameters).

## Database & Migraties

Geen migraties in deze repo. Schema en stored procedures (`spMaakAfspraak`, `spMaakReservering`, `psAgendaPicker_GetAvailability`) leven volledig in SQL Server, buiten deze codebase. Wijzigingen aan het gedrag van een endpoint vereisen meestal een wijziging aan de bijbehorende stored procedure in de database, niet (alleen) aan `function_app.py`.

## Testing

<!-- onbekend — vul aan: geen testframework of testbestanden aangetroffen in de scan -->

## Stijlgids

<!-- onbekend — vul aan: geen linting-config (bijv. `.flake8`, `ruff.toml`, `pyproject.toml`) aangetroffen in de scan -->
