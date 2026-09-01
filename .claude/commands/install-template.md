---
description: Installeer de claude-project-template in een nieuw of bestaand project en vul alle docs in
---

TEMPLATE_DIR=

Voer de volgende stappen uit:

## Stap 0 — Machine Setup (eenmalig)

Heb je `/setup-machine` al gedraaid vanuit de template-repo? Dan kun je deze stap overslaan.

Zo niet: open de template-repo in Claude Code en draai `/setup-machine`. Dat configureert dit command op de juiste plek en zet Notion klaar.

---

## Stap 1 — Bepaal het doelpad

Voer uit: `pwd`

- Als de uitvoer gelijk is aan `$TEMPLATE_DIR`: meld
  "Je staat in de template-repo zelf. Geef het absolute pad op van het project waar je de template wil installeren."
  en wacht op invoer van de gebruiker.
- Anders: vraag "Wil je de template installeren in `<uitvoer van pwd>`?
  Bevestig (Enter) of geef een ander absoluut pad op."
  Wacht op het antwoord. Gebruik het bevestigde of opgegeven pad als DOELPAD voor alle volgende stappen.

## Stap 2 — Voer de installatie uit

Voer uit:
```
bash $TEMPLATE_DIR/install.sh DOELPAD
```
(vervang DOELPAD door het pad uit stap 1)

Als het script een foutmelding geeft of afbreekt: meld de fout en stop.

## Stap 3 — Pas apply-template toe op het doelproject

Controleer eerst of `DOELPAD/.claude/commands/apply-template.md` bestaat.
(vervang DOELPAD door het pad uit stap 1)

- Als het bestand **niet bestaat**: meld "Kon apply-template.md niet vinden in DOELPAD/.claude/commands/ — controleer of de installatie geslaagd is." en stop.
- Als het bestand **wel bestaat**: lees het en voer de instructies daarin uit, waarbij je DOELPAD gebruikt als werkmap voor alle bestandsbewerkingen:
  - Lees alle scan-bestanden vanuit DOELPAD (bijv. `DOELPAD/package.json`, `DOELPAD/README.md`, etc.)
  - Schrijf alle output-bestanden naar DOELPAD (bijv. `DOELPAD/CLAUDE.md`, `DOELPAD/docs/HANDOFF.md`, etc.)
