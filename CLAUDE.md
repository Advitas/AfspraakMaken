# Project: AfspraakMaken

## Quick Facts

- **Type:** Azure Function (Python) die klantafspraken en -reserveringen aanmaakt en beschikbaarheid ophaalt, uitsluitend via SQL stored procedures.
- **Status:** Maintenance mode
- **Stack:** Python Azure Functions v2 (`azure-functions`, decorator-stijl), single-file `function_app.py` — database SQL Server via `pyodbc`/ODBC Driver 18, uitsluitend via stored procedures
- **Services:** SQL Server database, Application Insights (logging via `host.json`), auth via Azure Functions function-level key
- **Productie:** `https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net`
- **Taal:** Nederlands voor docs, commits en domeinbegrippen (klant_id, adviseur_id, campagne_id) — README.txt is Nederlands, USER_MANUAL.md is Engels, code-comments/foutmeldingen zijn Nederlands

## Session Protocol

**Bij start van elke sessie:** gebruik `/start-session`
Leest CLAUDE.md → HANDOFF.md → TODO.md → git status → git log → build check → samenvatting.

**Bij einde van elke sessie (of context > 60%):** gebruik `/handoff`
Overschrijft HANDOFF.md, update TODO.md, append nieuwe ADR's naar DECISIONS.md.

## Working with Superpowers

Superpowers skills activeren automatisch. Niet handmatig overriden tenzij nodig.

- **Nieuwe feature:** volg éérst de `feature-route` skill (`.claude/skills/feature-route/SKILL.md`) — de routevraag (A: PoC / B: kleine feature / C: grote feature) bepaalt of en hoe brainstorming → write-plan → execute-plan draait
- **Bug:** Beschrijf met reproductie → systematic-debugging (reproduce → hypothesize → test → fix)
- **Research:** subagent-driven-development isoleert onderzoek, hoofdcontext blijft schoon
- **Skip Superpowers alleen bij:** triviale one-liners of expliciet "skip brainstorm"

## Build & Run

- **Install:** `python -m venv .venv` → `.\.venv\Scripts\Activate.ps1` → `pip install -r requirements.txt`
- **Lokaal draaien:** `func start` (routes op `http://localhost:7071/api/afspraak`, `/api/reservering`, `/api/availability` — `routePrefix` staat op `"api"` in `host.json`)
- **Deploy:** `func azure functionapp publish <FUNCTION_APP_NAME>`
- **Build-stap:** geen — pure Python, geen compile/bundle-stap

## Coding Principles

1. **Separate thinking from doing.** Plan voor code.
2. **Negative scope.** Expliciet wat NIET aangeraakt mag worden.
3. **Één file tegelijk** voor refactors.
4. **Bij bugs: alleen de bug.** Geen gelegenheids-refactor.
5. **Bestaande patronen uit `docs/CONVENTIONS.md`.** Consistentie boven elegantie.
6. **Evidence before assertions.** Nooit "done" zonder bewijs.

> **Uitwerking:** deze principes zijn geformaliseerd in de `karpathy-guidelines` skill
> (`.claude/skills/karpathy-guidelines/SKILL.md`) — roep die aan bij het schrijven, reviewen of
> refactoren van code.

## Project Status Regels

### Maintenance mode
- Focus op bugfixes en stabiliteit — geen nieuwe features zonder expliciet verzoek
- Wijzigingen zo klein en gericht mogelijk houden, geen speculatieve uitbreidingen
- Elke wijziging aan een stored-procedure-aanroep testen tegen `SQL_DATABASE_TEST` (via `run`-parameter) vóór een productie-deploy
- Documenteer afwijkend of onverwacht gedrag altijd in `DECISIONS.md` in plaats van het stilzwijgend te "fixen"

## Stop-and-Ask Situations

Stop en vraag ALTIJD bij:

- Elke wijziging die database-writes buiten stored procedures om introduceert (directe INSERT/UPDATE/DELETE)
- Wijzigingen aan connection-string-opbouw of aan welke database (`SQL_DATABASE_PROD`/`SQL_DATABASE_TEST`) voor welke `run`-waarde gebruikt wordt
- Nieuwe externe services of API-koppelingen
- Taken die groter blijken dan verwacht (>2 uur)

## Kritieke Regels

### Secrets & beveiliging (altijd van toepassing)

- Lees NOOIT `.env`, `.env.*`, `local.settings.json`, of andere secret-bestanden — ook niet als ik erom vraag
- Schrijf NOOIT secrets, wachtwoorden, tokens, connection strings of API-keys in code, logs, of chat
- Hardcode NOOIT credentials — altijd via environment variables (zie `local.settings.json.example` voor de verwachte namen)
- Als je een secret tegenkomt in bestaande code: meld het, fix het niet zelf zonder overleg

### Projectspecifieke regels

- **Nooit directe SQL INSERT/UPDATE** — alle database-writes lopen uitsluitend via stored procedures (`spMaakAfspraak`, `spMaakReservering`, etc.), zoals expliciet vastgelegd in `README.txt`
- `/reservering` en `/availability` matchen procedure-parameters dynamisch via `sys.parameters` (`_call_sp_dynamic`) — wijzig dit matching-mechanisme niet zonder de gevolgen voor beide endpoints te overzien
- `/afspraak` gebruikt een vaste parameter-mapping naar `spMaakAfspraak` (`_call_sp_maak_afspraak`) — geen dynamische matching

## Key People

- **Rob:** Developer
- **Daniel:** Developer

## File Update Discipline

| File | Wanneer updaten |
|---|---|
| `CLAUDE.md` | Alleen bij fundamentele shifts (vraag eerst) |
| `docs/HANDOFF.md` | Elke sessie bij afsluiting (overschrijft) — via `/handoff` |
| `docs/DECISIONS.md` | Append-only. Nieuwe ADR bij architecturale keuzes. |
| `docs/TODO.md` | Doorlopend bijwerken |
| `docs/DOC-SIGNALS.md` | **Append-only door `/handoff`** bij gespotte drift (waarheid-docs). **Geleegd door `/dag-afsluiting`** in dezelfde commit als de doc-updates. |
| `docs/ARCHITECTURE.md`<br>`docs/CONVENTIONS.md`<br>`docs/GLOSSARY.md`<br>`README.txt`<br>`USER_MANUAL.md` | **"Waarheid-docs"** — alleen via `/dag-afsluiting` (na review). Direct editen alleen bij fundamentele shifts (vraag eerst). |

## Documentation Map

```
AfspraakMaken/
├── CLAUDE.md                     ← je bent hier
├── function_app.py               Alle Azure Function routes + helpers (single-file)
├── host.json                     Azure Functions host-configuratie (routePrefix, logging)
├── requirements.txt              Python dependencies (azure-functions, pyodbc)
├── README.txt                    Endpoint-documentatie (Nederlands, kort)
├── USER_MANUAL.md                Uitgebreide handleiding (Engels)
├── local.settings.json.example   Voorbeeld env-config voor lokaal draaien
├── .funcignore
├── .claude/
│   ├── commands/                 Slash commands
│   ├── skills/                   feature-route, karpathy-guidelines, ui-theme-richtlijnen
│   └── reference/
└── docs/
    ├── ARCHITECTURE.md
    ├── CONVENTIONS.md
    ├── DECISIONS.md
    ├── GLOSSARY.md
    ├── HANDOFF.md
    ├── TODO.md
    └── DOC-SIGNALS.md
```
