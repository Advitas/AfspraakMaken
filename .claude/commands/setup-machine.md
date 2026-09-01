---
description: Eenmalige machine-setup voor de claude-project-template — installeert install-template, vult projects.txt en configureert Notion
---

Voer de volgende stappen uit. Draai dit command altijd vanuit de **template-repo directory** (de map waar je dit command uitvoert is de template-repo zelf).

## Stap 1 — Machine-paden

### 1.1 TEMPLATE_DIR bepalen

Voer uit: `pwd`

Sla de uitvoer op als `TEMPLATE_DIR` voor de rest van dit command.

### 1.2 install-template.md installeren of reviewen

Controleer of `~/.claude/commands/install-template.md` bestaat.

**Bestaat niet:**
1. Lees `TEMPLATE_DIR/.claude/commands/install-template.md`
2. Vervang de regel `TEMPLATE_DIR=` door `TEMPLATE_DIR=<uitvoer van stap 1.1>`
3. Schrijf het resultaat naar `~/.claude/commands/install-template.md`
4. Meld: "✅ install-template.md geïnstalleerd in ~/.claude/commands/"

**Bestaat al:**
1. Lees `~/.claude/commands/install-template.md`
2. Zoek de `TEMPLATE_DIR=` regel en toon de huidige waarde
3. Vraag: "install-template.md gevonden. Huidig TEMPLATE_DIR: `<waarde>` — klopt dit nog? (Enter = ja, of geef nieuw absoluut pad)"
4. Als nieuw pad opgegeven: update de `TEMPLATE_DIR=` regel en sla op. Meld: "✅ TEMPLATE_DIR bijgewerkt"
5. Als Enter: meld "✅ Geen wijziging nodig"

---

## Stap 2 — Projects scannen

### 2.1 Scanpad bepalen

Controleer of `TEMPLATE_DIR/projects.txt` bestaat en minstens één niet-lege regel bevat.

**Bestaat niet of leeg:**
Vraag: "Wat is het root-pad waar je projecten staan? (bijv. `/Users/naam/werk` of `C:\Users\naam\projects`)"
Sla het antwoord op als `SCANPAD`.

**Bestaat al:**
Lees de eerste regel uit `projects.txt` als hint voor het scanpad. Bepaal de gemeenschappelijke parent-map van de eerste regel als hint.
Vraag: "projects.txt gevonden. Wil je opnieuw scannen om nieuwe projecten toe te voegen of verouderde te verwijderen? (ja/nee)"
- "nee": meld "✅ projects.txt ongewijzigd" en ga naar Stap 3
- "ja": vraag "Bevestig het scanpad (bijv. de map die al je projecten bevat):" en sla het op als `SCANPAD`

### 2.2 Scan uitvoeren

Zoek recursief vanuit `SCANPAD` naar alle mappen die een `.claude/` submap bevatten. Sla `TEMPLATE_DIR` zelf over.

Toon de gevonden mappen als genummerde lijst:

```
Gevonden projecten:
1. /Users/naam/werk/project-a
2. /Users/naam/werk/project-b
...
```

Vraag: "Kloppen deze projecten? Geef kommagescheiden nummers op om te verwijderen (bijv. `3,7`), of druk Enter om alles te accepteren."

Verwijder de aangegeven nummers uit de lijst.

### 2.3 projects.txt schrijven

Schrijf de bevestigde lijst naar `TEMPLATE_DIR/projects.txt` (één absoluut pad per regel, geen lege regels).
Meld: "✅ projects.txt bijgewerkt met N projecten"

---

## Stap 3 — Notion-config

### 3.1 Bestaande config checken

Controleer of `~/.claude/notion.md` bestaat.

- **Bestaat niet:** Ga naar Stap 3.2 (wizard)
- **Bestaat al:** Ga naar Stap 3.3 (review)

### 3.2 Notion-wizard (eerste keer)

Vraag: "Gebruik je Notion voor projectbeheer? (ja/nee)"

Bij **"nee":** Meld "Notion-config overgeslagen. Je kunt dit later instellen door `/setup-machine` opnieuw te draaien." Ga naar Stap 4.

Bij **"ja":** Vraag: "Hoeveel Notion workspaces wil je configureren? (bijv. 1 of 2)"

Herhaal voor elke workspace:

1. Vraag: "Naam van workspace [N]? (bijv. `mijnbedrijf` — geen spaties, lowercase)"
2. Vraag voor elk van de databases de collection ID. Gebruik deze exacte vragen:
   - "Tasks database collection ID voor `[naam]`? (bijv. `collection://xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)"
   - "Projects database collection ID voor `[naam]`?"
   - "ADR database collection ID voor `[naam]`?"
   - "Sessielogboek database collection ID voor `[naam]`?"
   - "Nacht Rapporten database collection ID voor `[naam]`?"

   Niet elke workspace heeft alle databases — laat een database weg als die niet bestaat voor deze workspace. De gebruiker kan dit aangeven met "n/a" of Enter.

   **Tip:** Je vindt de collection ID via Notion → open de database als full page → kopieer de page-link → de UUID in de URL is de database-ID. Schrijf het als `collection://UUID`.

Schrijf het resultaat naar `~/.claude/notion.md`:

```
# Notion Config

## Workspace: [naam]
- tasks: [collection ID]
- projects: [collection ID]
- adr: [collection ID]
- sessielogboek: [collection ID]
- nacht_rapporten: [collection ID]

## Workspace: [naam2]
- tasks: [collection ID]
...
```

Meld: "✅ ~/.claude/notion.md aangemaakt met N workspace(s)"

### 3.3 Notion-config review (al geconfigureerd)

Lees `~/.claude/notion.md` en toon alle workspaces met hun 6 database-IDs.

Voor elke workspace, vraag: "Workspace `[naam]` — klopt deze config nog? (ja / nee / verwijder)"

- **"ja":** geen actie voor deze workspace
- **"verwijder":** verwijder het volledige `## Workspace: [naam]` blok uit de config
- **"nee":** loop door alle 6 databases en vraag per database:
  "Huidige ID voor `[sleutel]`: `[id]` — klopt dit? (Enter = ja, of geef nieuwe collection ID)"
  Vervang bij een nieuw ID de waarde in de config.

Vraag na alle workspaces: "Wil je een nieuwe workspace toevoegen? (ja/nee)"
- Bij "ja": voer de wizard uit voor één nieuwe workspace (zie Stap 3.2, sla de intro-vraag over) en voeg het blok toe aan `~/.claude/notion.md`

Sla de bijgewerkte config op naar `~/.claude/notion.md`.
Meld: "✅ ~/.claude/notion.md bijgewerkt"

---

## Stap 4 — Afsluiting

Toon een samenvatting:

```
✅ Machine-setup voltooid

Gedaan:
- install-template.md : [aangemaakt / TEMPLATE_DIR bijgewerkt / ongewijzigd]
- projects.txt        : [N projecten geregistreerd / ongewijzigd]
- ~/.claude/notion.md : [aangemaakt / bijgewerkt / overgeslagen]

Je kunt nu /install-template gebruiken vanuit elk nieuw project.
Draai /setup-machine opnieuw als je de config wilt aanpassen.
```
