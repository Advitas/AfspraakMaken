---
description: Genereer handoff document voor de volgende sessie
---

Schrijf `docs/HANDOFF.md` volledig opnieuw (overschrijven, niet appenden).

Checklist:

1. **Datum bovenaan:** vandaag
2. **Project status:** huidige fase (bijv. greenfield, MVP, maintenance mode)
3. **Laatste werkende staat:**
   - `git branch --show-current`
   - `git log -1 --oneline`
   - Run het build command uit CLAUDE.md — rapporteer het echte resultaat
4. **Wat er deze sessie is gebeurd:** 2-4 zinnen, concreet en feitelijk. Geen vage samenvattingen.
5. **Git wijzigingen:**
   - Indien commits gedaan: `git diff --stat HEAD~N HEAD` (N = aantal commits deze sessie)
   - Indien alleen working copy changes: `git diff --stat`
6. **Open items / Next steps:** concreet, geordend op prioriteit. Geen "misschien X" — "doe X".
7. **Belangrijke context die niet mag verdwijnen:** ontdekkingen, workarounds, gotchas uit deze sessie die niet elders zijn gedocumenteerd.
7b. **Doc-drift signals voor `/dag-afsluiting`.** Loop deze sessie langs en spot wijzigingen die één van de 5 waarheid-docs raken:

    | Trigger | Target-doc |
    |---|---|
    | Nieuwe service / middleware / area / hook-pipeline / pipeline-aanpassing | `ARCHITECTURE.md` |
    | Nieuw code-pattern of project-conventie (naming, hooks, attributes) | `CONVENTIONS.md` |
    | Nieuwe domein-term, rol, status, business-concept | `GLOSSARY.md` |
    | Wijziging in dev-setup, URL, credential, connection string, scripts, ports | `README.md` |
    | Wijziging in branch-flow, commit-regels, samenwerk-process, PR-flow | `CONTRIBUTING.md` |

    Voor elk gespot signal: zorg dat `docs/DOC-SIGNALS.md` bestaat (maak aan met standaard header als het ontbreekt — zie format hieronder), en append onderaan dit format:

    ```
    ## YYYY-MM-DD — sessie N — TARGET-DOC

    **Wat:** [beschrijving]
    **Code:** [bestanden]
    **Commit:** [hash]
    **Voorgestelde plek:** [hint voor /dag-afsluiting]
    ```

    Standaard header voor een nieuw aangemaakt DOC-SIGNALS.md (gebruik alleen als file ontbreekt):

    ```
    # Doc-drift signals — buffer voor /dag-afsluiting

    Append-only door `/handoff`. Geleegd door `/dag-afsluiting` in dezelfde commit als de doc-updates.

    ---
    ```

    **Niet zelf de waarheid-doc aanraken** — dat is `/dag-afsluiting`'s job. Als geen signals: niets toevoegen (geen lege entry).
8. **Nieuwe ADR's nodig?** Als er architecturale keuzes zijn gemaakt, append naar `docs/DECISIONS.md`.
9. **Update `docs/TODO.md`:**
   - Voltooide items → Done sectie (max 5 meest recent)
   - Nieuwe items uit deze sessie → Next Up (max 5 items)
   - Items die nu geblokkeerd zijn → Blocked met reden
**Notion-config lezen (geldt voor stap 10 en 11):**
1. Controleer of `~/.claude/notion.md` bestaat → nee: sla stap 10 en 11 volledig over
2. Lees `~/.claude/notion.md`; bestaat `.claude/notion.md` ook in het huidige project? → lees dat ook; project-level waarden overschrijven globale waarden per database-sleutel
3. Lees het `Notion Workspace:` veld uit `CLAUDE.md` (onder Quick Facts) → dit is de actieve workspace-naam
   → Geen `Notion Workspace:` veld: sla stap 10 en 11 over
4. Zoek onder `## Workspace: <naam>` de benodigde collection-IDs op:
   - `tasks` → taken-database (stap 10)
   - `sessielogboek` → sessielogboek-database (stap 11)
   - `adr` → ADR-database (stap 11)

10. **Notion Taken synchroniseren** (als `CLAUDE.md` een `Notion Coding Project` URL bevat):
    - Taken database:
      - Gebruik het `tasks:` veld uit de Notion-config (zie blok hierboven)
    - **Notion → TODO.md:** Gebruik `notion-search` om taken van dit project op te halen. Voor elke taak met Status "Done" die nog als open item in `docs/TODO.md` staat: verplaats die naar de Done sectie.
    - **Nieuwe taken aanmaken:** Vergelijk de vorige `docs/HANDOFF.md` Open items met de nieuwe Next Up in `docs/TODO.md`. Maak voor elk nieuw item een taak aan via `notion-create-pages`:
      - Properties: `Taak` (naam), `Status` ("Not started"), `Type` (["Programmeren"]), `View` (["<workspace-naam uit Notion Workspace: veld in CLAUDE.md>"]), `Project` (URL van het coding project als JSON-array: `["https://..."]`)
    - **Voltooide taken sluiten:** Voor elk item dat deze sessie naar Done is verplaatst: zoek de Notion-taak via `notion-search` op taaknaam, update `Status` naar "Done" via `notion-update-page`
11. **Notion Coding Project updaten** (als `CLAUDE.md` een `Notion Coding Project` URL bevat):
    - Fetch de coding project pagina via `notion-fetch`
    - Maak een nieuwe sessie-entry aan in de Sessielogboek database via `notion-create-pages`:
      - Parent data_source_id:
        - Gebruik het `sessielogboek:` veld uit de Notion-config (zie blok hierboven)
      - Properties: `Sessie` (korte sessietitel), `date:Datum:start` (vandaag, YYYY-MM-DD), `date:Datum:is_datetime` (0), `Project` (URL van het coding project uit CLAUDE.md als JSON-array), `Status` ("Gedaan")
      - Content: samenvatting van de sessie (wat gedaan, gotchas/beslissingen)
    - Update de **Tech Stack** sectie op de coding project pagina via `notion-update-page` als er iets is veranderd
    - Zijn er nieuwe ADR's gemaakt deze sessie? Maak dan voor elke ADR een entry aan in de ADR database via `notion-create-pages`:
      - Parent data_source_id:
        - Gebruik het `adr:` veld uit de Notion-config (zie blok hierboven)
      - Properties: `ADR` (bijv. "ADR-004: Naam van de beslissing"), `Project` (URL van het coding project uit CLAUDE.md als JSON-array), `Status` ("Geaccepteerd" voor geaccepteerde ADRs, "Vervangen" voor vervangen ADRs), `date:Datum:start` (vandaag, YYYY-MM-DD), `date:Datum:is_datetime` (0)
      - Content: achtergrond, beslissing, alternatieven overwogen, consequenties

Na het schrijven: toon zowel de nieuwe HANDOFF.md als de geüpdatete TODO.md voor review.

Belangrijk: evidence before assertions. Geen "alles werkt" zonder build check. Geen "klaar" zonder git status check.
