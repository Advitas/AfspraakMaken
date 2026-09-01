---
description: Initialiseer een nieuw project — stel vragen en vul alle templates in
---

Voer de volgende stappen uit om een nieuw project te initialiseren. Vraag de informatie interactief uit en schrijf daarna alle bestanden weg.

## Stap 1 — Projectinformatie uitvragen

Stel de volgende vragen één voor één. Wacht op het antwoord voordat je verdergaat.

1. **Projectnaam:** Wat is de naam van dit project?
2. **Beschrijving:** Beschrijf het project in 1-2 zinnen. Wat doet het, voor wie?
3. **Tech stack:**
   - Frontend (bijv. React, Razor Pages, Vue, geen)
   - Backend (bijv. ASP.NET Core, Node/Express, Django, Laravel)
   - Database (bijv. SQL Server, PostgreSQL, MySQL, geen)
   - Hosting (bijv. VPS, Azure, Vercel, lokaal)
   - Overige services (bijv. e-mail API, error tracking, authenticatie)
4. **Build command:** Welk commando bouwt het project? (bijv. `dotnet build`, `npm run build`, `cargo build`)
5. **Run command:** Welk commando start de lokale server? (bijv. `dotnet run`, `npm run dev`)
6. **Taal:** Voertaal voor code? Voor docs/commits/UI? (bijv. code in Engels, docs in Nederlands)
7. **Kritieke regels:** Zijn er nu al harde constraints bekend? (bijv. "secrets nooit in code", "geen directe DB-toegang in controllers"). Mogen ook "geen" zijn.
8. **Superpowers:** Gebruik je de Superpowers plugin? (ja/nee) — dit bepaalt of de sessie-instructies daarnaar verwijzen.
9. **Key people:** Wie zijn de kernpersonen? (naam + rol, bijv. "Jan — lead developer, Lisa — designer")
10. **Project status:** Wat is de huidige fase? (bijv. "greenfield", "MVP", "maintenance mode")
11. **GitHub repository:** Is er al een GitHub-repo voor dit project? Geef de URL op, zeg "aanmaken" als je die nu wilt aanmaken, of "later" om dit over te slaan.
12. **Notion Coding Project:** Is dit een codeproject? (ja/nee)

## Stap 2 — Templates vullen

Na het uitvragen, schrijf de volgende bestanden weg met de verzamelde informatie:

### `CLAUDE.md`
Schrijf volledig opnieuw. Gebruik de antwoorden om alle `[placeholders]` in te vullen. Laat secties voor kritieke regels leeg of vul ze in met wat is opgegeven. Neem bij Superpowers-gebruik (vraag 8 = ja) in de Superpowers-sectie de feature-route-regel op: bij elk feature-verzoek éérst de `feature-route` skill volgen (routevraag A/B/C). Zie de CLAUDE.md van deze template-repo voor het exacte format.

### `docs/HANDOFF.md`
Schrijf de initiële handoff: datum van vandaag, project status uit stap 10, "Dit is de eerste sessie — nog geen werkende staat." Laat open items leeg.

### `docs/TODO.md`
Schrijf de initiële TODO: één item onder Next Up: "Stel architectuurkeuzes vast en vul docs/ARCHITECTURE.md in."

### `docs/DECISIONS.md`
Schrijf de header + instructie, nog geen ADR's.

### `docs/ARCHITECTURE.md`
Schrijf de sectiekoppen in, laat secties leeg.

### `docs/CONVENTIONS.md`
Schrijf de sectiekoppen in, laat secties leeg.

### `docs/GLOSSARY.md`
Schrijf de tabelheader in, laat tabel leeg.

### `.claude/settings.local.json`
Schrijf het build command en run command in als toegestane commando's.

## Stap 2.5 — Notion Coding Project

Handel vraag 12 af afhankelijk van het antwoord:

**"nee":** Sla deze stap over.

**"ja":** Maak een coding project aan in de actieve workspace:

**Notion-config lezen:**
1. Controleer of `~/.claude/notion.md` bestaat → nee: sla alle Notion-stappen over
2. Lees `~/.claude/notion.md`; bestaat `.claude/notion.md` ook in het huidige project? → lees dat ook; project-level waarden overschrijven globale waarden per database-sleutel
3. Lees het `Notion Workspace:` veld uit `CLAUDE.md` (onder Quick Facts) → dit is de actieve workspace-naam
   → Geen `Notion Workspace:` veld: sla Notion-stappen over
4. Zoek onder `## Workspace: <naam>` de benodigde collection-IDs op (Projecten data source, Coding area, Coding template ID, Sessielogboek data source)

1. Maak een pagina in de Projecten database van de workspace via `notion-create-pages`, met de Coding template content (secties: Context, Tech Stack, Architectuur, Setup & Deployment, Sessielogboek, Beslissingen):
   - `Project Naam`: `[projectnaam]` (of `[hoofdproject] Coding` als het een zijtak is)
   - `Project Type`: `Coding`
   - `Project status`: `On track`
   - `View`: de actieve workspace-naam
   - `Areas`: koppel aan de Coding area van die workspace
2. Werk de content bij met projectspecifieke info (stack, repo, commando's) via `notion-update-page`.
3. Voeg de URL van de aangemaakte pagina toe aan `CLAUDE.md` onder Quick Facts als `Notion Coding Project`.

## Stap 2.6 — Git & GitHub

Handel vraag 11 af afhankelijk van het antwoord:

**"later":** Sla deze stap over. Vermeld in de bevestiging dat de repo nog aangemaakt moet worden.

**URL opgegeven of "aanmaken":** Vraag eerst naar de SSH-alias:

> Lees `~/.ssh/config` en zoek alle `Host`-entries waarvan `HostName github.com` is. Toon de gevonden aliassen en vraag: "Welke SSH-alias moet ik gebruiken voor deze repo? (of 'geen' als je de standaard `github.com` wilt gebruiken)"

Vervang vervolgens `github.com` in de remote URL met de gekozen alias. Bijvoorbeeld: `git@github.com:user/repo.git` → `git@MijnAlias:user/repo.git`.

**URL opgegeven (repo bestaat al):** Noteer de (aangepaste) URL in `CLAUDE.md` onder Quick Facts. Voer geen git-commando's uit tenzij er nog geen `.git`-map is.

**"aanmaken":** Vraag bevestiging voor elke actie en voer daarna stap voor stap uit:
1. Genereer `.gitignore` op basis van de gekozen stack (Node, Python, .env, OS-bestanden)
2. `git init && git branch -m main`
3. `git add CLAUDE.md docs/ .claude/ .gitignore`
4. Laat de commit message zien en vraag bevestiging: `git commit -m "project initialisatie"`
5. Vraag of de repo-naam klopt, dan: `gh repo create [projectnaam] --private --source=. --remote=origin --push`

## Stap 3 — Bevestiging

Toon een samenvatting van wat er aangemaakt is en welke bestanden nog handmatig aangevuld moeten worden. Geef daarna het advies: "Gebruik `/start-session` om elke volgende sessie te starten."
