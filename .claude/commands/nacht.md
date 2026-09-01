---
description: Interactieve wizard voor de autonome nacht-sessie — stelt 6 vragen, detecteert workspace en plant een routine in via /schedule.
---

Voer de volgende stappen uit voor de nacht-sessie wizard.

## Stap 0: Vereistencheck

Lees `CLAUDE.md`. Zoek naar een regel die begint met `**Notion Coding Project:**` of `- **Notion Coding Project:**`.

Als die regel niet bestaat: stop en zeg:
> "Dit project heeft geen Notion Coding Project URL in CLAUDE.md. Voeg die eerst toe (zie /apply-template) voordat je /nacht gebruikt."

## Stap 1: Wizard — 6 vragen

Stel de volgende vragen via AskUserQuestion, één per keer in volgorde.

**Vraag 1 — Modus:**
Vraag: "Welke analysemodus wil je gebruiken?"
Opties:
- `debug` — analyseert op bugs, kleine fixes toegestaan (TODO-comments, type-annotaties)
- `verbeter` — analyseert op verbetermogelijkheden, alleen rapportage
- `rapport` — breed overzicht van de codebase, alleen rapportage

**Vraag 2 — Focus (optioneel):**
Stel via AskUserQuestion:
Vraag: "Welk deel van de codebase analyseren? (leeglaten = alles)"
Vrij tekstveld. Bijv: `backend/auth`, `frontend/components`, `src/models`.
Accepteer ook leeg antwoord — gebruik dan "alle bestanden".

**Vraag 3 — Compact-interval:**
Vraag: "Hoe vaak tussentijds opslaan en context compacten?"
Opties:
- `5` turns — vaker opslaan, kleinere stappen
- `10` turns — standaard
- `15` turns — minder onderbreking, grotere stappen

**Vraag 4 — Werkpace:**
Vraag: "Hoe snel werken?"
Opties:
- `conservatief` — één module tegelijk, grondiger
- `normaal` — twee à drie bestanden per turn
- `snel` — meerdere modules per turn, breder maar minder diep

**Vraag 5 — Opdracht:**
Vraag: "Wat wil je specifiek dat het onderzoekt? (vrije tekst)"
Vrij tekstveld. Bijv: "Kijk of er race conditions zijn in de auth module" of "Zoek naar inconsistenties in de API-responses."

**Vraag 6 — Wanneer:**
Stel via AskUserQuestion:
Vraag: "Wanneer moet de nacht-sessie starten?"
Opties:
- `nu` — direct starten (in de huidige sessie, laptop blijft open)
- `vanavond` — op Anthropic's infra, laptop mag daarna dicht
- `morgen` — op Anthropic's infra, laptop mag daarna dicht

Als de gebruiker `vanavond` of `morgen` kiest, stel direct daarna een vervolgvraag via AskUserQuestion:
- `vanavond`: Vraag: "Om hoe laat vanavond? (bijv. 23:00)"
- `morgen`: Vraag: "Om hoe laat morgen? (bijv. 07:00)"

Stel vervolgens — alleen bij `vanavond` of `morgen` — één extra vraag via AskUserQuestion:

**Vraag 7 — GitHub repo('s):**
Vraag: "Welke GitHub repo(s) moet de remote agent klonen? Geef de naam(en) in `org/repo` formaat, één per optie."
Vrij tekstveld. Bijv: `git-finnit/sally_backend`. Meerdere repos = meerdere opties of komma-gescheiden.
De GitHub connector zorgt automatisch voor authenticatie — geen PAT nodig.

## Stap 2: Workspace detecteren

1. Lees `CLAUDE.md`, haal de `Notion Coding Project` URL op
2. Fetch die pagina via `mcp__dd0ddd29-8fd0-4dca-ac38-81b2c64a8fde__notion-fetch`
3. Lees de `View` property — dit is `finnit` of `greit`
4. Lees ook de `Project Naam` property voor PROJECT_NAAM.
   - Als die property ontbreekt: gebruik de **linktekst** van de `Notion Coding Project` URL in CLAUDE.md
     (bijv. `[Fissabon App](https://...)` → `Fissabon App`)
   - Als ook die ontbreekt: gebruik de waarde na `# Project:` op de eerste regel van CLAUDE.md

Als de View property niet `finnit` of `greit` is: stop en meld:
> "Kan workspace niet detecteren uit de Notion pagina. Controleer de View property op de Notion Coding Project pagina."

## Stap 3: Routine-prompt bouwen

Bouw de volgende prompt op (vervang alle [waarden] met de ingevulde antwoorden):

```
Lees `.claude/skills/nacht-instructies.md` in de root van de repository en volg de instructies daarin volledig.

Parameters voor deze run:
- MODUS: [antwoord vraag 1]
- FOCUS: [antwoord vraag 2, of "alle bestanden" als leeg gelaten]
- COMPACT_INTERVAL: [antwoord vraag 3]
- WERKPACE: [antwoord vraag 4]
- OPDRACHT: [antwoord vraag 5]
- PROJECT_NAAM: [Project Naam uit Notion of CLAUDE.md]
- NOTION_PROJECT_URL: [Notion Coding Project URL uit CLAUDE.md]
- WORKSPACE: [finnit of greit, gedetecteerd in stap 2]
```

## Stap 4: Inplannen

Op basis van antwoord vraag 6:

**Als `nu`:** roep de `nacht-instructies` skill direct aan via de `Skill` tool. Sla scheduling over — de sessie draait nu direct in de huidige context (laptop blijft open).

**Als `vanavond` of `morgen`:** maak een remote routine aan via de `RemoteTrigger` tool (laad eerst via ToolSearch). Gebruik `action: "create"` met de volgende config:

- **Naam:** `Nacht-analyse [PROJECT_NAAM] — [datum van vandaag]`
- **`run_once_at`:** zet het ingevoerde tijdstip (lokale tijd Europe/Amsterdam, CEST = UTC+2) om naar RFC3339 UTC. Check eerst de actuele tijd via `date -u`. Voorbeeld: 00:00 Amsterdam = 22:00 UTC de vorige dag.
- **`environment_id`:** `env_0132Ce5eHX5xyD8ybtEJXMzV`
- **`model`:** `claude-sonnet-4-6`
- **`sources`:** bouw de repo-URL(s) op uit vraag 7 (org/repo formaat):
  - `{"git_repository": {"url": "https://github.com/org/repo"}}`
  - Voeg één entry toe per opgegeven repo
- **`allowed_tools`:** `["Bash", "Read", "Write", "Edit", "Glob", "Grep"]`
- **`events`:** één event met de routine-prompt uit Stap 3 als `message.content`
- Genereer een verse lowercase UUID v4 voor `events[].data.uuid`

Toon na aanmaken de link: `https://claude.ai/code/routines/[routine-id]`

## Stap 5: Bevestiging

Toon aan de gebruiker na succesvolle inplanning:

```
✅ Nacht-sessie ingepland

   Project:  [PROJECT_NAAM]
   Modus:    [MODUS]
   Focus:    [FOCUS of "alles"]
   Opdracht: [OPDRACHT]
   Pace:     [WERKPACE]
   Compact:  elke [COMPACT_INTERVAL] turns
   Tijdstip: [wanneer — bijv. "vanavond 23:00" of "nu (direct gestart)"]

   Repos:    [repo-naam(en) uit vraag 7]
   Routine:  https://claude.ai/code/routines/[id]

   's Ochtends verschijnt het rapport in:
   → Notion: Nacht Rapporten database
   → Lokaal: HANDOFF.md + TODO bijgewerkt
```
