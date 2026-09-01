# Handoff

**Datum:** 2026-08-25
**Branch:** main
**Laatste commit:** `41809f4 info`

## Build-status

Build command: geen build-stap. Run-check: `pip install -r requirements.txt` gevolgd door `func start` — niet gecontroleerd in deze sessie, voer zelf uit.

## Wat er in deze sessie is gebeurd

Template toegepast op bestaand project. Alle docs-bestanden zijn aangemaakt en gevuld op basis van codebase-scan en projectinformatie.

## Open items

1. Bouwcheck uitvoeren: `pip install -r requirements.txt` en `func start`, en de drie endpoints (`/api/afspraak`, `/api/reservering`, `/api/availability`) lokaal testen tegen `SQL_DATABASE_TEST`.
2. Discrepantie uitzoeken: `host.json` zet `routePrefix` op `"api"`, maar `README.txt`/`USER_MANUAL.md` beschrijven de routes zonder prefix (`/afspraak`, `/reservering`, `/availability`) — verifieer wat productie daadwerkelijk gebruikt en update de docs.
3. Onbekende secties aanvullen: CI/CD-pipeline en teststrategie in `docs/ARCHITECTURE.md` / `docs/CONVENTIONS.md` (geen CI-config of testframework aangetroffen in de scan).
