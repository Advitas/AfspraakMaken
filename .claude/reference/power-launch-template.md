# Toegang, rechten & launch — Power Apps Code Apps (Advitas-patroon)

> Launch-gids voor **elke** Power Apps Code App bij Advitas:
> hoe regel je (1) wie de app mag openen, (2) wie daarbinnen wat mag,
> (3) de datalaag & connectoren en (4) de deploy naar de omgeving.
> Dit is de **template** — de wizard **`/power-launch`** kopieert hem naar
> `docs/TOEGANG-EN-RECHTEN.md` in het project en vult de intake-tabellen,
> de bijlage en de launch-checklist via intake-vragen.
>
> Referentie-implementatie: **PropSmart** `docs/TOEGANG-EN-RECHTEN.md`
> (ADR-021 aldaar); het patroon is ook bewezen in **Polisbladmailer** (ADR-006 aldaar).

## 1. Intake-specificatie

Beantwoord deze vragen **vóór de bouw**; de bijlage onderaan is de ingevulde
versie voor deze app. Elke vraag komt terug in de secties 2–4.

### a. App & omgevingen

| Vraag | Antwoord |
|---|---|
| App-naam + doel | <vul in> |
| Omgeving(en) (test/acceptatie/productie) | <vul in — naam + environment-ID per omgeving> |
| Security group per omgeving (of "geen") | <vul in> |

### b. Toegang (laag 1)

| Vraag | Antwoord |
|---|---|
| Welke medewerkers/groepen mogen de app openen? | <vul in> |
| Parent-groep (naam + Object ID) | <vul in> |

### c. Rollen & rechten (laag 2)

| Rol | Bron (Entra-groep / user-lijst) | Leden of groep-ID | Tabs | Actie-gates |
|---|---|---|---|---|
| <vul in> | <vul in> | <vul in> | <vul in> | <vul in> |

### d. Datalaag & connectoren

| Vraag | Antwoord |
|---|---|
| SQL-server + database | <vul in> |
| Welke views/sprocs (of: zie `power.config.json`) | <vul in> |
| Overige connectoren | <vul in> |
| DLP-check gedaan (alle connectoren in Business-groep)? | <vul in> |

### e. Deploy

| Vraag | Antwoord |
|---|---|
| Co-owners (wie mag `pac code push`)? | <vul in> |
| Play-URL | <vul in> |

---

## 2. Toegang & rechten: het patroon

Twee onafhankelijke lagen:

| Laag | Vraag | Mechanisme | Beheer |
|---|---|---|---|
| **1 — Toegang** | Mag deze persoon de app openen? | App + connections gedeeld met één **parent-groep** in Entra | Entra-groepslidmaatschap (portal-inrichting eenmalig) |
| **2 — Rechten** | Wat mag hij/zij binnen de app? | App bepaalt bij het opstarten de **rol** van de gebruiker en mapt die op rechten | Entra-rol-groepen en/of user-ID-lijsten in code |

Beide lagen moeten kloppen: laag 1 zonder laag 2 geeft een nette
"Geen toegang"-melding in de app; laag 2 zonder laag 1 en de gebruiker ziet de
app helemaal niet.

**Waarom niet via `getContext()` of Dataverse-rollen?** Een Code App krijgt via
`getContext().user` alléén identiteit (objectId, UPN, naam) — geen groepen of
claims. Rollen moeten dus bij runtime worden opgehaald. Dat doen we met
**certified connectoren** (Office 365 Users + Groups, delegated, read-only):
geen custom Graph-connector, geen app-registratie.

### Eenmalige inrichting per app

#### Stap 1 — Entra-structuur (Entra admin center)

1. Maak een **parent-groep** voor de app (bv. "App <naam> gebruikers").
   Dit is de toegangspoort — iedereen die de app mag openen wordt hier lid van.
2. Bepaal de **rollen** van de app (bv. `gebruiker < supervisor < manager < admin`)
   en kies per rol een **bron**:
   - **Entra-groep** (aanbevolen): rol-wijziging = groepslid toevoegen/verwijderen,
     géén deploy. Maak per rol een groep en noteer het Object ID.
   - **User-ID-lijst in code**: vaste lijst persoons-objectId's in de identity-module.
     Rol-wijziging = code-wijziging + deploy. Acceptabel voor kleine, stabiele
     rollen (PropSmart koos dit voor owners/managers).

> **Valkuilen bij rol-groepen:** de check leest alleen **directe** leden (geen
> geneste groepen) en max. **999 leden** per groep (geen paging).
> GUID's van groepen en gebruikers zijn **niet geheim** — ze mogen in code/docs.

#### Stap 2 — Laag 1 delen (make.powerapps.com, juiste omgeving)

1. *Apps* → de app → **Share** → deel met de **parent-groep** (rol: User).
2. Deel óók elke **connection** die de app gebruikt met die groep:
   - SQL-connection (sqlAuthentication): *Connections* → connection → *Share* → Can use.
   - Office 365 Users/Groups zijn **delegated**: niet te delen; elke gebruiker
     krijgt bij de eerste keer openen een eenmalige consent-prompt. Dat is normaal.
3. Check het **DLP-beleid** van de omgeving: `shared_office365users`,
   `shared_office365groups` en `shared_sql` moeten in dezelfde groep (Business)
   toegestaan zijn.

> **Toegang ≠ deploy-recht.** De app kunnen openen is iets anders dan kunnen
> deployen: `pac code push` vereist **co-ownership** op de Code App (zie sectie 4).

#### Voorwaarde vóór alles: de omgevings-security-group

Een Power Platform-**omgeving** kan zelf een security group hebben; wie daar geen
lid van is kan géén enkele app in de omgeving openen ("You are not a member of
the environment's security group") — dit zit nog vóór laag 1.

1. **Welke groep?** [admin.powerplatform.microsoft.com](https://admin.powerplatform.microsoft.com)
   → *Environments* → klik de omgeving → veld **Security group** (via *Edit*).
   Geen security group ingesteld = hele tenant heeft omgevings-toegang.
2. **Lid toevoegen:** [entra.microsoft.com](https://entra.microsoft.com) → *Groups*
   → die groep → *Members* → *Add members*. **Direct lid** — nesting telt niet.

> Krijgt iemand deze melding terwijl anderen de app wél kunnen openen: check
> eerst of hij de **juiste app-URL** gebruikt — het `e/<guid>`-deel van de
> play-URL is de omgeving, en een link naar een andere omgeving geeft exact
> deze melding.

#### Stap 3 — Identiteits-connectoren in de codebase (pac)

Voeg de twee certified connectoren toe als datasource (connection-ID's vind je
met `pac connection list`):

```bash
pac code add-data-source -a shared_office365users  -c <office365users-conn-id>
pac code add-data-source -a shared_office365groups -c <office365groups-conn-id>
```

Dit genereert `Office365UsersService` (met `MyProfile_V2`) en
`Office365GroupsService` (met `ListGroupMembers`) in `src/generated/` —
nooit handmatig bewerken.

#### Stap 4 — Identity-module (code, het list+compare-patroon)

Bouw één identity-module (referentie: PropSmart `src/api/identity.ts`) die bij
het opstarten éénmalig, daarna gecached:

1. het profiel ophaalt: `MyProfile_V2('id,displayName,mail,userPrincipalName')`;
2. per rol-bron bepaalt of de gebruiker matcht:
   - groep: `ListGroupMembers(groupId, 999)` → match op `member.id === profile.id`
     (fallback UPN, case-insensitief) — **list+compare**, want geen enkele
     certified connector kan `/me/checkMemberGroups` aanroepen;
   - user-lijst: `memberIds.includes(profile.id)` (case-insensitief);
3. de **hoogste** gematchte rol kiest en die via een **pure kern**
   (referentie: PropSmart `src/lib/autorisatie.ts`: `ROL_RANG`, `hoogsteRol`,
   `rechtenVoorRol`) naar tab-/actierechten vertaalt — pure functies, unit-testbaar;
4. bij géén match een duidelijke 403-melding toont.

Schrijf bij writes de **Entra-identiteit** (objectId + email + naam) als
audit-velden mee — geen eigen SQL-gebruikerstabel als bron van waarheid.

#### Stap 5 — Lokale dev-stub

Lokaal is er geen Entra-context. Mock identiteit + rol via env-vars
(patroon: `LOCAL_USER_ROLE` voor de Express-backend, `VITE_DEV_ROLE`/`VITE_DEV_EMAIL`/
`VITE_DEV_NAAM`/`VITE_DEV_OBJECT_ID` voor Vite dev — zie de variabelen-tabel in
sectie 4) en laat de stub **dezelfde pure kern** gebruiken als de Power-modus —
zo test je elke rol lokaal met één env-var.

### Dagelijks beheer (per app)

| Wat | Hoe | Deploy nodig? |
|---|---|---|
| Nieuwe gebruiker toegang geven | Lid maken van de **parent-groep** (Entra) | Nee |
| Rol toekennen (groep-gebaseerde rol) | Lid maken van de **rol-groep** (direct lid!) | Nee |
| Rol toekennen (lijst-gebaseerde rol) | Object ID opzoeken (Entra → Users → *Object ID*) → toevoegen aan de lijst in de identity-module | **Ja** (`build:power` → `pac code push`) |
| Rechten van een rol wijzigen | Tab-mapping in de pure kern aanpassen (+ tests) | **Ja** |
| Gebruiker verwijderen | Uit parent-groep + rol-bron halen | Alleen bij lijst-rol |

Na elke rol-wijziging moet de gebruiker de app **opnieuw openen** — de rol wordt
per sessie éénmalig bepaald en gecached.

---

## 3. Datalaag & connectoren

De datalaag van een Code App bestaat uit **connections** (in de omgeving) en
**datasources** (in de codebase, gegenereerd door `pac code add-data-source`).

- **Connection-ID's vinden:** `pac connection list` (in de juiste omgeving).
  Het laatste pad-segment van `sharedConnectionId` in `power.config.json` is de
  connection-ID die pac verwacht.
- **Datasource toevoegen — views/tabellen** (alleen `-t`):

  ```bash
  pac code add-data-source -a shared_sql -c <connection-id> -t "[schema].[vw_Naam]"
  ```

- **Datasource toevoegen — stored procedures:** vereist `-t` én `-sp` met
  **dezelfde waarde**, en non-interactief óók `-c`:

  ```bash
  pac code add-data-source -a shared_sql -c <connection-id> -t "[schema].[usp_Naam]" -sp "[schema].[usp_Naam]"
  ```

- **Identiteits-connectoren** (`shared_office365users`, `shared_office365groups`):
  zie sectie 2, stap 3.
- Een **libuv-assertion** aan het einde van pac-output is cosmetisch — beoordeel
  het resultaat op de gegenereerde bestanden.

**Anatomie van `power.config.json`:**

| Veld | Betekenis |
|---|---|
| `appId` | ID van de Code App in de omgeving |
| `environmentId` | de omgeving waar `pac code push` naartoe publiceert |
| `buildPath` | de map die gepusht wordt (`./dist`) |
| `connectionReferences` | per connector: `sharedConnectionId` + de lijst `dataSources` |
| `dataSets` | mapping datasource → `[schema].[objectnaam]` in de database |

**`src/generated/` + `.power/` zijn autogegenereerd** — nooit handmatig
bewerken, wél committen: samen met `power.config.json` zijn ze de app-definitie.

**Dual-mode datalaag** (voor projecten met een lokaal Express-prototype):
één build-time vlag `VITE_DATA_BACKEND` (leeg = Express, `power` = Power
Platform SDK) kiest de implementatie achter één gedeelde `Api`-interface.
Reshape-helpers geven sproc-responses exact dezelfde payload als de
Express-route, zodat schermen geen verschil merken. Referentie: PropSmart
`src/api/client.ts`, `src/api/powerClient.ts`, `src/lib/powerReshape.ts`.

---

## 4. Deploy & variabelen

- **Eenmalig per machine/omgeving:** `pac auth create --environment <environment-id>`;
  wissel met `pac auth list` / `pac auth select`. Deployen vereist
  **co-ownership** op de Code App — regel dit voor iedereen die pusht.
- **Vaste werkwijze bij elke deploy:**

  ```bash
  npm run build:power   # power-mode build (--mode power → laadt .env.power)
  pac code push         # publiceert ./dist naar de omgeving uit power.config.json
  ```

  **Nooit** de gewone `npm run build` pushen — die bouwt Express-modus en de app
  zoekt dan `/api/*`, wat in Power Platform niet bestaat.
- **Promotie naar acceptatie/productie** is een aparte stap: Dataverse-solution
  + pipeline, `pac code push --solutionName <naam>` — afstemmen met de
  omgeving-beheerder.

**Variabelen** (namen + doel; waarden horen alléén in de lokale
`.env`-bestanden, nooit in code of docs):

| Variabele | Bestand | Doel |
|---|---|---|
| `SQL_SERVER`, `SQL_DATABASE`, `SQL_USER`, `SQL_PASSWORD`, `SQL_ENCRYPT` | `.env` | Express-backend → SQL (encrypt `true` voor Azure SQL) |
| `LOCAL_USER_EMAIL` | `.env` | identiteit van de dev-stub (lokale auth-laag) |
| `LOCAL_USER_ROLE` (default `admin`), `LOCAL_USER_NAAM`, `LOCAL_USER_OBJECT_ID` | `.env` | rol + identiteit van de Express-dev-stub |
| `VITE_DATA_BACKEND` | `.env.power` | leeg = Express, `power` = Power Platform SDK (build-time) |
| `VITE_DEV_ROLE`, `VITE_DEV_EMAIL`, `VITE_DEV_NAAM`, `VITE_DEV_OBJECT_ID` | `.env.power` / Vite-dev | mock-identiteit in power-dev-modus |
| `VITE_GROUP_<ROL>` | `.env` / `.env.power` | override van een rol-groep-Object-ID (bv. `VITE_GROUP_SUPERVISOR`) |

**`vite.config.ts` → `base: './'` is verplicht** voor Code App-hosting: de
usercontent-CDN serveert vanaf een sub-pad; absolute `/assets/`-paden komen
terug als `application/json` (CSS/JS-MIME-fout).

**Verificatie-checklist na elke deploy:**

- [ ] Harde refresh op de play-URL (Ctrl+F5)
- [ ] Per rol inloggen: juiste tabs zichtbaar, actie-gates kloppen
- [ ] Niet-lid krijgt de nette 403-/"Geen toegang"-melding
- [ ] Eerste keer per gebruiker: Office 365-consent-prompt accepteren (eenmalig, normaal)
- [ ] Eén write-actie doen → audit-velden (objectId/email/naam) gevuld in de database

---

## 5. Problemen oplossen

| Symptoom | Oorzaak | Oplossing |
|---|---|---|
| "You are not a member of the environment's security group" | Verkeerde app-URL: de link wijst naar een **andere omgeving** (bv. productie) met een eigen security group | De juiste play-URL van de app delen — het `e/<guid>`-deel in de URL is de omgeving. Alléén als de URL wél klopt: persoon (direct) lid maken van de security group van de omgeving (Power Platform admin center → Environments → *Security group*) |
| App niet zichtbaar / opent niet | Laag 1 ontbreekt | Persoon in de parent-groep zetten |
| "Geen toegang"-melding ín de app | Laag 2 ontbreekt | Rol-groep (Entra) of user-lijst (code + deploy) |
| Consent-prompt Office 365 bij openen | Eerste keer | Accepteren — eenmalig per gebruiker |
| Rol-wijziging niet zichtbaar | Sessie-cache | App sluiten en opnieuw openen (evt. Ctrl+F5) |
| Lid van rol-groep maar geen rol | Genest lidmaatschap | Persoon **direct** lid maken van de rol-groep |
| Grote groep: sommige leden geen rol | >999 leden, geen paging | Groep splitsen of custom connector overwegen |
| Datafouten/403 op SQL | Connection niet gedeeld | SQL-connection delen met de parent-groep |
| `pac code push` → 403 PowerAppsNoAccess | Geen co-owner | Co-ownership regelen op de Code App |
| CSS/JS laadt niet, MIME-fout `application/json` | `base: './'` ontbreekt in `vite.config.ts` | `base: './'` zetten en opnieuw builden + pushen |
| App zoekt `/api/*` en toont geen data | Verkeerde build-modus gepusht (`npm run build` i.p.v. `build:power`) | `npm run build:power` → `pac code push` |
| Datasource ontbreekt in de app na push | `pac code add-data-source` niet gedraaid of `power.config.json`/`src/generated/` niet gecommit | Datasource toevoegen (sectie 3) en opnieuw pushen |
| libuv-assertion na een pac-commando | Cosmetische fout in pac zelf | Negeren — beoordeel op de gegenereerde bestanden |

---

## Bijlage — invulling <app>

> Wordt ingevuld door `/power-launch`. Onbekende antwoorden blijven `<vul in>`
> staan en komen terug in het open-punten-overzicht van de wizard.

### a. App & omgevingen

| Vraag | Antwoord |
|---|---|
| App-naam + doel | <vul in> |
| Omgeving(en) | <vul in — naam + environment-ID; app-ID zodra `power.config.json` bestaat> |
| Security group per omgeving | <vul in> |

### b. Toegang (laag 1)

| Vraag | Antwoord |
|---|---|
| Wie mogen de app openen? | <vul in> |
| Parent-groep | <vul in — naam + Object ID> |

### c. Rollen & rechten (laag 2)

| Rol | Bron | Leden / groep-ID | Tabs | Actie-gates |
|---|---|---|---|---|
| <vul in> | <vul in> | <vul in> | <vul in> | <vul in> |

### d. Datalaag & connectoren

| Vraag | Antwoord |
|---|---|
| SQL-server + database | <vul in> |
| Views/sprocs | <vul in — of: zie `power.config.json`> |
| Overige connectoren | <vul in> |
| DLP-check | <vul in> |

### e. Deploy

| Vraag | Antwoord |
|---|---|
| Co-owners | <vul in> |
| Play-URL | <vul in> |

### Verwijzingen

- **Code-plekken:** identity-module `src/api/identity.ts` · pure autorisatie-kern
  `src/lib/autorisatie.ts` · dev-stub (Express: `server/auth.ts` of equivalent).
- **Deploy:** altijd `npm run build:power` vóór `pac code push` (nooit de gewone build).

---

## Launch-checklist

Portal-stappen (handmatig, in volgorde):

- [ ] Entra: parent-groep aangemaakt (Object ID genoteerd in de bijlage)
- [ ] Entra: rol-groepen aangemaakt (indien groep-gebaseerde rollen)
- [ ] Power Platform admin center: security group van de omgeving gecheckt; alle gebruikers (direct) lid
- [ ] make.powerapps.com: app gedeeld met de parent-groep (rol: User)
- [ ] make.powerapps.com: SQL-connection gedeeld met de parent-groep (Can use)
- [ ] DLP-beleid gecheckt: alle gebruikte connectoren in dezelfde (Business-)groep
- [ ] Co-ownership op de Code App geregeld voor iedereen die deployt

Code-stappen (per stap uitvoerbaar met Claude):

- [ ] `pac auth create --environment <environment-id>`
- [ ] `pac code add-data-source` voor elke view/sproc (sectie 3)
- [ ] Identity-module + pure autorisatie-kern gebouwd (sectie 2, stap 4)
- [ ] Lokale dev-stub met env-vars (sectie 2, stap 5)
- [ ] `npm run build:power` → `pac code push`
- [ ] Verificatie-checklist na deploy doorlopen (sectie 4)
