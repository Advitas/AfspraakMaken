---
description: Pas de project-template toe op een bestaand project — detecteer de stack, stel vragen en vul alle docs-bestanden in met echte content.
---

Voer de volgende stappen uit om de template toe te passen op dit bestaande project. Het project heeft al code — gebruik die als primaire informatiebron en vul aan met gerichte vragen.

## Stap 0 — Bestaande bestanden controleren

Controleer of `CLAUDE.md` en/of de map `docs/` al bestaan.

- Als ze **niet bestaan**: ga direct door naar stap 1.
- Als ze **wel bestaan**: meld wat je aantreft (welke bestanden, kort wat erin staat) en vraag:

  > "Ik zie dat er al een `CLAUDE.md` en/of `docs/`-bestanden zijn. Wat wil je dat ik doe?
  > - **Overschrijven** — ik vervang alles met de ingevulde template
  > - **Samenvoegen** — ik voeg de template-structuur toe en bewaar bestaande content waar dat kan
  > - **Stoppen** — ik doe niets"

  Wacht op het antwoord voordat je verdergaat.

## Stap 1 — Codebase scannen

Lees de volgende bestanden en mappen als ze bestaan, zonder ze te rapporteren aan de gebruiker — gebruik ze puur als context:

- `package.json` / `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml`
- `Cargo.toml` / `pyproject.toml` / `*.csproj` / `build.gradle` / `pom.xml` / `composer.json`
- `Dockerfile` / `docker-compose.yml` / `.github/workflows/*.yml`
- `*.env.example` / `.env.example`
- `README.md` (als die bestaat)
- De root-mappenstructuur (één niveau diep)
- `src/` of `app/`-mappenstructuur (één niveau diep)
- Eventuele CI-configuratiebestanden

Leid hier zo veel mogelijk uit af:
- **Stack** (frontend, backend, database, hosting)
- **Build command** en **run command**
- **Externe services** (betalingen, e-mail, monitoring, auth)
- **Projectnaam**
- **Taal** van de code (variabelenamen, comments)
- **Testframework**
- **Code-patronen** (mapstructuur, naamgeving)
- **Entiteiten in het domein** (op basis van bestandsnamen, modellen, routes)

## Stap 2 — Gerichte vragen stellen

Stel alleen vragen over wat je **niet** uit de code kon afleiden. Presenteer voor elk punt eerst je eigen voorstel (op basis van de scan) en vraag om bevestiging of correctie. Bundel vragen per thema in één bericht — stel ze niet één voor één tenzij het antwoord de volgende vraag bepaalt.

Vragen die altijd gesteld worden, ook als je een voorstel hebt:

1. **Beschrijving:** Wat doet dit project, voor wie? (1-2 zinnen)
2. **Project status:** Greenfield, MVP, of maintenance mode?
3. **Productie-URL:** Is het al deployed? Zo ja, op welk adres?
4. **Key people:** Wie zijn de kernpersonen? (naam + rol)
5. **Voertaal docs/commits/UI:** Code-taal heb je waarschijnlijk al — maar wat is de taal voor documentatie, commit messages en de UI?
6. **Kritieke projectregels:** Zijn er harde constraints die Claude moet kennen? (bijv. "geen directe DB-queries buiten de repository-laag")
7. **Domein-termen:** Zijn er termen die specifiek zijn voor dit project die een buitenstaander niet zou begrijpen? (bijv. interne naam voor een entiteit of proces)

Stel ook situationele vragen als je die niet kon afleiden:
- Hosting / deployment-aanpak (als niet af te leiden uit CI of Dockerfile)
- Authenticatie-aanpak (als niet af te leiden uit dependencies)
- Database-schema of hoofdentiteiten (als niet af te leiden uit modellen)
- Teststrategie (als geen testframework gevonden)

## Stap 3 — Alle bestanden schrijven

Na het verzamelen van alle informatie, schrijf de volgende bestanden weg. Gebruik **altijd echte content** — geen lege placeholders laten staan als je de informatie hebt. Vul secties die je niet kunt invullen in met een expliciete `<!-- onbekend — vul aan -->` comment.

### `CLAUDE.md`

Schrijf volledig opnieuw op basis van de template. Regels:

- Alle `[placeholders]` invullen met verzamelde informatie
- **Superpowers-sectie altijd opnemen** — inclusief de feature-route-regel: bij elk feature-verzoek éérst de `feature-route` skill volgen (routevraag A/B/C). Zie de CLAUDE.md van deze template-repo voor het exacte format.
- Project Status Regels: neem alleen de sectie op die past bij de status (greenfield/MVP of maintenance mode)
- Kritieke regels: voeg de secrets-sectie altijd op, voeg projectspecifieke regels toe op basis van wat opgegeven is
- Build command en run command: gebruik wat gedetecteerd of opgegeven is
- **File Update Discipline tabel** moet de DOC-SIGNALS-rij en de waarheid-docs-cluster-rij bevatten. Zie de CLAUDE.md van deze template-repo voor het exacte format.

### `docs/HANDOFF.md`

Schrijf de initiële handoff op basis van de huidige staat van het project:

- Datum van vandaag
- Huidige branch (`git branch --show-current`)
- Laatste commit (`git log -1 --oneline`)
- Build-status: vermeld het build command, schrijf "niet gecontroleerd in deze sessie — voer zelf uit"
- Wat er in deze sessie is gebeurd: "Template toegepast op bestaand project. Alle docs-bestanden zijn aangemaakt en gevuld op basis van codebase-scan en projectinformatie."
- Open items: top 3 meest voor de hand liggende volgende stappen op basis van de huidige staat

### `docs/TODO.md`

Schrijf een initiële TODO met ten minste:

- [ ] Controleer en vul aan: `docs/ARCHITECTURE.md` — vooral de secties die onbekend bleven
- [ ] Controleer en vul aan: `docs/CONVENTIONS.md` — voeg patronen toe die nog ontbreken
- [ ] Voer een bouwcheck uit: `[build command]`

Voeg toe wat logisch volgt uit de projectstatus (bijv. "schrijf eerste tests" als er geen testfiles zijn).

### `docs/DECISIONS.md`

Schrijf de header + format-instructie. Voeg één ADR toe voor de meest significante architecturale keuze die je uit de codebase kon afleiden (bijv. framework-keuze, database-keuze). Als je niets kunt afleiden, laat de sectie leeg met een comment.

### `docs/ARCHITECTURE.md`

Schrijf alle secties in met echte content op basis van de scan:

- **Systeem-overzicht:** wie zijn de gebruikers, welke systemen communiceren
- **Tech Stack tabel:** vul in wat je weet, markeer onbekende rijen met `onbekend`
- **Data Model:** beschrijf de hoofdentiteiten die je kon afleiden uit modellen, routes, of bestandsnamen
- **Request Flows:** beschrijf de meest voor de hand liggende flow (bijv. authenticatie of de primaire use case)
- **Deployment:** vul in op basis van Dockerfile / CI / hostingkeuze
- **Externe Afhankelijkheden tabel:** vul in op basis van dependencies en env-variabelen

### `docs/CONVENTIONS.md`

Schrijf secties in met patronen die je uit de codebase kon afleiden:

- **Naamgeving:** wat zie je aan naamgeving van bestanden, klassen, functies?
- **Projectstructuur:** beschrijf de mappenstructuur zoals je die aantrof
- **Patronen die we gebruiken:** wat zie je aan architectuurpatronen?
- **Patronen die we NIET gebruiken:** laat leeg met comment als onbekend
- **Error Handling:** wat zie je in de code?
- **Database & Migraties:** vul in als relevant
- **Testing:** wat zie je aan testbestanden en testpatronen?
- **Stijlgids:** wat zie je aan linting-config, formattering?

### `docs/GLOSSARY.md`

Schrijf de tabelheader in. Voeg rijen toe voor domein-termen die opgegeven zijn of die je uit de codebase hebt afgeleid (entiteitsnamen, interne termen). Laat de code-referentie zo concreet mogelijk (bijv. `src/models/Order.ts`).

### `docs/DOC-SIGNALS.md`

Schrijf de file met **alleen de header en format-uitleg** (geen retroactieve signal-vulling — projecten beginnen met een lege buffer):

````
# Doc-drift signals — buffer voor /dag-afsluiting

Append-only door `/handoff`. Geleegd door `/dag-afsluiting` in dezelfde commit als de doc-updates.

**Doel:** captures van wijzigingen die één van de "waarheid-docs" raken (`CONVENTIONS`, `ARCHITECTURE`, `GLOSSARY`, `README`, `CONTRIBUTING`). `/handoff` voegt entries toe; `/dag-afsluiting` verwerkt en leegt.

**Format per entry:**

```
## YYYY-MM-DD — sessie N — TARGET-DOC

**Wat:** [korte beschrijving van de wijziging]
**Code:** [betrokken bestanden, paden t.o.v. repo-root]
**Commit:** [commit-hash van de relevante commit]
**Voorgestelde plek:** [hint voor /dag-afsluiting — welke sectie in de waarheid-doc]
```

---

<!-- Entries hieronder. Verwijder deze regel bij de eerste echte entry. -->
````

### `.claude/settings.local.json`

Als dit bestand nog niet bestaat: schrijf het aan met het build command en run command als toegestane commando's.
Als het al bestaat: lees het, en voeg de commando's toe als ze er nog niet in staan. Overschrijf bestaande permissies niet.

### `.gitignore` — `.claude/` regels

Zorg dat de volgende granulaire regels aanwezig zijn in `.gitignore`. Doel: lokale/machine-specifieke bestanden uitsluiten, maar commands en skills wél committen (zodat remote routines er toegang toe hebben).

Te blokkeren:
```
# AI — lokale bestanden niet committen, commands en skills wel
.claude/settings.local.json
.claude/.template-source
.claude/.DS_Store
.claude/worktrees/
```

Werkwijze:
- Als `.gitignore` niet bestaat: maak het aan met alleen dit blok.
- Als `.gitignore` bestaat én een blanket `.claude/` of `.claude` regel bevat: vervang die regel door het blok hierboven.
- Als `.gitignore` bestaat maar geen `.claude`-regel heeft: voeg het blok toe aan het einde.
- Als de granulaire regels al aanwezig zijn: niets doen.

## Stap 3.5 — Notion Coding Project

Vraag: Is dit een codeproject dat bijgehouden moet worden in Notion? (ja/nee)

**"nee":** Sla deze stap over.

**"ja":**
- Controleer of `~/.claude/notion.md` bestaat
  - Nee: meld "Draai eerst `/setup-machine` vanuit de template-repo om Notion in te stellen." → sla de rest van Stap 3.5 over
  - Ja: lees de beschikbare workspace-namen uit `~/.claude/notion.md` (alle `## Workspace: <naam>` koppen)
- Toon de beschikbare workspaces en vraag: "Welke workspace hoort bij dit project? [toon lijst]"
- Voeg het gekozen antwoord toe aan `CLAUDE.md` onder Quick Facts als:
  `- **Notion Workspace:** <gekozen naam>`

Dan:
1. Maak een pagina aan in de Projecten database via `notion-create-pages` met de Coding template content (Context, Tech Stack, Architectuur, Setup & Deployment, Sessielogboek, Beslissingen)
2. Werk de content bij met projectspecifieke info (stack, repo, commando's)
3. Voeg de URL toe aan `CLAUDE.md` onder Quick Facts als `Notion Coding Project`

**Notion-config lezen voor Stap 3.5:**
- Lees `~/.claude/notion.md`
- Zoek onder `## Workspace: <gekozen naam>`:
  - `projects:` → gebruik als parent data source voor het aanmaken van de Coding Project pagina
  - `sessielogboek:` → gebruik als parent data source voor sessielogboek-entries

> **Let op:** De Coding area URL en Coding template ID zijn workspace-specifiek en staan niet in `~/.claude/notion.md`. Vraag deze eenmalig op als ze niet beschikbaar zijn, of sla het automatisch aanmaken van de Notion-pagina over en doe dit handmatig.

## Stap 4 — Bevestiging

Toon een overzicht:

- Welke bestanden zijn aangemaakt of bijgewerkt
- Welke secties je *niet* volledig hebt kunnen invullen (en waarom)
- Aanbeveling: "Gebruik `/start-session` om elke volgende sessie te starten."
