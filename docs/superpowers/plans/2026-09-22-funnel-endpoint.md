# Funnel-endpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Een `POST /api/funnel`-endpoint in AfspraakMaken dat een funnel-inzending vastlegt, de klant en het product aanmaakt, en daarna een reservering maakt — zodat de FunnelKnop van de AgendaPicker werkt.

**Architecture:** Het endpoint roept twee stored procedures achter elkaar aan op dezelfde verbinding: eerst `dbo.spFunnelCreateOrCheck` voor het `klant_id`, dan `dbo.spMaakReservering` met dat id. Daartussen wordt gecommit, zodat een mislukte reservering de vastgelegde inzending niet meesleurt. Beide aanroepen lopen via het bestaande `_call_sp_dynamic`, dat parameters matcht via `sys.parameters`.

**Tech Stack:** Python 3.12, Azure Functions v2 (decorator-stijl), `pyodbc` met ODBC Driver 18, SQL Server. Geen testframework in de repo; de planstappen gebruiken `unittest` uit de standaardbibliotheek.

**Spec:** [docs/superpowers/specs/2026-09-22-funnel-endpoint-design.md](../specs/2026-09-22-funnel-endpoint-design.md)

## Global Constraints

- Alle database-writes lopen uitsluitend via stored procedures. Geen directe `INSERT`/`UPDATE`/`DELETE` (`CLAUDE.md`).
- Het dynamische parameter-matchingmechanisme `_call_sp_dynamic` wordt niet gewijzigd (`CLAUDE.md`).
- `spMaakReservering` en `spMMJOcreateOrcheck` worden niet gewijzigd. De MMJO-flow via `/reservering` blijft ongemoeid.
- Lees nooit `.env`, `local.settings.json` of andere secret-bestanden; hardcode geen credentials.
- Elke wijziging aan een stored-procedure-aanroep wordt getest tegen `SQL_DATABASE_TEST` via `run=test` vóór een productie-deploy (`CLAUDE.md`).
- Nederlands voor commentaar, foutmeldingen en commits.
- Python-commando's draaien met `.venv\Scripts\python.exe` vanuit de repo-root.

## File Structure

| Bestand | Verantwoordelijkheid |
| --- | --- |
| `../AgendaPicker/sql/spFunnelCreateOrCheck.sql` | De stored procedure. Blijft in de AgendaPicker-repo staan, net als `spMaakReservering.sql`, dat ook van daaruit beheerd wordt terwijl AfspraakMaken hem aanroept. |
| `function_app.py` | Twee nieuwe helpers plus de route. Het project is bewust single-file; er komt geen module bij. |
| `tests/test_funnel_payload.py` | Unittests voor de twee helpers. Draait zonder database. |
| `.funcignore` | `tests` uitsluiten van de deploy. |
| `docs/DECISIONS.md` | Nieuwe ADR over de tussentijdse commit en het weglaten van `funnel`/`route` bij de reservering. |

---

### Task 1: `spFunnelCreateOrCheck` parametriseren

De productconfiguratie in de procedure is hardgecodeerd op de MMJO-waarden. Die worden parameters met precies die waarden als default, zodat een aanroeper die niets meegeeft zich onveranderd gedraagt.

**Files:**
- Modify: `C:\Users\rvader\Documents\VS_projects\AgendaPicker\sql\spFunnelCreateOrCheck.sql:24-28` (signatuur) en `:49-53` (configuratieblok)

**Interfaces:**
- Consumes: niets
- Produces: `dbo.spFunnelCreateOrCheck(@funnel NVARCHAR(MAX), @route NVARCHAR(100), @klant_id INT = NULL OUTPUT, @productnaam NVARCHAR(255) = N'meermetjeoverwaarde.nl', @verzekeraar_id INT = 33, @hoofdbranche_id INT = 51, @intermediair_id INT = 602)`

- [ ] **Stap 1: Vervang de signatuur (regels 24-28)**

Van:

```sql
CREATE OR ALTER PROCEDURE dbo.spFunnelCreateOrCheck
(
    @funnel   NVARCHAR(MAX),
    @route    NVARCHAR(100),
    @klant_id INT = NULL OUTPUT
)
```

Naar:

```sql
CREATE OR ALTER PROCEDURE dbo.spFunnelCreateOrCheck
(
    @funnel          NVARCHAR(MAX),
    @route           NVARCHAR(100),
    @klant_id        INT           = NULL OUTPUT,

    -- 2026-09-22: de productconfiguratie stond hardgecodeerd op de MMJO-waarden, waardoor elke
    -- funnel een product kreeg met productnaam 'meermetjeoverwaarde.nl' en verzekeraar 33 - ook
    -- een schade- of hypotheekfunnel die daar niets mee te maken heeft. Nu parameters, met die
    -- waarden als default zodat bestaande aanroepers zich onveranderd gedragen.
    @productnaam     NVARCHAR(255) = N'meermetjeoverwaarde.nl',
    @verzekeraar_id  INT           = 33,
    @hoofdbranche_id INT           = 51,
    @intermediair_id INT           = 602
)
```

- [ ] **Stap 2: Laat het configuratieblok de parameters gebruiken (regels 49-53)**

De `@v_`-variabelen blijven bestaan, zodat de rest van de body (de kolomcursors op regel 266 en 334-345) ongewijzigd blijft. Van:

```sql
        DECLARE @v_intermediair_id   INT           = 602;
        DECLARE @v_verzekeraar_id    INT           = 33;
        DECLARE @v_hoofdbranche_id   INT           = 51;
        DECLARE @v_productnaam       NVARCHAR(255) = 'meermetjeoverwaarde.nl';
        DECLARE @v_hoofdintermediair INT           = 602;
```

Naar:

```sql
        DECLARE @v_intermediair_id   INT           = @intermediair_id;
        DECLARE @v_verzekeraar_id    INT           = @verzekeraar_id;
        DECLARE @v_hoofdbranche_id   INT           = @hoofdbranche_id;
        DECLARE @v_productnaam       NVARCHAR(255) = @productnaam;
        DECLARE @v_hoofdintermediair INT           = @intermediair_id;
```

- [ ] **Stap 3: Werk de kopregels bij die het tegendeel beweren**

In het commentaarblok bovenaan (regels 10-12) staat nu dat `@route` de configuratie niet aanstuurt en dat alle routes dezelfde vaste defaults gebruiken. Vervang die drie regels door:

```sql
-- @route is uitsluitend een label — wordt op de dbo.Funnel-rij opgeslagen, stuurt verder geen
-- enkele logica aan. De productconfiguratie stuur je los mee via @productnaam, @verzekeraar_id,
-- @hoofdbranche_id en @intermediair_id; laat je die weg, dan gelden de MMJO-waarden.
```

- [ ] **Stap 4: Controleer dat er geen losse 602/33/51 meer in het configuratieblok staat**

Draai vanuit `C:\Users\rvader\Documents\VS_projects\AgendaPicker`:

```bash
grep -n "DECLARE @v_" sql/spFunnelCreateOrCheck.sql
```

Verwacht: vijf regels die alle vijf naar een parameter verwijzen, geen letterlijke getallen of de letterlijke string `'meermetjeoverwaarde.nl'` meer.

- [ ] **Stap 5: Commit in de AgendaPicker-repo**

```bash
git add sql/spFunnelCreateOrCheck.sql
git commit -m "feat: productconfiguratie van spFunnelCreateOrCheck als parameters"
```

---

### Task 2: Validatie- en voorbereidingshelpers

Twee pure functies zonder database, zodat het gedrag vastligt vóór het endpoint eromheen gebouwd wordt.

**Files:**
- Create: `tests/test_funnel_payload.py`
- Modify: `function_app.py` (na `_prepare_make_reservation_payload`, rond regel 543)
- Modify: `.funcignore`

**Interfaces:**
- Consumes: `ValidationError`, `_prepare_make_reservation_payload(payload: dict) -> dict` uit `function_app.py`
- Produces:
  - `_validate_funnel_payload(payload: dict) -> None` — gooit `ValidationError` bij een ontbrekend of ongeldig veld
  - `_prepare_funnel_call(payload: dict) -> dict` — de parameters voor `spFunnelCreateOrCheck`
  - `_prepare_funnel_reservation_payload(payload: dict, klant_id: int) -> dict` — de parameters voor `spMaakReservering`

- [ ] **Stap 1: Schrijf de falende test**

Maak `tests/test_funnel_payload.py`:

```python
"""Tests voor de payload-helpers van POST /funnel.

Draait zonder database: de helpers zijn pure functies. Uitvoeren met
.venv\\Scripts\\python.exe -m unittest discover -s tests -v
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import function_app


def geldige_payload():
    return {
        "datum": "2026-09-30",
        "tijd": "16:00",
        "adviseur_id": "300",
        "duur_kwartieren": 2,
        "campagne_id": 77,
        "route": "funnelpicker-funnelknop",
        "funnel": '{"email":"test@example.com"}',
        "run": "test",
    }


class ValidatieTest(unittest.TestCase):
    def test_geldige_payload_gaat_door(self):
        function_app._validate_funnel_payload(geldige_payload())

    def test_ontbrekende_route_is_fout(self):
        payload = geldige_payload()
        del payload["route"]
        with self.assertRaises(function_app.ValidationError):
            function_app._validate_funnel_payload(payload)

    def test_lege_funnel_is_fout(self):
        payload = geldige_payload()
        payload["funnel"] = "   "
        with self.assertRaises(function_app.ValidationError):
            function_app._validate_funnel_payload(payload)

    def test_campaign_id_alias_wordt_geaccepteerd(self):
        payload = geldige_payload()
        payload["campaign_id"] = payload.pop("campagne_id")
        function_app._validate_funnel_payload(payload)

    def test_duur_kwartieren_nul_is_fout(self):
        payload = geldige_payload()
        payload["duur_kwartieren"] = 0
        with self.assertRaises(function_app.ValidationError):
            function_app._validate_funnel_payload(payload)


class FunnelCallTest(unittest.TestCase):
    def test_alleen_procedure_velden_gaan_mee(self):
        payload = geldige_payload()
        payload["productnaam"] = "schade.nl"
        prepared = function_app._prepare_funnel_call(payload)
        self.assertEqual(
            set(prepared),
            {"funnel", "route", "klant_id", "productnaam"},
        )
        self.assertEqual(prepared["productnaam"], "schade.nl")

    def test_klant_id_nul_wordt_none(self):
        payload = geldige_payload()
        payload["klant_id"] = 0
        self.assertIsNone(function_app._prepare_funnel_call(payload)["klant_id"])

    def test_klant_id_ontbreekt_wordt_none(self):
        self.assertIsNone(function_app._prepare_funnel_call(geldige_payload())["klant_id"])


class ReserveringPayloadTest(unittest.TestCase):
    def test_funnel_en_route_gaan_niet_mee(self):
        prepared = function_app._prepare_funnel_reservation_payload(geldige_payload(), 4242)
        self.assertNotIn("funnel", prepared)
        self.assertNotIn("route", prepared)

    def test_klant_id_komt_uit_de_eerste_procedure(self):
        payload = geldige_payload()
        payload["klant_id"] = 0
        prepared = function_app._prepare_funnel_reservation_payload(payload, 4242)
        self.assertEqual(prepared["klant_id"], 4242)

    def test_mmjo_funnel_alias_gaat_ook_niet_mee(self):
        payload = geldige_payload()
        payload["MMJO/funnel"] = payload["funnel"]
        prepared = function_app._prepare_funnel_reservation_payload(payload, 4242)
        self.assertNotIn("MMJO/funnel", prepared)
        self.assertNotIn("mmjo_funnel", prepared)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Stap 2: Draai de test en controleer dat hij faalt**

```bash
.venv\Scripts\python.exe -m unittest discover -s tests -v
```

Verwacht: `AttributeError: module 'function_app' has no attribute '_validate_funnel_payload'`.

- [ ] **Stap 3: Schrijf de helpers**

Voeg in `function_app.py` direct na `_prepare_make_reservation_payload` toe:

```python
FUNNEL_REQUIRED_FIELDS = ("datum", "tijd", "adviseur_id", "duur_kwartieren", "route", "funnel", "run")

# De parameters die dbo.spFunnelCreateOrCheck kent. _call_sp_dynamic matcht toch op naam via
# sys.parameters, maar door hier expliciet te filteren blijft leesbaar wat er heen gaat en
# belandt de rest van de funnel-payload niet per ongeluk in de procedure-aanroep.
FUNNEL_SP_FIELDS = (
    "funnel",
    "route",
    "klant_id",
    "productnaam",
    "verzekeraar_id",
    "hoofdbranche_id",
    "intermediair_id",
)


def _validate_funnel_payload(payload: dict):
    for field in FUNNEL_REQUIRED_FIELDS:
        value = payload.get(field)
        if value is None or (isinstance(value, str) and not value.strip()):
            raise ValidationError(f"Parameter '{field}' is verplicht.")

    campaign_value = payload.get("campagne_id", payload.get("campaign_id"))
    if campaign_value is None or (isinstance(campaign_value, str) and not campaign_value.strip()):
        raise ValidationError("Parameter 'campagne_id' (of 'campaign_id') is verplicht.")

    try:
        int(campaign_value)
    except (TypeError, ValueError) as ex:
        raise ValidationError("Parameter 'campagne_id' (of 'campaign_id') moet een getal zijn.") from ex

    try:
        duur_kwartieren = int(payload["duur_kwartieren"])
    except (TypeError, ValueError) as ex:
        raise ValidationError("Parameter 'duur_kwartieren' moet een getal zijn.") from ex

    if duur_kwartieren <= 0:
        raise ValidationError("Parameter 'duur_kwartieren' moet groter dan 0 zijn.")


def _prepare_funnel_call(payload: dict) -> dict:
    prepared = {key: payload[key] for key in FUNNEL_SP_FIELDS if key in payload}

    # De procedure maakt een nieuwe klant aan (of zoekt er een op e-mailadres) zodra @klant_id
    # NULL of 0 is. Een ontbrekend veld betekent hetzelfde, dus dat maken we hier expliciet.
    if prepared.get("klant_id") in (None, "", 0, "0"):
        prepared["klant_id"] = None

    return prepared


def _prepare_funnel_reservation_payload(payload: dict, klant_id: int) -> dict:
    prepared = _prepare_make_reservation_payload(payload)

    # Bewust zonder funnel en route: spMaakReservering roept bij campagne_id 230 zelf
    # spMMJOcreateOrcheck aan, wat de klant een tweede keer zou registreren terwijl
    # spFunnelCreateOrCheck dat hierboven al gedaan heeft.
    for key in ("funnel", "mmjo_funnel", "MMJO/funnel", "route"):
        prepared.pop(key, None)

    prepared["klant_id"] = klant_id
    return prepared
```

- [ ] **Stap 4: Draai de test en controleer dat hij slaagt**

```bash
.venv\Scripts\python.exe -m unittest discover -s tests -v
```

Verwacht: `OK`, 11 tests.

- [ ] **Stap 5: Sluit `tests` uit van de deploy**

`.funcignore` bevat nu alleen `.venv` en eindigt zonder newline. Maak er twee regels van:

```
.venv
tests
```

- [ ] **Stap 6: Commit**

```bash
git add function_app.py tests/test_funnel_payload.py .funcignore
git commit -m "feat: payload-helpers voor het funnel-endpoint"
```

---

### Task 3: Het endpoint

**Files:**
- Modify: `function_app.py` — nieuwe route, direct na de `reservering`-route (die eindigt rond regel 975)

**Interfaces:**
- Consumes: `_validate_funnel_payload`, `_prepare_funnel_call`, `_prepare_funnel_reservation_payload` uit Task 2; `_get_connection`, `_call_sp_dynamic`, `_extract_db_error_details` uit `function_app.py`
- Produces: `POST /api/funnel`

- [ ] **Stap 1: Schrijf de route**

```python
@app.route(route="funnel", methods=["POST"])
def funnel(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Funnel API aangeroepen")

    try:
        payload = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Body moet geldige JSON zijn."}),
            status_code=400,
            mimetype="application/json",
        )

    if not isinstance(payload, dict):
        return func.HttpResponse(
            json.dumps({"error": "Body moet een JSON object zijn."}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        _validate_funnel_payload(payload)
        funnel_args = _prepare_funnel_call(payload)
    except (ValidationError, ValueError) as ex:
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=400,
            mimetype="application/json",
        )

    conn = None
    cursor = None
    try:
        conn = _get_connection(payload.get("run"))
        cursor = conn.cursor()

        try:
            funnel_result = _call_sp_dynamic(cursor, "dbo", "spFunnelCreateOrCheck", funnel_args)
        except RuntimeError as ex:
            if "heeft geen parameters of bestaat niet" not in str(ex):
                raise
            conn.rollback()
            return func.HttpResponse(
                json.dumps(
                    {
                        "error": "dbo.spFunnelCreateOrCheck bestaat niet in deze database. "
                        "Voer sql/spFunnelCreateOrCheck.sql uit voordat dit endpoint gebruikt wordt."
                    }
                ),
                status_code=500,
                mimetype="application/json",
            )

        funnel_output = funnel_result.get("output", {})
        klant_id = funnel_output.get("klant_id")

        if klant_id in (None, 0):
            conn.rollback()
            return func.HttpResponse(
                json.dumps(
                    {
                        "error": "spFunnelCreateOrCheck gaf geen klant_id terug.",
                        "stored_procedure_output": funnel_output,
                    },
                    default=str,
                ),
                status_code=500,
                mimetype="application/json",
            )

        # Bewust committen vóór de reservering. spFunnelCreateOrCheck draait binnen ONZE
        # transactie (pyodbc verbindt zonder autocommit), en kan zijn eigen herstel-insert dus
        # niet uitvoeren als het verderop misgaat. Door hier te committen blijft de inzending
        # bewaard - inclusief klant en product - ook als de reservering hierna mislukt. Zie de
        # ADR in docs/DECISIONS.md.
        conn.commit()

        reservering_args = _prepare_funnel_reservation_payload(payload, klant_id)
        reservering_result = _call_sp_dynamic(cursor, "dbo", "spMaakReservering", reservering_args)
        reservering_output = reservering_result.get("output", {})

        sp_foutcode = reservering_output.get("foutcode")
        try:
            parsed_foutcode = int(sp_foutcode) if sp_foutcode is not None else 0
        except (TypeError, ValueError):
            parsed_foutcode = 0

        if parsed_foutcode != 0:
            conn.rollback()
            return func.HttpResponse(
                json.dumps(
                    {
                        "error": "Reservering is niet gelukt; de funnel-inzending is wel vastgelegd.",
                        "klant_id": klant_id,
                        "stored_procedure_output": reservering_output,
                    },
                    default=str,
                ),
                status_code=500,
                mimetype="application/json",
            )

        conn.commit()

        return func.HttpResponse(
            json.dumps(
                {
                    "result": "success",
                    "klant_id": klant_id,
                    "funnel_output": funnel_output,
                    "reservering_output": reservering_output,
                    "matched_parameters": {
                        "spFunnelCreateOrCheck": funnel_result.get("matched_parameters", []),
                        "spMaakReservering": reservering_result.get("matched_parameters", []),
                    },
                },
                default=str,
            ),
            status_code=200,
            mimetype="application/json",
        )
    except RuntimeError as ex:
        if conn:
            conn.rollback()
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=500,
            mimetype="application/json",
        )
    except pyodbc.Error as ex:
        logging.exception("Databasefout in het funnel-endpoint")
        if conn:
            conn.rollback()
        return func.HttpResponse(
            json.dumps(
                {
                    "error": "Databasefout bij uitvoeren van stored procedure.",
                    "details": _extract_db_error_details(ex),
                },
                default=str,
            ),
            status_code=500,
            mimetype="application/json",
        )
    except Exception as ex:
        logging.exception("Fout in het funnel-endpoint")
        if conn:
            conn.rollback()
        return func.HttpResponse(
            json.dumps(
                {
                    "error": "Interne fout bij uitvoeren van stored procedure.",
                    "details": str(ex),
                },
                default=str,
            ),
            status_code=500,
            mimetype="application/json",
        )
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
```

- [ ] **Stap 2: Controleer dat het bestand nog compileert**

```bash
.venv\Scripts\python.exe -m py_compile function_app.py
```

Verwacht: geen uitvoer.

- [ ] **Stap 3: Controleer dat de route geregistreerd staat**

```bash
.venv\Scripts\python.exe -c "import function_app; print([f.get_function_name() for f in function_app.app.get_functions()])"
```

Verwacht: een lijst waarin `funnel` voorkomt, naast `reservering`, `availability`, `afspraak` en de drie wijzig-routes.

- [ ] **Stap 4: Draai de tests uit Task 2 opnieuw**

```bash
.venv\Scripts\python.exe -m unittest discover -s tests -v
```

Verwacht: `OK`, 11 tests. Dit bewijst dat de nieuwe route de helpers niet gebroken heeft.

- [ ] **Stap 5: Commit**

```bash
git add function_app.py
git commit -m "feat: POST /funnel legt funnel-inzending vast en maakt de reservering"
```

---

### Task 4: ADR vastleggen

**Files:**
- Modify: `docs/DECISIONS.md` (append-only)

**Interfaces:**
- Consumes: niets
- Produces: niets

- [ ] **Stap 1: Zoek het hoogste ADR-nummer**

```bash
grep -n "^## ADR-" docs/DECISIONS.md | tail -3
```

- [ ] **Stap 2: Voeg de ADR onderaan toe**

Gebruik het eerstvolgende nummer en de stijl van de ADR's erboven. Inhoud:

```markdown
## ADR-0XX: Funnel-endpoint commit tussen de twee stored procedures

**Datum:** 2026-09-22
**Status:** geaccepteerd

**Context.** `POST /api/funnel` roept `spFunnelCreateOrCheck` en daarna `spMaakReservering` aan op
dezelfde verbinding. `_get_connection()` gebruikt `pyodbc.connect()` zonder `autocommit`, dus beide
aanroepen lopen in een transactie die het endpoint zelf afsluit. `spFunnelCreateOrCheck` bevat een
herstelmechanisme dat na een fout de `dbo.Funnel`-rij opnieuw wegschrijft, maar dat werkt alleen als
de procedure de transactie zelf gestart heeft — en dat is hier niet zo.

**Besluit.** Na `spFunnelCreateOrCheck` wordt gecommit, vóór de reserveringsaanroep. De
reservering krijgt daarna een eigen commit of rollback.

**Gevolg.** Mislukt de reservering, dan blijven de funnel-rij, de klant en het product bestaan; de
klant staat dan geregistreerd zonder afspraak. Dat is bewust gekozen boven alles-of-niets: `dbo.Funnel`
is er juist om de inzending te bewaren, ook als het verderop misgaat, en een geregistreerde lead
zonder afspraak is bruikbaar terwijl een verdwenen inzending dat niet is. De foutmelding van het
endpoint zegt daarom expliciet dat de inzending wel is vastgelegd.

**Daarnaast.** De reserveringsaanroep krijgt bewust geen `funnel` en geen `route` mee.
`spMaakReservering` roept bij `@campagne_id = 230` zelf `spMMJOcreateOrcheck` aan; zou de funnel
meegaan, dan werd de klant bij campagne 230 twee keer geregistreerd.
```

- [ ] **Stap 3: Commit**

```bash
git add docs/DECISIONS.md
git commit -m "docs: ADR over de tussentijdse commit in het funnel-endpoint"
```

---

### Task 5: Verificatie tegen de testdatabase

Deze taak vereist database- en Azure-toegang en wordt door Rob of Daniel uitgevoerd.

**Files:** geen

**Interfaces:**
- Consumes: alles uit Task 1 tot en met 3
- Produces: een werkend `AFSPRAAK_FUNNEL_URL`

- [ ] **Stap 1: Voer de SQL uit op de testdatabase**

Draai in volgorde tegen `SQL_DATABASE_TEST`:

1. `AgendaPicker/sql/dboFunnel_tabel.sql`
2. `AgendaPicker/sql/spFunnelCreateOrCheck.sql` (de versie uit Task 1)

Dit is de eerste keer dat deze procedure draait. Controleer daarbij de twee punten die het
commentaar in de procedure zelf noemt: of `dbo.Klanten` en `dbo.Producten` dezelfde kolommen en
types hebben als waar `spMMJOcreateOrcheck` vanuit gaat, en of `@klant_id` als OUTPUT-parameter
hergebruikt mag worden als doel van de geneste `sp_executesql`-aanroep.

- [ ] **Stap 2: Start de functie lokaal**

```bash
func start
```

- [ ] **Stap 3: Roep het endpoint aan met `run=test`**

```bash
curl -s -X POST http://localhost:7071/api/funnel -H "Content-Type: application/json" -d "{\"datum\":\"2026-09-30\",\"tijd\":\"16:00\",\"adviseur_id\":\"300\",\"duur_kwartieren\":2,\"campagne_id\":77,\"route\":\"handmatige-test\",\"funnel\":\"{\\\"email\\\":\\\"test@example.com\\\",\\\"naam\\\":\\\"Testpersoon\\\"}\",\"run\":\"test\"}"
```

Verwacht: HTTP 200 met `"result": "success"` en een `klant_id` groter dan 0.

- [ ] **Stap 4: Controleer de database**

Controleer in de testdatabase dat er één nieuwe rij in `dbo.Funnel` staat met `route = 'handmatige-test'`
en een gevuld `klant_id`, dat de klant in `dbo.Klanten` bestaat, en dat er een reservering staat op
2026-09-30 16:00 voor adviseur 300.

- [ ] **Stap 5: Controleer de ontdubbeling**

Roep stap 3 nog een keer aan met hetzelfde e-mailadres maar een ander tijdstip. Verwacht: hetzelfde
`klant_id` als de eerste keer, een tweede rij in `dbo.Funnel`, en géén tweede klant in `dbo.Klanten`.

- [ ] **Stap 6: Deploy en zet de omgevingsvariabele**

Deploy AfspraakMaken, en zet daarna in de App Settings van de AgendaPicker-app:

```
AFSPRAAK_FUNNEL_URL=https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net/api/funnel
```

Herstart de AgendaPicker-app en test de FunnelKnop met `run=test`.

---

## Self-Review

**Spec-dekking.** Elk onderdeel van de spec heeft een taak: het endpoint-contract en de twee
SP-aanroepen (Task 3), de parametrisering van `spFunnelCreateOrCheck` (Task 1), de tussentijdse
commit (Task 3 stap 1 en Task 4), het weglaten van `funnel`/`route` bij de reservering (Task 2 en 4),
de uitvoervolgorde inclusief het zetten van `AFSPRAAK_FUNNEL_URL` (Task 5), en de twee open punten
uit de spec (Task 5 stap 1).

De spec noemt dat er geen e-mail verstuurd wordt; dat is een bewuste afwezigheid en heeft daarom
geen taak. Datzelfde geldt voor het niet aanpassen van `spMaakReservering` en `_call_sp_dynamic`.

**Namen.** `_validate_funnel_payload`, `_prepare_funnel_call` en `_prepare_funnel_reservation_payload`
heten in Task 2 (definitie), Task 3 (gebruik) en de tests identiek. `klant_id` is overal de sleutel
die uit `funnel_output` komt en als `klant_id` de reserveringsaanroep in gaat.

**Geen placeholders.** Alle stappen bevatten het letterlijke commando of codeblok. De enige waarde
die de uitvoerder zelf moet bepalen is het ADR-nummer in Task 4, en stap 1 van die taak zegt hoe je
dat vindt.
