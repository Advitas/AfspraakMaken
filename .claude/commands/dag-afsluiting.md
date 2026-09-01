---
description: Sluit de werkdag af — synchroniseer waarheid-docs (CONVENTIONS / ARCHITECTURE / GLOSSARY / README / CONTRIBUTING) met code-realiteit
---

Workflow voor einde werkdag. Verwerkt accumuleerde drift-signals (uit `docs/DOC-SIGNALS.md`) en code-changes sinds vorige dag-afsluiting, en updatet de 5 "waarheid-docs" in één batch.

**De 5 waarheid-docs:** `docs/CONVENTIONS.md`, `docs/ARCHITECTURE.md`, `docs/GLOSSARY.md`, `README.md`, `CONTRIBUTING.md`.

---

## Stap 1 — Pre-flight

1. **Working tree clean?** Run `git status`. Als niet clean: stop, vraag de gebruiker te committen/discarden voordat we verder gaan.
2. **Build groen?** Run het build command zoals gespecifieerd in `CLAUDE.md` (Build & Run sectie). Als het build command in CLAUDE.md ontbreekt of "geen build" zegt: skip deze check. Als rood: stop met "Fix eerst de build — geen docs-update op kapotte staat".
3. **Zorg dat `docs/DOC-SIGNALS.md` bestaat.** Als het ontbreekt: maak aan met deze header:

   ```
   # Doc-drift signals — buffer voor /dag-afsluiting

   Append-only door `/handoff`. Geleegd door `/dag-afsluiting` in dezelfde commit als de doc-updates.

   ---
   ```

4. **Vind anker:**
   - Primair: `git log --grep="^Docs: dag-afsluiting" -1 --format=%H`.
   - Cold start (geen resultaat): `git log --diff-filter=A --format=%H -- docs/DOC-SIGNALS.md | Select-Object -Last 1` (PowerShell) of `git log --diff-filter=A --format=%H -- docs/DOC-SIGNALS.md | tail -1` (bash). Dat is de commit waar DOC-SIGNALS.md is aangemaakt.
   - Als DOC-SIGNALS.md zojuist in Stap 1.3 is aangemaakt (uncommitted): gebruik huidige HEAD als anker. Geen retroactieve drift-detectie.

   Sla deze hash op als `<anker>`.

## Stap 2 — Verzamel inputs (drie bronnen)

1. **Lees `docs/DOC-SIGNALS.md`** volledig. Identificeer alle entries die beginnen met `## YYYY-MM-DD — sessie N — TARGET-DOC`.
2. **Run** `git diff <anker>..HEAD --stat` en bekijk welke files veranderd zijn.
3. **Run** `git log <anker>..HEAD --oneline -- docs/HANDOFF.md` om te zien welke sessies er waren.

Indien zowel DOC-SIGNALS.md leeg (geen `## `-entries) én geen relevante diff (zie Stap 3 voor wat "relevant" is): meld "Geen drift sinds <anker-datum>. Werk schoon." en stop. Géén commit, géén Notion-actie.

## Stap 3 — Map per waarheid-doc

Voor elke van de 5 waarheid-docs:

**Wat is "relevante diff" per doc?**

| Doc | Diff-paths die drift suggereren |
|---|---|
| `ARCHITECTURE.md` | Nieuwe top-level directories. Nieuwe services, middleware, controllers, routes, of equivalente architectonische units (stack-afhankelijk: `services/`, `controllers/`, `routes/`, `handlers/`, `Areas/`, `Services/`, etc.). Nieuwe ORM-types of database-context classes. |
| `CONVENTIONS.md` | Nieuwe patterns in frontend assets (`src/`, `wwwroot/`, `static/`, `assets/`), nieuwe attribute- of decorator-conventions, nieuwe naming-stijlen, nieuwe hook-files of utility-conventies. |
| `GLOSSARY.md` | Nieuwe types in domain-folders, nieuwe enums, nieuwe role/status-namen, nieuwe business-concepten of branded types. |
| `README.md` | Config-bestanden (`appsettings*.json`, `.env.example`, `pyproject.toml`, `package.json` scripts, etc.), ports, connection strings, login-credentials, dev-setup-bestanden, scripts in `scripts/` of project-root. |
| `CONTRIBUTING.md` | `.claude/`, branch-config, CI/CD-files (`.github/workflows/`, `.gitlab-ci.yml`, etc.), commit-regels, PR-templates. |

> **Stack-agnostisch:** dit zijn richtlijnen — pas de paden aan op je eigen project. Het LLM-executor mag eigen oordeel gebruiken op basis van CLAUDE.md's "Stack" en `docs/CONVENTIONS.md`.

**Voor elke doc:**

1. Verzamel signals uit DOC-SIGNALS.md die deze doc targeten.
2. Bekijk relevante diff-paths.
3. Lees huidige doc-versie (overslaan als de doc niet bestaat — flag dit dan in het rapport).
4. **Draft een patch** (concrete edit met expliciete regel-locatie of insertie-context). Geen prose-rapport — daadwerkelijke diff-tekst.
5. Bouw de doc-sectie van het rapport (zie Stap 4).

## Stap 4 — Presenteer batch-rapport aan gebruiker

Toon één rapport in de chat met **per doc** deze layout:

```
═══════════════════════════════════════════════════════════
[DOC-NAAM].md — drift gedetecteerd
═══════════════════════════════════════════════════════════
Bron: <N signals + samenvatting>, <relevante diff-paths>
Voorgestelde edit:
  <concrete diff, leesbaar>

[a] accept   [e] edit   [c] code is fout   [s] skip
```

Stel de keuze per doc via `AskUserQuestion` met opties: `accept`, `edit`, `code is fout`, `skip`.

**Belangrijke variant — signal vs diff conflict:** als het signal zegt X maar de code-diff laat Y zien, presenteer beide en vraag: "signal zegt X, code zegt Y — welke is waarheid?". Niet zelf gokken.

Voor docs zonder drift: laat ze weg uit het rapport (toon niet alle 5 standaard — alleen die met drift).

## Stap 5 — Verwerk gebruikers-keuzes

Per doc:

- **`accept`** → pas de voorgestelde edit toe op de file.
- **`edit`** → vraag de gebruiker om hun voorstel via een tweede `AskUserQuestion` of vrije tekst; pas dat toe.
- **`code is fout`** → de werkelijkheid wijkt af van wat het signal beweert; doc niet aanraken. Vraag via `AskUserQuestion` waar de Advisory-entry naartoe moet:
  - Detecteer welke TODO-bestanden bestaan: `docs/TODO_shared.md`, `docs/TODO_<naam>.md` (uit `.claude/developer` of `## Key People` in CLAUDE.md), `docs/TODO.md`.
  - Bied alleen bestaande opties aan als keuzes.
  - Default-volgorde in de opties-lijst: `TODO_shared.md` eerst, dan persoonlijke, dan fallback `TODO.md`.
  - **Bij ≥3 "code is fout"-entries in één run:** bied ook een extra optie aan: "Alles naar `<gekozen bestand>`" om de rest van de run niet meer te vragen.
  - Append in de gekozen file onder de `## Advisory / technical debt`-sectie (maak aan als die niet bestaat):

    ```
    - **Code wijkt af van [DOC] pattern X** — [beschrijving]. Uit dag-afsluiting YYYY-MM-DD.
    ```

- **`skip`** → niets doen; signal blijft in DOC-SIGNALS.md voor volgende run.

## Stap 6 — DOC-SIGNALS.md leegmaken

Verwijder uit `docs/DOC-SIGNALS.md` alle entries waarvoor de gebruiker `accept`, `edit` of `code is fout` koos. Behoud:
- De header (eerste paar regels tot en met de eerste `---`).
- Eventuele `skip`-entries.

Schrijf de gewijzigde file terug.

## Stap 7 — Eén commit

Stage alle waarheid-doc-wijzigingen + DOC-SIGNALS.md + het juiste TODO-bestand (indien gewijzigd door `code is fout`).

Commit-message (verplicht format — eerste regel exact zo voor de anker-grep):

```
Docs: dag-afsluiting YYYY-MM-DD

[1-3 zinnen over wat is verwerkt: hoeveel signals, welke docs geüpdatet, code-is-fout-doorschuivingen]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

## Stap 8 — Notion-acties (alleen als `CLAUDE.md` een `Notion Coding Project` URL bevat)

Als `CLAUDE.md` géén `Notion Coding Project` URL bevat: **sla deze hele stap over**. Ga direct naar Stap 9.

> **Notion-falen is niet fataal.** Als een Notion-aanroep faalt (netwerk, MCP, ontbrekende permissies): log een waarschuwing in de chat, sla de rest van Stap 8 over, en ga door naar Stap 9. De lokale commit uit Stap 7 is al gemaakt en blijft geldig. Notion-pad is best-effort.

### Stap 8.1 — Notion-config lezen

1. Controleer of `~/.claude/notion.md` bestaat → nee: sla **Stap 8 volledig** over
2. Lees `~/.claude/notion.md`; bestaat `.claude/notion.md` ook in het huidige project? → lees dat ook; project-level waarden overschrijven globale waarden per database-sleutel
3. Lees het `Notion Workspace:` veld uit `CLAUDE.md` (onder Quick Facts) → dit is de actieve workspace-naam
   → Geen `Notion Workspace:` veld: sla Stap 8 over
4. Zoek onder `## Workspace: <naam>` de benodigde collection-IDs op:
   - `nacht_rapporten` → dag-rapporten-database (stap 8.2)
   - `sessielogboek` → sessielogboek-database (stap 8.3)
   - `adr` → ADR-database (stap 8.4)

### Stap 8.2 — Dag-rapport aanmaken in "Dag Rapporten" database

Maak een nieuwe pagina aan via `notion-create-pages`.

**Workspace-referentie (Dag Rapporten data source):**

Gebruik het `nacht_rapporten:` veld uit de Notion-config (zie Stap 8.1)

Properties:

```
Rapport naam:        [PROJECT_NAAM] — [datum YYYY-MM-DD]
Project:             "[\"[NOTION_PROJECT_URL]\"]"
date:Datum:start:    [datum van vandaag, YYYY-MM-DD]
date:Datum:is_datetime: 0
Docs aangepast:      [multi-select: lijst van waarheid-docs die zijn geüpdatet]
Signals verwerkt:    [getal: aantal accept + edit]
Doorgeschoven naar TODO: [getal: aantal code-is-fout]
Skipped:             [getal: aantal skip]
View:                ["[WORKSPACE]"]
```

Content (de subpagina):

```markdown
## Samenvatting
[2-3 regels: welke docs geraakt, hoeveel signals verwerkt, opvallendste change]

## Gewijzigde docs
[Per doc:]
**[DOC-NAAM].md** — [korte beschrijving van wat is geüpdatet]

## Doorgeschoven naar TODO
[Per code-is-fout-entry:]
- [beschrijving] → [TODO-bestand]

## Skipped (voor volgende run)
[Per skip-entry:]
- [signal-beschrijving] — reden om te skippen
```

### Stap 8.3 — Tech Stack updaten op Coding Project (alleen bij ARCHITECTURE-wijziging)

Als `ARCHITECTURE.md` in deze run is geüpdatet (Stap 5 `accept` of `edit`):

1. Fetch Coding Project pagina via `notion-fetch`.
2. Update de **Tech Stack** sectie via `notion-update-page` met de nieuwe architectuur-info (zelfde aanroep-pattern als `/handoff` stap 11).

### Stap 8.4 — Nieuwe ADR's pushen (alleen als DECISIONS.md is geraakt)

Als `/dag-afsluiting` zelf een ADR aan `docs/DECISIONS.md` heeft toegevoegd (zeldzaam, maar mogelijk bij grote drift-conclusies):

Voor elke ADR een entry in de ADR database (zelfde data sources als `/handoff` stap 11):

Gebruik het `adr:` veld uit de Notion-config (zie Stap 8.1)

Properties + content zoals in `/handoff` stap 11 (hergebruik dat pattern, niet apart documenteren).

## Stap 9 — Eind-rapport

Toon korte samenvatting in de chat:

```
✅ Dag-afsluiting verwerkt

   Anker was:  [hash van vorige Docs: dag-afsluiting]
   Verwerkt:   [N] signals  ([accept] accepted, [edit] edited, [code-is-fout] doorgeschoven)
   Skipped:    [K] (blijven in DOC-SIGNALS voor volgende run)
   Gewijzigd:  [lijst van waarheid-docs]
   TODO:       [lijst per bestand: bv. "TODO_shared.md +2, TODO_mel.md +1"]
   Commit:     [nieuwe-hash]
   Notion:     [URL naar dag-rapport pagina, of "n.v.t. (geen Notion in dit project)"]
```

---

**Belangrijk:**

- **Evidence before assertions:** pre-flight build-check is verplicht. Nooit "klaar" zonder die check.
- **Eén commit per dag-afsluiting** (niet per doc) — anders vervuilt git history.
- **Nooit een waarheid-doc raken zonder de gebruiker's expliciete `accept` of `edit`** per doc.
- **Géén lege commits** (geen drift = geen commit).
- **Notion is optioneel:** als CLAUDE.md geen Notion Coding Project URL bevat, slaat stap 8 zichzelf over. Het command werkt volledig zonder Notion.
