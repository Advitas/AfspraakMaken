---
description: Start een nieuwe sessie — laad context en bevestig begrip
---

Voer de volgende stappen in deze volgorde uit:

1. Lees `CLAUDE.md` volledig
2. Bepaal wie er aan het werk is:
   a. Controleer of `.claude/developer` bestaat — zo ja, gebruik die naam (geen vraag nodig)
   b. Zo niet: kijk naar de developer/team-sectie in `CLAUDE.md` — als er meerdere developers staan, vraag dan wie er nu werkt
   c. Bestaan er persoonlijke `docs/TODO_<naam>.md` bestanden? Laad dan de juiste én `docs/TODO_shared.md`
   d. Zo niet: lees `docs/TODO.md`
3. Lees `docs/HANDOFF.md` volledig
4. Als `CLAUDE.md` een `Notion Coding Project` URL bevat: fetch die pagina via `notion-fetch` en lees het **Sessielogboek** (laatste entry) en de **Tech Stack** sectie. Dit geeft aanvullende context bovenop HANDOFF.md.
5. Als `CLAUDE.md` een `Notion Coding Project` URL bevat: **Notion Taken synchroniseren**
   **Notion-config lezen:**
   1. Controleer of `~/.claude/notion.md` bestaat → nee: sla stap 5 volledig over
   2. Lees `~/.claude/notion.md`; bestaat `.claude/notion.md` ook in het huidige project? → lees dat ook; project-level waarden overschrijven globale waarden per database-sleutel
   3. Lees het `Notion Workspace:` veld uit `CLAUDE.md` (onder Quick Facts) → dit is de actieve workspace-naam
      → Geen `Notion Workspace:` veld aanwezig: sla stap 5 over
   4. Zoek onder `## Workspace: <naam>` het `tasks:` veld op → gebruik die collection ID als taken-database
   - Zoek taken van dit project via `notion-search`
   - Voor elke taak met Status "Done" die nog als open item in `docs/TODO.md` staat: verplaats naar Done sectie in `docs/TODO.md`
   - Vermeld open Notion-taken die nog niet in `docs/TODO.md` staan in de samenvatting (zodat de developer ze kan oppakken)
6. **Template versiecheck** (alleen als `.claude/.template-version` en `.claude/.template-source` bestaan):
   - Lees `.claude/.template-version` (geïnstalleerde versie)
   - Lees `.claude/.template-source` (pad naar template-repo)
   - Lees `<template-pad>/VERSION`, waarbij `<template-pad>` de inhoud is van `.template-source` (huidige template-versie)
   - Als de versies verschillen: voeg toe aan de samenvatting: `⚠️ Template is bijgewerkt (geïnstalleerd: X, actueel: Y) — run /sync-template vanuit de template-repo`
   - Als de versies gelijk zijn of de bestanden niet bestaan: geen melding
6b. **Check `docs/DOC-SIGNALS.md`** (als die bestaat). Tel het aantal entries dat begint met `## ` (negeer de header). Als > 0: noteer "**N onverwerkte doc-signals — overweeg `/dag-afsluiting` aan einde werkdag**" voor in de samenvatting (stap 10). Als 0 of file bestaat niet: geen vermelding. **Niet zelf verwerken.**
7. Run `git status` — check of er uncommitted changes zijn
8. Run `git log -3 --oneline` — laatste 3 commits
9. Run het build command uit `CLAUDE.md` — evidence-based build status, geen aanname
10. Geef een bondige samenvatting (max 10 regels) met:
   - Actieve developer (indien meerdere developers in project)
   - Huidige project status
   - Laatste commit
   - Build status (green/red)
   - Uncommitted changes (indien aanwezig)
   - Top 1-3 items uit TODO Next Up
   - Eventuele open Notion-taken die nog niet in TODO staan
   - **Onverwerkte doc-signals** (als > 0, uit stap 6b)
   - Voorstel voor deze sessie

BELANGRIJK:
- Begin NOG NIET met code wijzigen totdat ik bevestig
- Als er uncommitted changes zijn: vraag of die gecommit of gediscarded moeten worden
- Als Superpowers actief is (zie CLAUDE.md): laat skills activeren voor features en bugs — ga niet zelf direct implementeren

Wacht op mijn bevestiging voor je verder gaat.
