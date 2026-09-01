---
name: ui-theme-richtlijnen
description: Richtlijnen voor het consistent toepassen van de Advitas UI en theme in React-schermen.
license: MIT
---

# UI/Theme Richtlijnen

Gebruik `src/styles/app.css` als bron voor:
- kleurgebruik (`--brand-*`, `--accent-*`, `--neutral-*`)
- typografie
- spacing

Gebruik componenten in `src/components/` als visuele referentie voor:
- header/logo uitstraling
- card-opbouw
- knop-hiërarchie
- labels en statusweergave

## Regels
1. Houd UI zakelijk en rustig.
2. Gebruik duidelijke primaire CTA's.
3. Houd touch/desktop bruikbaar.
4. Vermijd visuele ruis en overbodige navigatie.
5. Maak geen afhankelijkheid naar `src/ui` of `src/theme`.

## Compatibiliteit
- Claude skillformaat blijft onder `.claude/skills`.
- GitHub Copilot equivalent staat in `.github/prompts/ui-theme-apply.prompt.md`.
