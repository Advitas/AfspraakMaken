# Design: Afspraak wijzigen via pincode-verificatie

**Datum:** 2026-09-03
**Route:** B — kleine feature (feature-route), spec + implementatieplan, inline uitvoering, geen review-agents.
**Repo's:** `AfspraakMaken` (Azure Function, backend) + `AgendaPicker` (Node/Express webapp, frontend + thin proxy).

## Context / doel

Een klant moet zelfstandig, zonder in te loggen, de datum/tijd (en eventueel adviseur/vorm_afspraak) van een
bestaande afspraak kunnen wijzigen. Toegang wordt beveiligd met een eenmalige, kortlevende pincode die per
e-mail wordt verstuurd. Er bestaat nog geen enkele vorm van klant-facing wijzig-flow in beide repo's; dit is
nieuw terrein voor allebei.

## Scope

**In scope:**
- Nieuw endpoint in AfspraakMaken dat een pincode genereert, tijdelijk opslaat en per e-mail verstuurt.
- Nieuw endpoint in AfspraakMaken dat een pincode verifieert.
- Nieuw endpoint in AfspraakMaken dat de nieuwe datum/tijd/adviseur/vorm_afspraak opslaat (via een nieuwe,
  nog te bouwen stored procedure).
- Nieuwe pagina + twee thin-proxy routes in AgendaPicker die deze drie endpoints ontsluiten voor de klant,
  met hergebruik van de bestaande beschikbaarheids-kalender-flow (zoals `horizontal.html`/`/api/availability`).

**Buiten scope:**
- Het daadwerkelijk bouwen/deployen van de nieuwe stored procedure `spWijzigAfspraakDatumTijd` in SQL Server
  — dat gebeurt buiten deze repo's, door een DBA. Deze feature bouwt tegen een afgesproken contract (zie
  "Openstaande afhankelijkheid" hieronder) en kan het laatste endpoint pas end-to-end testen zodra die SP
  in `SQL_DATABASE_TEST` bestaat.
- Wie/wat de eerste aanroep (`/wijzig-aanvraag`) triggert (bijv. een link in een ander systeem, een
  handmatige actie van planning) — dat is een aanroeper buiten deze twee repo's.
- Opnieuw kunnen opvragen van de huidige (ongewijzigde) datum/tijd van de afspraak — er komt geen read-SP
  bij; alle context die het wijzig-scherm nodig heeft wordt in stap 1 meegegeven en via het pincode-record
  doorgegeven.

## Architectuur / flow

```
1. (interne aanroeper) → POST AfspraakMaken /wijzig-aanvraag
   body: { afspraak_id, email, adviseur_id, duur_kwartieren, vorm_afspraak, postcode?, run }
   - genereert 6-cijferige numerieke pincode
   - upsert in Azure Table Storage: PartitionKey=afspraak_id, 5 min TTL (zelf gecontroleerd,
     geen ingebouwde Table-TTL), attempts=0, plus alle bovenstaande velden
   - verstuurt e-mail (Mandrill, zelfde patroon als _send_reservering_email) naar `email` met
     de pincode en een link:
     https://agendapicker-ahe5g9g6gdh0gcdw.azurewebsites.net/wijzig-afspraak.html?afspraak_id=<id>

2. Klant opent wijzig-afspraak.html?afspraak_id=<id>, vult pincode in
   → POST AgendaPicker /api/wijziging/verifieer-pincode (thin proxy, function-key server-side)
   → POST AfspraakMaken /wijzig-verificatie { afspraak_id, pincode }
   - haalt record op via afspraak_id (PartitionKey), checkt: bestaat, niet verlopen (nu < verlooptijd),
     pincode gelijk, attempts < 5
   - bij mismatch: attempts += 1, foutmelding "Ongeldige pincode." (geen onderscheid maken tussen
     "bestaat niet"/"verlopen"/"fout" in de foutmelding, om geen informatie te lekken)
   - bij 5e mismatch: record wordt verwijderd, foutmelding "Te vaak fout ingevoerd, vraag een nieuwe
     pincode aan."
   - bij match: retourneert { adviseur_id, duur_kwartieren, vorm_afspraak, postcode } uit het record
     (attempts wordt NIET gereset — een geldige pincode-poging telt niet tegen de limiet)

3. wijzig-afspraak.html toont de bestaande beschikbaarheids-kalender (zelfde `/api/availability`-flow
   als horizontal.html), met duur_kwartieren/vorm_afspraak/postcode als vaste filters uit stap 2.
   adviseur_id wordt NIET vastgezet — de klant kan dus (net als in de bestaande kalender) een andere
   adviseur/tijdslot kiezen dan de oorspronkelijke afspraak.

4. Klant kiest datum/tijd (en daarmee impliciet adviseur_id, zoals in de bestaande boekingsflow), klikt
   Opslaan → POST AgendaPicker /api/wijziging/opslaan (thin proxy)
   → POST AfspraakMaken /wijzig-opslaan
     { afspraak_id, pincode, adviseur_id, datum, tijd, duur_kwartieren, vorm_afspraak, run }
   - valideert pincode opnieuw (zelfde regels als stap 2, incl. attempts-teller)
   - roept `spWijzigAfspraakDatumTijd` aan met @afspraak_id, @adviseur_id, @datum, @tijd,
     @duur_kwartieren, @vorm_afspraak (analoog aan _call_sp_maak_afspraak: vaste parameter-mapping,
     géén dynamische matching)
   - bij succes (foutmelding-output leeg): pincode-record wordt verwijderd (one-time use), HTTP 200
   - bij foutmelding uit de SP-output: HTTP 500 met de SP-foutdetails, pincode-record blijft staan
     (klant mag het nog eens proberen binnen de resterende geldigheidsduur)
```

## Componenten

### AfspraakMaken (`function_app.py`)

Drie nieuwe routes, met vaste parameter-mapping (zoals `/afspraak`, niet dynamisch zoals `/reservering`):

- `POST /wijzig-aanvraag`
- `POST /wijzig-verificatie`
- `POST /wijzig-opslaan`

Nieuwe helpers (private, `_`-prefix, zelfde stijl als bestaande code):
- `_genereer_pincode()` — 6-cijferige numerieke pincode (`secrets`-module, niet `random`, want dit is een
  beveiligingsmechanisme).
- `_get_table_client()` — opent een `TableClient` op tabel `WijzigAfspraakPincodes`, connection uit
  `AzureWebJobsStorage` (bestaande env var, geen nieuwe secret).
- `_bewaar_pincode(...)` / `_haal_pincode_record(...)` / `_verwijder_pincode_record(...)` — CRUD op de
  tabel.
- `_valideer_pincode(afspraak_id, pincode)` — gedeelde validatielogica voor stap 2 én stap 4 (zelfde regels,
  niet dupliceren).
- `_build_wijzig_email(...)` / `_send_wijzig_email(...)` — analoog aan `_build_reservering_email`/
  `_send_reservering_email`, maar naar het opgegeven klant-e-mailadres (niet naar planning@advitas.nl), met
  `[TEST]`-prefix/banner bij `run != prod` zoals de bestaande mail.
- `_call_sp_wijzig_afspraak(cursor, data)` — vaste parameter-mapping naar `spWijzigAfspraakDatumTijd`,
  zelfde stijl als `_call_sp_maak_afspraak`.

Nieuwe dependency in `requirements.txt`: `azure-data-tables`.

### AgendaPicker (`server.js` + `public/`)

- Nieuwe pagina `public/wijzig-afspraak.html` + `.css` + `.js` (eigen drietal, volgens het bestaande
  patroon — dit is een expliciete stop-and-ask in AgendaPicker's CLAUDE.md, al voorgelegd en akkoord).
  - Stap A: pincode-invoerveld + knop.
  - Stap B (na succesvolle verificatie): hergebruikt de bestaande kalender/tijdslot-UI-logica (zoals
    `horizontal.js`) tegen `/api/availability`, met duur_kwartieren/vorm_afspraak/postcode vast, en een
    "Opslaan"-knop i.p.v. "Bevestigen".
- Twee nieuwe thin-proxy routes in `server.js`, zelfde stijl als bestaande routes (function-key toevoegen,
  try/catch, JSON error-shape):
  - `POST /api/wijziging/verifieer-pincode` → `AFSPRAAK_MAKEN_URL`-host + `/wijzig-verificatie`
  - `POST /api/wijziging/opslaan` → `AFSPRAAK_MAKEN_URL`-host + `/wijzig-opslaan`
  - Nieuwe env vars naar analogie van `AFSPRAAK_RESERVERING_URL`: bijv. `AFSPRAAK_WIJZIG_VERIFICATIE_URL`,
    `AFSPRAAK_WIJZIG_OPSLAAN_URL` (exacte namen definitief maken in het implementatieplan).

## Data model: pincode-tabel (Azure Table Storage)

Tabel `WijzigAfspraakPincodes`:

| Veld | Type | Omschrijving |
|---|---|---|
| PartitionKey | string | `afspraak_id` |
| RowKey | string | vaste waarde, bijv. `"pincode"` (één actief record per afspraak_id) |
| Pincode | string | 6 cijfers |
| VerlooptOp | datetime (UTC) | aanmaakmoment + 5 minuten |
| Attempts | int | aantal foute pincode-pogingen, start op 0 |
| AdviseurId | string/int | context voor de kalender |
| DuurKwartieren | int | context voor de kalender |
| VormAfspraak | string | `online`/`buitendienst` |
| Postcode | string, optioneel | alleen relevant bij `vorm_afspraak=buitendienst` |
| Run | string | `test`/`prod`, bepaalt db-keuze in stap 4 |

Een nieuwe aanvraag (stap 1) voor dezelfde `afspraak_id` overschrijft (upsert) het bestaande record volledig
— dat is bewust simpel gehouden.

## Openstaande afhankelijkheid: `spWijzigAfspraakDatumTijd`

Bestaat nog niet. Voorgesteld contract (analoog aan `spMaakAfspraak`):

```sql
EXEC [dbo].[spWijzigAfspraakDatumTijd]
    @afspraak_id = ?,
    @adviseur_id = ?,
    @datum = ?,
    @tijd = ?,
    @duur_kwartieren = ?,
    @vorm_afspraak = ?,
    @foutmelding = @foutmelding OUTPUT;
```

Dit contract moet bevestigd worden vóór/tijdens implementatie van `/wijzig-opslaan`. Tot de SP in
`SQL_DATABASE_TEST` bestaat, kan dit ene endpoint niet end-to-end getest worden (wel de validatie- en
pincode-logica ervoor). Dit wordt als openstaand punt in `docs/TODO.md` opgenomen.

## Security

- Pincode: 6 cijfers, `secrets`-module (niet `random`), 5 minuten geldig, max. 5 foute pogingen per
  aanvraag, one-time use (verwijderd na succesvolle opslag).
- Foutmeldingen bij verificatie lekken geen onderscheid tussen "bestaat niet"/"verlopen"/"fout ingevoerd".
- Geen sessie/token-concept — pincode + afspraak_id worden door de klant-browser bij zowel stap 2 als stap 4
  meegestuurd; elk endpoint valideert zelf opnieuw tegen het Table Storage-record (stateless, consistent met
  hoe de rest van AfspraakMaken werkt).
- E-mailadres uit de payload van stap 1 wordt vertrouwd (komt van de interne aanroeper, niet van de klant) —
  geen extra validatie nodig buiten een basic formaatcheck.

## Error handling

Consistent met bestaande conventies (`ValidationError` → 400, `pyodbc.Error` → 500 met
`_extract_db_error_details`, generieke `Exception` → 500 met Nederlandse boodschap + `logging.exception`).
E-mailverzendfouten in stap 1 zijn non-blocking zoals `_try_send_reservering_email` — als de mail faalt,
blijft de pincode wel bruikbaar (al heeft de klant 'm dan niet ontvangen; dit wordt gelogd naar Application
Insights).

## Testing

- Geen testframework in beide repo's (alleen syntax-check in AgendaPicker). Handmatig testen:
  - AfspraakMaken: elke nieuwe route testen tegen `SQL_DATABASE_TEST` via `run`-parameter (voor
    `/wijzig-opslaan`: pas mogelijk zodra de SP bestaat; `/wijzig-aanvraag` en `/wijzig-verificatie` zijn
    onafhankelijk daarvan te testen, want die raken geen SQL).
  - AgendaPicker: lokaal `npm start`, handmatig door `wijzig-afspraak.html` lopen.
- Bewijs vóór "klaar"-claim: curl/Postman-aanroepen tonen tegen `SQL_DATABASE_TEST`/lokale AgendaPicker.

## Open punten (naar `docs/TODO.md`)

1. `spWijzigAfspraakDatumTijd` moet gebouwd worden in SQL Server (buiten deze repo's) volgens het contract
   hierboven, vóór `/wijzig-opslaan` end-to-end getest kan worden.
2. Exacte env var-namen voor de nieuwe AgendaPicker-proxy-routes vaststellen in het implementatieplan.
3. Bevestigen dat `AzureWebJobsStorage` (of een aparte storage-connection-string) beschikbaar is als env var
   in de Function App voor Table Storage-toegang.
