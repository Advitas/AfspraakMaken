# Afspraak Wijzigen via Pincode-verificatie Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Laat een klant, zonder in te loggen, zelfstandig de datum/tijd/adviseur/vorm van een bestaande
afspraak wijzigen via een e-mailde, kortlevende pincode.

**Architecture:** Drie nieuwe endpoints in de Azure Function `AfspraakMaken` (pincode aanvragen+mailen,
pincode verifiëren, wijziging opslaan), plus twee nieuwe thin-proxy routes en één nieuwe statische pagina in
`AgendaPicker` die de bestaande beschikbaarheids-kalender hergebruikt. Pincodes leven kort in Azure Table
Storage (via de bestaande `AzureWebJobsStorage`-connectie); de daadwerkelijke wijziging loopt via een nieuwe
stored procedure die **nog niet bestaat** in SQL Server (zie Taak 5).

**Tech Stack:** Python Azure Functions v2 (`function_app.py`) + `azure-data-tables` (nieuw) · Node.js/Express
(`server.js`) + vanilla JS/HTML/CSS (`public/`).

**Spec:** `docs/superpowers/specs/2026-09-03-wijzig-afspraak-pincode-design.md`

**Testing-aanpak (afwijking van het standaard TDD-stramien van deze skill):** geen van beide repo's heeft een
testframework (`docs/CONVENTIONS.md` in AfspraakMaken: "onbekend — geen testframework aangetroffen";
AgendaPicker: alleen `node --check`-syntaxcontrole). Stappen die normaal "schrijf een falende test" zouden
zijn, zijn hier vervangen door een handmatige verificatiestap (curl tegen een lokaal draaiende
`func start`/`npm start`, tegen `SQL_DATABASE_TEST` via de `run`-parameter) — consistent met hoe de rest van
deze repo's altijd getest is (zie `CLAUDE.md`: "Elke wijziging aan een stored-procedure-aanroep testen tegen
SQL_DATABASE_TEST vóór een productie-deploy").

## Global Constraints

- Nooit directe SQL INSERT/UPDATE — alle writes uitsluitend via stored procedures.
- Pincode: 6 cijfers, gegenereerd met Python's `secrets`-module (niet `random`).
- Pincode: 5 minuten geldig, max. 5 foute verificatiepogingen, one-time use (verwijderd na succesvolle
  opslag of na overschrijden van de pogingenlimiet of na verlopen).
- Foutmeldingen bij pincode-verificatie lekken geen onderscheid tussen "bestaat niet"/"verlopen"/"fout
  ingevoerd"/"te vaak fout" — altijd dezelfde generieke Nederlandse boodschap.
- Elke nieuwe/gewijzigde SP-aanroep testen tegen `SQL_DATABASE_TEST` (via `run`-parameter) vóór
  productie-deploy.
- Domeinbegrippen in het Nederlands, ook in code (`afspraak_id`, `adviseur_id`, `vorm_afspraak`,
  `duur_kwartieren`, `pincode`).
- AfspraakMaken-routes: vaste parameter-mapping (zoals `_call_sp_maak_afspraak`), geen dynamische
  `sys.parameters`-matching voor deze drie nieuwe routes.
- Response-shape consistent met bestaande endpoints: `{"result": "success", ...}` bij succes,
  `{"error": "..."}` bij fouten.
- E-mails via Mandrill (`https://mandrillapp.com/api/1.0/messages/send.json`, env var
  `MANDRILL_API_KEY`), non-blocking (een mislukte mail mag de rest van de flow nooit breken), met
  `[TEST]`-prefix/banner wanneer `run != prod`.
- AgendaPicker: `server.js` blijft een dunne proxy (valideert, voegt function-key toe, stuurt door) — geen
  eigen business-logica of SQL-writes.

---

## Taak 1: Pincode-opslag in Azure Table Storage (AfspraakMaken)

**Files:**
- Modify: `requirements.txt`
- Modify: `function_app.py` (nieuwe code toevoegen na regel 1035, einde van het bestand)

**Interfaces:**
- Produces: `_genereer_pincode() -> str`, `_bewaar_pincode_record(afspraak_id, pincode, adviseur_id,
  duur_kwartieren, vorm_afspraak, postcode, run_value) -> None`, `_haal_pincode_record(afspraak_id) ->
  dict | None`, `_verwijder_pincode_record(afspraak_id) -> None`, `_valideer_pincode(afspraak_id,
  ingevoerde_pincode) -> dict` (gooit `ValidationError` bij elke ongeldige situatie) — gebruikt door Taak 2,
  3 en 4.

- [ ] **Step 1: Dependency toevoegen**

`requirements.txt` wordt:

```
azure-functions
pyodbc
requests
azure-data-tables
```

- [ ] **Step 2: Installeer de dependency lokaal**

```bash
.\.venv\Scripts\Activate.ps1
pip install azure-data-tables
```

Expected: installatie slaagt zonder errors.

- [ ] **Step 3: Schrijf de pincode-opslag-helpers**

Voeg toe aan het einde van `function_app.py`:

```python
import secrets
from datetime import datetime, timedelta, timezone

from azure.core.exceptions import ResourceNotFoundError
from azure.data.tables import TableServiceClient, UpdateMode

PINCODE_TABLE_NAME = "WijzigAfspraakPincodes"
PINCODE_GELDIGHEID_MINUTEN = 5
PINCODE_MAX_POGINGEN = 5
PINCODE_GENERIEKE_FOUTMELDING = "Ongeldige of verlopen pincode."


def _genereer_pincode() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _get_pincode_table_client():
    conn_str = _require_any_env("AzureWebJobsStorage")
    service = TableServiceClient.from_connection_string(conn_str)
    return service.create_table_if_not_exists(PINCODE_TABLE_NAME)


def _bewaar_pincode_record(
    afspraak_id, pincode: str, adviseur_id, duur_kwartieren: int, vorm_afspraak: str, postcode, run_value
) -> None:
    verloopt_op = datetime.now(timezone.utc) + timedelta(minutes=PINCODE_GELDIGHEID_MINUTEN)
    entity = {
        "PartitionKey": str(afspraak_id),
        "RowKey": "pincode",
        "Pincode": pincode,
        "VerlooptOp": verloopt_op.isoformat(),
        "Attempts": 0,
        "AdviseurId": str(adviseur_id),
        "DuurKwartieren": int(duur_kwartieren),
        "VormAfspraak": vorm_afspraak,
        "Postcode": str(postcode) if postcode not in (None, "") else "",
        "Run": str(run_value) if run_value not in (None, "") else "",
    }
    table_client = _get_pincode_table_client()
    table_client.upsert_entity(entity, mode=UpdateMode.REPLACE)


def _haal_pincode_record(afspraak_id):
    table_client = _get_pincode_table_client()
    try:
        return table_client.get_entity(partition_key=str(afspraak_id), row_key="pincode")
    except ResourceNotFoundError:
        return None


def _verwijder_pincode_record(afspraak_id) -> None:
    table_client = _get_pincode_table_client()
    try:
        table_client.delete_entity(partition_key=str(afspraak_id), row_key="pincode")
    except ResourceNotFoundError:
        pass


def _verhoog_pincode_pogingen(afspraak_id, record) -> None:
    nieuwe_pogingen = int(record.get("Attempts", 0)) + 1
    if nieuwe_pogingen >= PINCODE_MAX_POGINGEN:
        _verwijder_pincode_record(afspraak_id)
        return

    table_client = _get_pincode_table_client()
    table_client.update_entity(
        {"PartitionKey": str(afspraak_id), "RowKey": "pincode", "Attempts": nieuwe_pogingen},
        mode=UpdateMode.MERGE,
    )


def _valideer_pincode(afspraak_id, ingevoerde_pincode) -> dict:
    record = _haal_pincode_record(afspraak_id)
    if record is None:
        raise ValidationError(PINCODE_GENERIEKE_FOUTMELDING)

    verloopt_op = datetime.fromisoformat(str(record.get("VerlooptOp")))
    if datetime.now(timezone.utc) >= verloopt_op:
        _verwijder_pincode_record(afspraak_id)
        raise ValidationError(PINCODE_GENERIEKE_FOUTMELDING)

    if int(record.get("Attempts", 0)) >= PINCODE_MAX_POGINGEN:
        _verwijder_pincode_record(afspraak_id)
        raise ValidationError(PINCODE_GENERIEKE_FOUTMELDING)

    if str(record.get("Pincode")) != str(ingevoerde_pincode).strip():
        _verhoog_pincode_pogingen(afspraak_id, record)
        raise ValidationError(PINCODE_GENERIEKE_FOUTMELDING)

    return record
```

- [ ] **Step 4: Verifieer met een lokaal Python-scriptje**

Zorg dat `local.settings.json` een geldige `AzureWebJobsStorage`-connectiestring bevat (een echte Storage
Account, of `UseDevelopmentStorage=true` met Azurite lokaal draaiend). Run vanuit de projectroot met de
venv actief:

```bash
python -c "
from function_app import _bewaar_pincode_record, _haal_pincode_record, _valideer_pincode, _verwijder_pincode_record, ValidationError
_bewaar_pincode_record('999999', '123456', 42, 2, 'online', None, 'test')
print(_haal_pincode_record('999999'))
print(_valideer_pincode('999999', '123456'))
try:
    _valideer_pincode('999999', '123456')
    print('FOUT: had moeten falen (one-time use is nog niet van toepassing hier, want opslaan gebeurt in taak 4)')
except ValidationError as ex:
    print('onverwacht maar oké voor nu:', ex)
_verwijder_pincode_record('999999')
print(_haal_pincode_record('999999'))
"
```

Expected: eerste `_haal_pincode_record` toont het record, `_valideer_pincode` faalt niet, laatste
`_haal_pincode_record` print `None`.

- [ ] **Step 5: Commit**

```bash
git add requirements.txt function_app.py
git commit -m "feat: pincode-opslag in Azure Table Storage voor afspraak-wijziging"
```

---

## Taak 2: `/wijzig-aanvraag` — pincode genereren en mailen

**Files:**
- Modify: `function_app.py` (append na Taak 1's code)

**Interfaces:**
- Consumes: `_genereer_pincode`, `_bewaar_pincode_record` (Taak 1); `_require`, `_optional_int`,
  `ValidationError`, `_require_any_env` (bestaand); `requests` (bestaand).
- Produces: route `POST /wijzig-aanvraag`.

- [ ] **Step 1: Schrijf de e-mail-helpers**

```python
def _build_wijzig_email(afspraak_id, pincode: str, run_value) -> tuple[str, str]:
    is_prod = str(run_value).strip().lower() == "prod"
    subject_prefix = "" if is_prod else "[TEST] "
    subject = f"{subject_prefix}Pincode om uw afspraak te wijzigen"

    agendapicker_base = os.getenv(
        "AGENDAPICKER_BASE_URL", "https://agendapicker-ahe5g9g6gdh0gcdw.azurewebsites.net"
    ).rstrip("/")
    link_url = f"{agendapicker_base}/wijzig-afspraak.html?afspraak_id={html.escape(str(afspraak_id), quote=True)}"

    test_banner = (
        ""
        if is_prod
        else (
            '<p style="color:#b00020;font-weight:bold;">Dit is een TESTaanvraag '
            "(niet tegen productie) — geen actie ondernemen.</p>"
        )
    )

    html_body = (
        '<div style="font-family:Segoe UI, Arial, sans-serif;color:#222;max-width:600px;">'
        '<h2 style="color:#1a3c6e;">Afspraak wijzigen</h2>'
        f"{test_banner}"
        "<p>Gebruik onderstaande pincode om uw afspraak te wijzigen. De pincode is "
        f"<strong>5 minuten</strong> geldig.</p>"
        f'<p style="font-size:28px;font-weight:bold;letter-spacing:4px;">{html.escape(pincode)}</p>'
        '<p style="margin-top:16px;">'
        f'<a href="{link_url}" style="background-color:#1a3c6e;color:#ffffff;'
        'padding:8px 16px;border-radius:4px;text-decoration:none;display:inline-block;">'
        "Wijzig uw afspraak</a>"
        "</p>"
        '<p style="color:#888;font-size:12px;margin-top:16px;">'
        "Automatisch gegenereerd door AfspraakMaken. Heeft u dit niet aangevraagd? Dan kunt u deze "
        "e-mail negeren."
        "</p>"
        "</div>"
    )

    return subject, html_body


def _send_wijzig_email(afspraak_id, email: str, pincode: str, run_value) -> None:
    subject, html_body = _build_wijzig_email(afspraak_id, pincode, run_value)
    api_key = _require_any_env("MANDRILL_API_KEY")

    response = requests.post(
        "https://mandrillapp.com/api/1.0/messages/send.json",
        json={
            "key": api_key,
            "message": {
                "html": html_body,
                "subject": subject,
                "from_email": "planning@advitas.nl",
                "from_name": "Advitas",
                "to": [{"email": email, "type": "to"}],
            },
        },
        timeout=15,
    )
    if response.status_code >= 300:
        raise RuntimeError(f"Mandrill sendMail-fout ({response.status_code}): {response.text[:500]}")

    try:
        result = response.json()
    except ValueError:
        result = None

    if isinstance(result, dict) and result.get("status") == "error":
        raise RuntimeError(f"Mandrill wees de aanvraag af: {result}")

    if isinstance(result, list) and result and isinstance(result[0], dict):
        eerste_status = result[0].get("status")
        if eerste_status in {"rejected", "invalid"}:
            raise RuntimeError(f"Mandrill wees de mail af: {result[0]}")


def _try_send_wijzig_email(afspraak_id, email: str, pincode: str, run_value) -> None:
    try:
        _send_wijzig_email(afspraak_id, email, pincode, run_value)
    except Exception:
        logging.exception("Fout bij versturen van wijzig-pincode-mail naar %s", email)
```

- [ ] **Step 2: Schrijf de route**

```python
_EMAIL_PATROON = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$")


def _parse_wijzig_aanvraag_payload(payload: dict) -> dict:
    afspraak_id = _require(payload.get("afspraak_id"), "afspraak_id")
    email = str(_require(payload.get("email"), "email")).strip()
    if not _EMAIL_PATROON.match(email):
        raise ValidationError("'email' moet een geldig e-mailadres zijn.")

    adviseur_id = _require(payload.get("adviseur_id"), "adviseur_id")
    duur_kwartieren = int(_require(payload.get("duur_kwartieren"), "duur_kwartieren"))
    if duur_kwartieren < 1:
        raise ValidationError("'duur_kwartieren' moet minimaal 1 zijn.")

    vorm_afspraak = str(_require(payload.get("vorm_afspraak"), "vorm_afspraak")).strip().lower()
    if vorm_afspraak not in {"online", "buitendienst"}:
        raise ValidationError("'vorm_afspraak' moet 'online' of 'buitendienst' zijn.")

    postcode = payload.get("postcode")
    if vorm_afspraak == "buitendienst" and not re.fullmatch(r"\d{4}", str(postcode or "")):
        raise ValidationError(
            "'postcode' is verplicht en moet uit exact 4 cijfers bestaan bij vorm_afspraak 'buitendienst'."
        )

    return {
        "afspraak_id": afspraak_id,
        "email": email,
        "adviseur_id": adviseur_id,
        "duur_kwartieren": duur_kwartieren,
        "vorm_afspraak": vorm_afspraak,
        "postcode": postcode,
        "run": payload.get("run"),
    }


@app.route(route="wijzig-aanvraag", methods=["POST"])
def wijzig_aanvraag(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Wijzig-aanvraag API aangeroepen")

    try:
        payload = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Body moet geldige JSON zijn."}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        data = _parse_wijzig_aanvraag_payload(payload)
    except (ValidationError, ValueError) as ex:
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        pincode = _genereer_pincode()
        _bewaar_pincode_record(
            data["afspraak_id"],
            pincode,
            data["adviseur_id"],
            data["duur_kwartieren"],
            data["vorm_afspraak"],
            data["postcode"],
            data["run"],
        )
    except RuntimeError as ex:
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=500,
            mimetype="application/json",
        )
    except Exception:
        logging.exception("Fout bij opslaan van pincode-record")
        return func.HttpResponse(
            json.dumps({"error": "Interne fout bij opslaan van de pincode."}),
            status_code=500,
            mimetype="application/json",
        )

    _try_send_wijzig_email(data["afspraak_id"], data["email"], pincode, data["run"])

    return func.HttpResponse(
        json.dumps({"result": "success"}),
        status_code=200,
        mimetype="application/json",
    )
```

- [ ] **Step 3: Verifieer lokaal**

```bash
func start
```

In een andere terminal:

```bash
curl -X POST http://localhost:7071/api/wijzig-aanvraag \
  -H "Content-Type: application/json" \
  -d '{"afspraak_id":999999,"email":"test@advitas.nl","adviseur_id":42,"duur_kwartieren":2,"vorm_afspraak":"online","run":"test"}'
```

Expected: `{"result": "success"}` met status 200, en (bij geldige `MANDRILL_API_KEY` in
`local.settings.json`) een e-mail bij `test@advitas.nl` met een 6-cijferige pincode en een link naar
`.../wijzig-afspraak.html?afspraak_id=999999`.

- [ ] **Step 4: Commit**

```bash
git add function_app.py
git commit -m "feat: /wijzig-aanvraag endpoint voor pincode-mail bij afspraak-wijziging"
```

---

## Taak 3: `/wijzig-verificatie` — pincode controleren

**Files:**
- Modify: `function_app.py` (append na Taak 2's code)

**Interfaces:**
- Consumes: `_valideer_pincode` (Taak 1).
- Produces: route `POST /wijzig-verificatie`.

- [ ] **Step 1: Schrijf de route**

```python
@app.route(route="wijzig-verificatie", methods=["POST"])
def wijzig_verificatie(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Wijzig-verificatie API aangeroepen")

    try:
        payload = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Body moet geldige JSON zijn."}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        afspraak_id = _require(payload.get("afspraak_id"), "afspraak_id")
        pincode = _require(payload.get("pincode"), "pincode")
    except (ValidationError, ValueError) as ex:
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        record = _valideer_pincode(afspraak_id, pincode)
    except ValidationError as ex:
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=400,
            mimetype="application/json",
        )
    except Exception:
        logging.exception("Fout bij verifiëren van pincode")
        return func.HttpResponse(
            json.dumps({"error": "Interne fout bij verifiëren van de pincode."}),
            status_code=500,
            mimetype="application/json",
        )

    return func.HttpResponse(
        json.dumps(
            {
                "result": "success",
                "adviseur_id": record.get("AdviseurId"),
                "duur_kwartieren": record.get("DuurKwartieren"),
                "vorm_afspraak": record.get("VormAfspraak"),
                "postcode": record.get("Postcode") or None,
                "run": record.get("Run") or None,
            },
            default=str,
        ),
        status_code=200,
        mimetype="application/json",
    )
```

- [ ] **Step 2: Verifieer lokaal**

Met `func start` draaiend (zelfde als Taak 2), gebruik makend van het `999999`-record uit Taak 2's curl:

```bash
curl -X POST http://localhost:7071/api/wijzig-verificatie \
  -H "Content-Type: application/json" \
  -d '{"afspraak_id":999999,"pincode":"000000"}'
```

Expected: HTTP 400, `{"error": "Ongeldige of verlopen pincode."}` (fout pincode). Vraag daarna opnieuw een
pincode aan via `/wijzig-aanvraag` (Taak 2's curl) en lees de echte pincode uit de ontvangen mail of uit
Table Storage (Azure Storage Explorer), en verifieer daarmee:

```bash
curl -X POST http://localhost:7071/api/wijzig-verificatie \
  -H "Content-Type: application/json" \
  -d '{"afspraak_id":999999,"pincode":"<echte pincode>"}'
```

Expected: HTTP 200 met `adviseur_id: "42"`, `duur_kwartieren: 2`, `vorm_afspraak: "online"`.

- [ ] **Step 3: Commit**

```bash
git add function_app.py
git commit -m "feat: /wijzig-verificatie endpoint voor pincode-check bij afspraak-wijziging"
```

---

## Taak 4: `/wijzig-opslaan` — nieuwe datum/tijd/adviseur/vorm opslaan

**Files:**
- Modify: `function_app.py` (append na Taak 3's code)

**Interfaces:**
- Consumes: `_valideer_pincode`, `_verwijder_pincode_record` (Taak 1); `_get_connection`,
  `_read_all_result_sets`, `_extract_db_error_details` (bestaand).
- Produces: route `POST /wijzig-opslaan`, helper `_call_sp_wijzig_afspraak(cursor, data) -> dict`.

> **Let op:** deze taak roept `[dbo].[spWijzigAfspraakDatumTijd]` aan — die stored procedure bestaat nog
> niet in SQL Server (zie spec, sectie "Openstaande afhankelijkheid"). Stap 4 (verifiëren tegen
> `SQL_DATABASE_TEST`) kan pas slagen zodra die procedure daar is aangemaakt. Tot die tijd is het enige
> haalbare bewijs dat de Python-code de juiste EXEC-statement en parameters opbouwt (te zien in de
> foutmelding "Could not find stored procedure" — dat bevestigt dat de aanroep de database bereikt en
> correct is opgebouwd, alleen de procedure zelf ontbreekt nog).

- [ ] **Step 1: Schrijf `_call_sp_wijzig_afspraak`**

```python
def _call_sp_wijzig_afspraak(cursor, data: dict) -> dict:
    cursor.execute(
        """
        DECLARE @foutmelding NVARCHAR(500);

        EXEC [dbo].[spWijzigAfspraakDatumTijd]
            @afspraak_id = ?,
            @adviseur_id = ?,
            @datum = ?,
            @tijd = ?,
            @duur_kwartieren = ?,
            @vorm_afspraak = ?,
            @foutmelding = @foutmelding OUTPUT;

        SELECT @foutmelding AS foutmelding;
        """,
        data["afspraak_id"],
        data["adviseur_id"],
        data["datum"],
        data["tijd"],
        data["duur_kwartieren"],
        data["vorm_afspraak"],
    )

    result_sets = _read_all_result_sets(cursor)
    output = {}
    if result_sets and result_sets[-1]:
        output = result_sets[-1][0]
        result_sets = result_sets[:-1]

    return {"output": output, "result_sets": result_sets}
```

- [ ] **Step 2: Schrijf de route**

```python
def _parse_wijzig_opslaan_payload(payload: dict) -> dict:
    afspraak_id = _require(payload.get("afspraak_id"), "afspraak_id")
    pincode = _require(payload.get("pincode"), "pincode")
    adviseur_id = int(_require(payload.get("adviseur_id"), "adviseur_id"))

    try:
        datum = date.fromisoformat(str(_require(payload.get("datum"), "datum")))
    except ValueError as ex:
        raise ValidationError("'datum' moet formaat YYYY-MM-DD hebben, bijvoorbeeld 2026-06-24.") from ex

    try:
        tijd = time.fromisoformat(str(_require(payload.get("tijd"), "tijd")))
    except ValueError as ex:
        raise ValidationError("'tijd' moet formaat HH:MM of HH:MM:SS hebben, bijvoorbeeld 14:30.") from ex

    duur_kwartieren = int(_require(payload.get("duur_kwartieren"), "duur_kwartieren"))
    if duur_kwartieren < 1:
        raise ValidationError("'duur_kwartieren' moet minimaal 1 zijn.")

    vorm_afspraak = str(_require(payload.get("vorm_afspraak"), "vorm_afspraak")).strip().lower()
    if vorm_afspraak not in {"online", "buitendienst"}:
        raise ValidationError("'vorm_afspraak' moet 'online' of 'buitendienst' zijn.")

    return {
        "afspraak_id": afspraak_id,
        "pincode": pincode,
        "adviseur_id": adviseur_id,
        "datum": datum,
        "tijd": tijd,
        "duur_kwartieren": duur_kwartieren,
        "vorm_afspraak": vorm_afspraak,
        "run": payload.get("run"),
    }


@app.route(route="wijzig-opslaan", methods=["POST"])
def wijzig_opslaan(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Wijzig-opslaan API aangeroepen")

    try:
        payload = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Body moet geldige JSON zijn."}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        data = _parse_wijzig_opslaan_payload(payload)
    except (ValidationError, ValueError) as ex:
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        _valideer_pincode(data["afspraak_id"], data["pincode"])
    except ValidationError as ex:
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=400,
            mimetype="application/json",
        )

    conn = None
    cursor = None
    try:
        conn = _get_connection(data["run"])
        cursor = conn.cursor()

        sp_result = _call_sp_wijzig_afspraak(cursor, data)
        foutmelding = sp_result["output"].get("foutmelding")

        if foutmelding:
            conn.rollback()
            return func.HttpResponse(
                json.dumps(
                    {"error": "Stored procedure gaf een foutmelding.", "stored_procedure_output": sp_result["output"]},
                    default=str,
                ),
                status_code=500,
                mimetype="application/json",
            )

        conn.commit()
        _verwijder_pincode_record(data["afspraak_id"])

        return func.HttpResponse(
            json.dumps({"result": "success", "stored_procedure_output": sp_result["output"]}, default=str),
            status_code=200,
            mimetype="application/json",
        )
    except RuntimeError as ex:
        return func.HttpResponse(
            json.dumps({"error": str(ex)}),
            status_code=500,
            mimetype="application/json",
        )
    except pyodbc.Error as ex:
        logging.exception("Databasefout bij aanroepen van spWijzigAfspraakDatumTijd")
        if conn:
            conn.rollback()
        return func.HttpResponse(
            json.dumps(
                {"error": "Databasefout bij uitvoeren van stored procedure.", "details": _extract_db_error_details(ex)},
                default=str,
            ),
            status_code=500,
            mimetype="application/json",
        )
    except Exception:
        logging.exception("Fout bij aanroepen van spWijzigAfspraakDatumTijd")
        if conn:
            conn.rollback()
        return func.HttpResponse(
            json.dumps({"error": "Interne fout bij uitvoeren van stored procedure."}),
            status_code=500,
            mimetype="application/json",
        )
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
```

- [ ] **Step 3: Verifieer lokaal (tot de grens van wat mogelijk is zonder de SP)**

Vraag opnieuw een pincode aan (Taak 2's curl, `afspraak_id=999999`) en lees de echte pincode uit de mail,
dan:

```bash
curl -X POST http://localhost:7071/api/wijzig-opslaan \
  -H "Content-Type: application/json" \
  -d '{"afspraak_id":999999,"pincode":"<echte pincode>","adviseur_id":42,"datum":"2026-09-10","tijd":"14:30","duur_kwartieren":2,"vorm_afspraak":"online","run":"test"}'
```

Expected (met `SQL_DATABASE_TEST` correct geconfigureerd maar zónder de SP): HTTP 500 met een
databasefout die klaagt dat `spWijzigAfspraakDatumTijd` niet bestaat (`_extract_db_error_details` toont de
ruwe ODBC-foutmelding). Dat bevestigt dat pincode-validatie, connectie en EXEC-statement-opbouw correct
werken; de SP zelf moet nog gebouwd worden (zie Taak 5). Verifieer ook een foute pincode:

```bash
curl -X POST http://localhost:7071/api/wijzig-opslaan \
  -H "Content-Type: application/json" \
  -d '{"afspraak_id":999999,"pincode":"000000","adviseur_id":42,"datum":"2026-09-10","tijd":"14:30","duur_kwartieren":2,"vorm_afspraak":"online","run":"test"}'
```

Expected: HTTP 400 `{"error": "Ongeldige of verlopen pincode."}`, zonder dat er een databaseconnectie
geopend wordt (pincode-check gebeurt vóór `_get_connection`).

- [ ] **Step 4: Commit**

```bash
git add function_app.py
git commit -m "feat: /wijzig-opslaan endpoint voor opslaan van gewijzigde afspraak"
```

---

## Taak 5: Documentatie AfspraakMaken bijwerken

**Files:**
- Modify: `README.txt`
- Modify: `local.settings.json.example`
- Modify: `docs/TODO.md`
- Modify: `docs/DECISIONS.md`

**Interfaces:** geen (documentatie-only).

- [ ] **Step 1: `README.txt` uitbreiden**

Voeg aan het einde van `README.txt` toe:

```

---

Nieuwe endpoints: afspraak wijzigen via pincode

POST /api/wijzig-aanvraag (of /wijzig-aanvraag als routePrefix leeg staat)
Body: { afspraak_id, email, adviseur_id, duur_kwartieren, vorm_afspraak, postcode (verplicht bij
vorm_afspraak=buitendienst), run }
Gedrag: genereert een 6-cijferige pincode (5 min geldig, max 5 pogingen), slaat die tijdelijk op in Azure
Table Storage, en mailt de pincode + een link naar de AgendaPicker-wijzigpagina naar `email`.

POST /api/wijzig-verificatie
Body: { afspraak_id, pincode }
Gedrag: controleert de pincode. Bij succes: retourneert adviseur_id, duur_kwartieren, vorm_afspraak,
postcode, run uit het pincode-record (voor de kalender in AgendaPicker).

POST /api/wijzig-opslaan
Body: { afspraak_id, pincode, adviseur_id, datum, tijd, duur_kwartieren, vorm_afspraak, run }
Gedrag: controleert de pincode opnieuw, roept [dbo].[spWijzigAfspraakDatumTijd] aan. Bij succes wordt het
pincode-record verwijderd (one-time use).

Nieuwe environment variable:
- AzureWebJobsStorage (verplicht — standaard Azure Functions storage-connectie, gebruikt voor de
  tijdelijke pincode-opslag)
- AGENDAPICKER_BASE_URL (optioneel, default
  https://agendapicker-ahe5g9g6gdh0gcdw.azurewebsites.net — basis-URL voor de link in de pincode-mail)
```

- [ ] **Step 2: `local.settings.json.example` uitbreiden**

Voeg `"AGENDAPICKER_BASE_URL"` toe aan de `Values`, direct na `"MANDRILL_API_KEY"`:

```json
    "MANDRILL_API_KEY": "<mandrill-api-key>",
    "AGENDAPICKER_BASE_URL": "https://agendapicker-ahe5g9g6gdh0gcdw.azurewebsites.net",
```

(`AzureWebJobsStorage` staat al in het bestand als `"UseDevelopmentStorage=true"` — die regel hoeft niet
gewijzigd te worden, alleen lokaal met Azurite draaien om Taak 1's verificatiestap te kunnen uitvoeren.)

- [ ] **Step 3: `docs/TODO.md` bijwerken**

Voeg een item toe:

```
- [ ] `spWijzigAfspraakDatumTijd` moet gebouwd worden in SQL Server (buiten deze repo, door een DBA) met
  contract `@afspraak_id, @adviseur_id, @datum, @tijd, @duur_kwartieren, @vorm_afspraak, @foutmelding
  OUTPUT` — zie `docs/superpowers/specs/2026-09-03-wijzig-afspraak-pincode-design.md`. Tot dan geeft
  `/wijzig-opslaan` een databasefout ("procedure niet gevonden").
- [ ] Bevestigen dat `MANDRILL_API_KEY` en `AzureWebJobsStorage` correct in de Function App's App Settings
  staan voor de nieuwe wijzig-pincode-mail en pincode-opslag.
```

- [ ] **Step 4: `docs/DECISIONS.md` — nieuwe ADR toevoegen**

Voeg onderaan (append-only, niet bewerken) toe:

```

## 2026-09-03 — Afspraak wijzigen via e-mail-pincode, pincode-opslag in Azure Table Storage

**Context:** een klant moest zonder in te loggen de datum/tijd/adviseur/vorm van een bestaande afspraak
kunnen wijzigen. Een letterlijk "tijdelijk bestand" op de Function App (zoals oorspronkelijk gevraagd) is
niet betrouwbaar op een Azure Functions Consumption-plan (meerdere instanties, geen gegarandeerd gedeelde
lokale schijf tussen aanroepen).

**Beslissing:** de pincode (+ afspraak_id, adviseur_id, duur_kwartieren, vorm_afspraak, postcode, run)
wordt 5 minuten bewaard in Azure Table Storage, via de bestaande `AzureWebJobsStorage`-connectie (geen
nieuwe externe dienst, wel de nieuwe dependency `azure-data-tables`). Drie nieuwe endpoints
(`/wijzig-aanvraag`, `/wijzig-verificatie`, `/wijzig-opslaan`) volgen dezelfde vaste-parameter-mapping-stijl
als `/afspraak`. De daadwerkelijke opslag loopt via een nieuwe stored procedure
`spWijzigAfspraakDatumTijd` die nog gebouwd moet worden buiten deze repo (zie `docs/TODO.md`).

**Gevolgen:** `/wijzig-opslaan` faalt met een databasefout totdat de stored procedure bestaat in
`SQL_DATABASE_TEST`/productie. Pincodes zijn one-time-use (verwijderd na succesvolle opslag), 5 minuten
geldig, max. 5 foute pogingen; foutmeldingen bij verificatie lekken bewust geen detail over de exacte
reden van afwijzing.
```

- [ ] **Step 5: Commit**

```bash
git add README.txt local.settings.json.example docs/TODO.md docs/DECISIONS.md
git commit -m "docs: documenteer wijzig-afspraak-pincode-endpoints en openstaande SP-afhankelijkheid"
```

---

## Taak 6: Thin-proxy routes in AgendaPicker (`server.js`)

**Files:**
- Modify: `server.js:9-12` (env var-declaraties), en na regel 747 (na de bestaande `/api/reservering`-route,
  vóór `/healthz`)

**Interfaces:**
- Consumes: bestaande `normalizeRunValue`, `normalizeText`, `bookingFunctionKey` (in `server.js`).
- Produces: routes `POST /api/wijziging/verifieer-pincode`, `POST /api/wijziging/opslaan`.

- [ ] **Step 1: Nieuwe env var-declaraties**

Wijzig regel 9-12 (de blok met `bookingApiUrl`/`reservationApiUrl`/`availabilityApiUrl`/
`bookingFunctionKey`) door twee regels toe te voegen erna:

```javascript
const bookingApiUrl = (process.env.AFSPRAAK_MAKEN_URL || 'https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net/afspraak').trim();
const reservationApiUrl = (process.env.AFSPRAAK_RESERVERING_URL || process.env.AFSPRAAK_MAKEN_URL || 'https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net/afspraak').trim();
const availabilityApiUrl = (process.env.AFSPRAAK_AVAILABILITY_URL || '').trim();
const wijzigVerificatieUrl = (process.env.AFSPRAAK_WIJZIG_VERIFICATIE_URL || 'https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net/wijzig-verificatie').trim();
const wijzigOpslaanUrl = (process.env.AFSPRAAK_WIJZIG_OPSLAAN_URL || 'https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net/wijzig-opslaan').trim();
const bookingFunctionKey = (process.env.AFSPRAAK_MAKEN_KEY || process.env.BOOKING_FUNCTION_KEY || '').trim();
```

- [ ] **Step 2: Schrijf de twee routes**

Voeg toe direct vóór `app.get('/healthz', ...)` (na de sluitende `});` van `/api/reservering`):

```javascript
app.post('/api/wijziging/verifieer-pincode', async (req, res) => {
  if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) {
    return res.status(400).json({ error: 'Een geldige JSON-body is verplicht.' });
  }

  const afspraakId = normalizeText(req.body.afspraak_id);
  const pincode = normalizeText(req.body.pincode);

  if (!afspraakId) {
    return res.status(400).json({ error: 'Parameter "afspraak_id" is verplicht.' });
  }

  if (!pincode) {
    return res.status(400).json({ error: 'Parameter "pincode" is verplicht.' });
  }

  try {
    const requestHeaders = {
      'Content-Type': 'application/json',
      Accept: 'application/json'
    };

    if (bookingFunctionKey) {
      requestHeaders['x-functions-key'] = bookingFunctionKey;
    }

    const upstreamResponse = await fetch(wijzigVerificatieUrl, {
      method: 'POST',
      headers: requestHeaders,
      body: JSON.stringify({ afspraak_id: afspraakId, pincode })
    });

    const rawBody = await upstreamResponse.text();
    let responseBody = null;
    if (rawBody) {
      try {
        responseBody = JSON.parse(rawBody);
      } catch {
        responseBody = rawBody;
      }
    }

    if (!upstreamResponse.ok) {
      return res.status(upstreamResponse.status).json({
        error: 'Pincode-verificatie gaf een foutmelding.',
        details: responseBody
      });
    }

    return res.json(responseBody);
  } catch (error) {
    console.error('Wijzig-verificatie API call failed:', error.message);
    return res.status(500).json({ error: 'Pincode-verificatie aanroepen is mislukt.' });
  }
});

app.post('/api/wijziging/opslaan', async (req, res) => {
  if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) {
    return res.status(400).json({ error: 'Een geldige JSON-body is verplicht.' });
  }

  const afspraakId = normalizeText(req.body.afspraak_id);
  const pincode = normalizeText(req.body.pincode);
  const adviseurIdRaw = req.body.adviseur_id;
  const datum = normalizeText(req.body.datum);
  const tijd = normalizeText(req.body.tijd);
  const durationQuartersRaw = req.body.duur_kwartieren;
  const vormAfspraak = normalizeText(req.body.vorm_afspraak).toLowerCase();
  const run = normalizeRunValue(req.body.run);
  const adviseurId = Number(adviseurIdRaw);
  const duurKwartieren = Number(durationQuartersRaw);

  if (!afspraakId) {
    return res.status(400).json({ error: 'Parameter "afspraak_id" is verplicht.' });
  }
  if (!pincode) {
    return res.status(400).json({ error: 'Parameter "pincode" is verplicht.' });
  }
  if (!Number.isInteger(adviseurId) || adviseurId <= 0) {
    return res.status(400).json({ error: 'Parameter "adviseur_id" is verplicht en moet een positief integer zijn.' });
  }
  if (!isValidDate(datum)) {
    return res.status(400).json({ error: 'Parameter "datum" is verplicht in formaat YYYY-MM-DD.' });
  }
  if (!isValidTime(tijd)) {
    return res.status(400).json({ error: 'Parameter "tijd" is verplicht in formaat HH:mm.' });
  }
  if (!Number.isInteger(duurKwartieren) || duurKwartieren <= 0) {
    return res.status(400).json({ error: 'Parameter "duur_kwartieren" is verplicht en moet een positief integer zijn.' });
  }
  if (!['online', 'buitendienst'].includes(vormAfspraak)) {
    return res.status(400).json({ error: 'Parameter "vorm_afspraak" moet online of buitendienst zijn.' });
  }

  try {
    const requestHeaders = {
      'Content-Type': 'application/json',
      Accept: 'application/json'
    };

    if (bookingFunctionKey) {
      requestHeaders['x-functions-key'] = bookingFunctionKey;
    }

    const upstreamPayload = {
      afspraak_id: afspraakId,
      pincode,
      adviseur_id: adviseurId,
      datum,
      tijd,
      duur_kwartieren: duurKwartieren,
      vorm_afspraak: vormAfspraak,
      run
    };

    const upstreamResponse = await fetch(wijzigOpslaanUrl, {
      method: 'POST',
      headers: requestHeaders,
      body: JSON.stringify(upstreamPayload)
    });

    const rawBody = await upstreamResponse.text();
    let responseBody = null;
    if (rawBody) {
      try {
        responseBody = JSON.parse(rawBody);
      } catch {
        responseBody = rawBody;
      }
    }

    if (!upstreamResponse.ok) {
      return res.status(upstreamResponse.status).json({
        error: 'Wijziging opslaan gaf een foutmelding.',
        details: responseBody
      });
    }

    return res.json(responseBody);
  } catch (error) {
    console.error('Wijzig-opslaan API call failed:', error.message);
    return res.status(500).json({ error: 'Wijziging opslaan is mislukt.' });
  }
});
```

- [ ] **Step 3: Syntax-check + lokaal verifiëren**

```bash
npm test
```

Expected: `node --check` slaagt (geen syntaxfouten).

Zet in `.env` (lokaal, niet gecommit) `AFSPRAAK_WIJZIG_VERIFICATIE_URL=http://localhost:7071/api/wijzig-verificatie`
en `AFSPRAAK_WIJZIG_OPSLAAN_URL=http://localhost:7071/api/wijzig-opslaan` (naar de lokale AfspraakMaken
`func start`), start dan:

```bash
npm start
```

En in een andere terminal (met AfspraakMaken's `func start` ook actief en een geldig pincode-record uit
Taak 2/3):

```bash
curl -X POST http://localhost:3001/api/wijziging/verifieer-pincode \
  -H "Content-Type: application/json" \
  -d '{"afspraak_id":999999,"pincode":"<echte pincode>"}'
```

Expected: HTTP 200 met dezelfde JSON als het directe AfspraakMaken-endpoint in Taak 3.

- [ ] **Step 4: Commit**

```bash
git add server.js
git commit -m "feat: thin-proxy routes voor pincode-verificatie en wijziging-opslaan"
```

---

## Taak 7: `wijzig-afspraak.html` — klant-facing wijzigpagina

**Files:**
- Create: `public/wijzig-afspraak.html`
- Create: `public/wijzig-afspraak.css`
- Create: `public/wijzig-afspraak.js`

**Interfaces:**
- Consumes: `GET /api/availability` (bestaand, ongewijzigd), `POST /api/wijziging/verifieer-pincode`,
  `POST /api/wijziging/opslaan` (Taak 6).

- [ ] **Step 1: HTML**

```html
<!doctype html>
<html lang="nl">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Afspraak wijzigen</title>
    <link rel="stylesheet" href="wijzig-afspraak.css" />
  </head>
  <body>
    <main class="wijzig-afspraak">
      <section id="pincodeStep" class="panel pincode-panel">
        <h1>Afspraak wijzigen</h1>
        <p>Vul de pincode in die u per e-mail heeft ontvangen.</p>
        <form id="pincodeForm" novalidate>
          <label>
            <span class="field-label">Pincode *</span>
            <input type="text" name="pincode" inputmode="numeric" pattern="\d{6}" maxlength="6" required />
          </label>
          <button id="verifyBtn" class="primary" type="submit">Bevestigen</button>
        </form>
        <p id="pincodeFeedback" class="feedback"></p>
      </section>

      <section id="calendarStep" class="panel picker-panel hidden">
        <header class="panel-header">
          <h1>Kies een nieuwe datum</h1>
          <div class="selected-date-text-wrap">
            <span id="selectedDateText" class="selected-date-text">-</span>
          </div>
        </header>

        <div class="picker-layout">
          <section class="calendar-col" aria-label="Kalender">
            <div class="calendar-nav">
              <button id="prevMonth" type="button" aria-label="Vorige maand">&#x2039;</button>
              <strong id="monthLabel"></strong>
              <button id="nextMonth" type="button" aria-label="Volgende maand">&#x203A;</button>
            </div>
            <div class="weekday-row" aria-hidden="true">
              <span>ma</span><span>di</span><span>wo</span><span>do</span><span>vr</span><span>za</span><span>zo</span>
            </div>
            <div id="calendarGrid" class="calendar-grid" role="grid"></div>
          </section>

          <section class="slots-col" aria-label="Tijdsloten">
            <div id="slotsGrid" class="slots-grid"></div>
            <p id="slotFeedback" class="feedback"></p>
          </section>
        </div>

        <button id="saveBtn" class="primary" type="button" disabled>Opslaan</button>
        <p id="saveFeedback" class="feedback"></p>
      </section>
    </main>

    <script src="wijzig-afspraak.js"></script>
  </body>
</html>
```

- [ ] **Step 2: CSS**

```css
body {
  margin: 0;
  font-family: "Segoe UI", Arial, sans-serif;
  background: #f5f6f8;
  color: #222;
}

.wijzig-afspraak {
  max-width: 640px;
  margin: 0 auto;
  padding: 24px 16px;
}

.panel {
  background: #fff;
  border-radius: 8px;
  padding: 24px;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.08);
  margin-bottom: 16px;
}

.panel.hidden {
  display: none;
}

h1 {
  color: #1a3c6e;
  font-size: 20px;
  margin: 0 0 12px;
}

.field-label {
  display: block;
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 4px;
}

input[type="text"] {
  width: 100%;
  padding: 10px;
  font-size: 18px;
  letter-spacing: 4px;
  box-sizing: border-box;
  border: 1px solid #ccc;
  border-radius: 4px;
}

button.primary {
  margin-top: 16px;
  background: #1a3c6e;
  color: #fff;
  border: none;
  border-radius: 4px;
  padding: 10px 20px;
  font-size: 15px;
  cursor: pointer;
}

button.primary:disabled {
  background: #a9b6c9;
  cursor: not-allowed;
}

.feedback {
  min-height: 18px;
  font-size: 13px;
  color: #b00020;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.picker-layout {
  display: flex;
  gap: 24px;
  flex-wrap: wrap;
  margin-top: 16px;
}

.calendar-col,
.slots-col {
  flex: 1 1 240px;
}

.calendar-nav {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.weekday-row,
.calendar-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 4px;
  text-align: center;
}

.weekday-row {
  font-size: 12px;
  color: #888;
  margin-bottom: 4px;
}

.day-cell {
  padding: 8px 0;
  border: none;
  border-radius: 4px;
  background: #eee;
  cursor: not-allowed;
  color: #aaa;
}

.day-cell.available {
  background: #dcecff;
  color: #1a3c6e;
  cursor: pointer;
}

.day-cell.selected {
  background: #1a3c6e;
  color: #fff;
}

.day-cell.muted {
  background: transparent;
}

.slots-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.slot {
  padding: 8px 12px;
  border: 1px solid #1a3c6e;
  border-radius: 4px;
  background: #fff;
  color: #1a3c6e;
  cursor: pointer;
}

.slot.selected {
  background: #1a3c6e;
  color: #fff;
}
```

- [ ] **Step 3: JS**

```javascript
const params = new URLSearchParams(window.location.search);
const afspraakId = (params.get('afspraak_id') || '').trim();

const state = {
  verified: false,
  run: 'test',
  duurKwartieren: 3,
  vormAfspraak: 'online',
  postcode: null,
  monthCursor: null,
  selectedDate: null,
  selectedTime: null,
  selectedAdvisorIds: [],
  minDate: null,
  maxDate: null,
  dayAvailability: new Map(),
  loadedMonths: new Set(),
  saving: false
};

const pincodeStep = document.getElementById('pincodeStep');
const calendarStep = document.getElementById('calendarStep');
const pincodeForm = document.getElementById('pincodeForm');
const pincodeFeedback = document.getElementById('pincodeFeedback');
const verifyBtn = document.getElementById('verifyBtn');
const prevMonthButton = document.getElementById('prevMonth');
const nextMonthButton = document.getElementById('nextMonth');
const monthLabel = document.getElementById('monthLabel');
const calendarGrid = document.getElementById('calendarGrid');
const slotsGrid = document.getElementById('slotsGrid');
const slotFeedback = document.getElementById('slotFeedback');
const selectedDateText = document.getElementById('selectedDateText');
const saveBtn = document.getElementById('saveBtn');
const saveFeedback = document.getElementById('saveFeedback');

const monthFormatter = new Intl.DateTimeFormat('nl-NL', { month: 'long', year: 'numeric' });
const fullDateFormatter = new Intl.DateTimeFormat('nl-NL', { weekday: 'long', day: 'numeric', month: 'long' });

function pad(value) {
  return String(value).padStart(2, '0');
}

function toIsoDate(date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function parseIsoDate(isoDate) {
  const [year, month, day] = isoDate.split('-').map(Number);
  return new Date(year, month - 1, day);
}

function addDays(date, days) {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

function addMonths(date, months) {
  const next = new Date(date);
  next.setMonth(next.getMonth() + months);
  return next;
}

function firstDayOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function lastDayOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth() + 1, 0);
}

function getFieldValue(source, keys) {
  if (!source || typeof source !== 'object') {
    return undefined;
  }
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(source, key)) {
      return source[key];
    }
  }
  return undefined;
}

function normalizeTimeValue(rawTime) {
  const value = String(rawTime || '').trim();
  const match = value.match(/^(\d{2}:\d{2})(:\d{2})?$/);
  return match ? match[1] : value;
}

function normalizeSlots(rawSlots) {
  return (rawSlots || [])
    .map((slot) => {
      const timeRaw = getFieldValue(slot, ['timeblock', 'timeBlock', 'time', 'tijd']);
      const advisorIdsRaw = getFieldValue(slot, ['adviseurIds', 'advisorIds', 'adviseur_id', 'advisorId']);
      const advisorIds = Array.isArray(advisorIdsRaw)
        ? advisorIdsRaw.map((value) => String(value).trim()).filter(Boolean)
        : String(advisorIdsRaw || '').split(',').map((value) => value.trim()).filter(Boolean);
      return { time: normalizeTimeValue(timeRaw), advisorIds };
    })
    .filter((slot) => /^\d{2}:\d{2}$/.test(slot.time) && slot.advisorIds.length > 0)
    .sort((a, b) => a.time.localeCompare(b.time));
}

function groupMonthSlotsByDate(rawSlots) {
  const slotsByDate = new Map();
  (rawSlots || []).forEach((slot) => {
    const rawDate = getFieldValue(slot, ['afspraakDatum', 'afspraak_datum', 'datum', 'date']);
    const isoMatch = String(rawDate || '').match(/^(\d{4}-\d{2}-\d{2})/);
    if (!isoMatch) {
      return;
    }
    const isoDate = isoMatch[1];
    const existing = slotsByDate.get(isoDate) || [];
    existing.push(slot);
    slotsByDate.set(isoDate, existing);
  });
  return slotsByDate;
}

async function preloadMonthAvailability() {
  const monthStart = firstDayOfMonth(state.monthCursor);
  const monthEnd = lastDayOfMonth(state.monthCursor);
  const start = monthStart < parseIsoDate(state.minDate) ? parseIsoDate(state.minDate) : monthStart;
  const end = monthEnd > parseIsoDate(state.maxDate) ? parseIsoDate(state.maxDate) : monthEnd;
  if (start > end) {
    return;
  }

  const monthKey = `${monthStart.getFullYear()}-${pad(monthStart.getMonth() + 1)}`;
  if (state.loadedMonths.has(monthKey)) {
    return;
  }

  const query = new URLSearchParams({
    date: toIsoDate(monthStart),
    requiredFreeSlots: String(state.duurKwartieren),
    monthView: 'true',
    run: state.run,
    vorm_afspraak: state.vormAfspraak
  });
  if (state.vormAfspraak === 'buitendienst' && state.postcode) {
    query.set('postcode', state.postcode);
  }

  slotFeedback.textContent = 'Beschikbaarheid laden...';

  const response = await fetch(`/api/availability?${query.toString()}`);
  const rawBody = await response.text();
  let data = null;
  if (rawBody) {
    try {
      data = JSON.parse(rawBody);
    } catch {
      data = rawBody;
    }
  }

  if (!response.ok) {
    throw new Error('Beschikbaarheid ophalen mislukt.');
  }

  const slots = (data && typeof data === 'object' && Array.isArray(data.slots)) ? data.slots : [];
  const slotsByDate = groupMonthSlotsByDate(slots);

  let cursor = new Date(start);
  while (cursor <= end) {
    const isoDate = toIsoDate(cursor);
    state.dayAvailability.set(isoDate, normalizeSlots(slotsByDate.get(isoDate) || []));
    cursor = addDays(cursor, 1);
  }

  state.loadedMonths.add(monthKey);
}

function getMonthAvailabilityDates() {
  const available = new Set();
  state.dayAvailability.forEach((slots, isoDate) => {
    if (slots.length) {
      available.add(isoDate);
    }
  });
  return available;
}

function renderCalendar() {
  const monthStart = firstDayOfMonth(state.monthCursor);
  const monthEnd = lastDayOfMonth(state.monthCursor);
  const availableDates = getMonthAvailabilityDates();

  monthLabel.textContent = monthFormatter.format(monthStart);

  const mondayBasedOffset = (monthStart.getDay() + 6) % 7;
  const cells = [];
  for (let i = 0; i < mondayBasedOffset; i += 1) {
    cells.push('<button type="button" class="day-cell muted" aria-hidden="true" tabindex="-1"></button>');
  }

  for (let day = 1; day <= monthEnd.getDate(); day += 1) {
    const date = new Date(monthStart.getFullYear(), monthStart.getMonth(), day);
    const isoDate = toIsoDate(date);
    const inRange = isoDate >= state.minDate && isoDate <= state.maxDate;
    const hasAvailability = inRange && availableDates.has(isoDate);
    const isSelected = isoDate === state.selectedDate;

    const classes = ['day-cell'];
    if (hasAvailability) classes.push('available');
    if (isSelected) classes.push('selected');

    cells.push(`
      <button type="button" class="${classes.join(' ')}" data-date="${isoDate}" ${hasAvailability ? '' : 'disabled'}>${day}</button>
    `);
  }

  calendarGrid.innerHTML = cells.join('');

  const prevMonth = firstDayOfMonth(addMonths(state.monthCursor, -1));
  const nextMonth = firstDayOfMonth(addMonths(state.monthCursor, 1));
  prevMonthButton.disabled = toIsoDate(lastDayOfMonth(prevMonth)) < state.minDate;
  nextMonthButton.disabled = toIsoDate(firstDayOfMonth(nextMonth)) > state.maxDate;
}

function renderSlots() {
  if (!state.selectedDate) {
    selectedDateText.textContent = '-';
    slotsGrid.innerHTML = '';
    slotFeedback.textContent = 'Kies eerst een datum met beschikbaarheid.';
    updateSaveState();
    return;
  }

  const slots = state.dayAvailability.get(state.selectedDate) || [];
  selectedDateText.textContent = fullDateFormatter.format(parseIsoDate(state.selectedDate));

  if (!slots.length) {
    slotsGrid.innerHTML = '';
    slotFeedback.textContent = 'Geen tijdsloten beschikbaar op deze dag.';
    state.selectedTime = null;
    state.selectedAdvisorIds = [];
    updateSaveState();
    return;
  }

  slotsGrid.innerHTML = slots.map((slot) => {
    const selectedClass = slot.time === state.selectedTime ? 'selected' : '';
    return `<button type="button" class="slot ${selectedClass}" data-time="${slot.time}">${slot.time}</button>`;
  }).join('');

  slotFeedback.textContent = '';
  updateSaveState();
}

function updateSaveState() {
  const ready = Boolean(state.selectedDate && state.selectedTime && state.selectedAdvisorIds.length && !state.saving);
  saveBtn.disabled = !ready;
}

async function refreshMonth() {
  await preloadMonthAvailability();

  const monthStart = firstDayOfMonth(state.monthCursor);
  const monthEnd = lastDayOfMonth(state.monthCursor);
  const availableDatesInMonth = [...getMonthAvailabilityDates()]
    .filter((date) => date >= toIsoDate(monthStart) && date <= toIsoDate(monthEnd))
    .sort();

  if (!state.selectedDate || !availableDatesInMonth.includes(state.selectedDate)) {
    state.selectedDate = availableDatesInMonth[0] || null;
    state.selectedTime = null;
  }

  renderCalendar();
  renderSlots();
}

async function verifyPincode(pincode) {
  const response = await fetch('/api/wijziging/verifieer-pincode', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ afspraak_id: afspraakId, pincode })
  });

  const rawBody = await response.text();
  let responseBody = null;
  if (rawBody) {
    try {
      responseBody = JSON.parse(rawBody);
    } catch {
      responseBody = rawBody;
    }
  }

  if (!response.ok) {
    const message = responseBody && typeof responseBody === 'object' && responseBody.error
      ? responseBody.error
      : 'Pincode-verificatie mislukt.';
    throw new Error(message);
  }

  return responseBody;
}

async function saveWijziging() {
  const advisorIds = state.selectedAdvisorIds
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
  const primaryAdvisorId = advisorIds[0];

  const response = await fetch('/api/wijziging/opslaan', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      afspraak_id: afspraakId,
      pincode: state.pincode,
      adviseur_id: primaryAdvisorId,
      datum: state.selectedDate,
      tijd: state.selectedTime,
      duur_kwartieren: state.duurKwartieren,
      vorm_afspraak: state.vormAfspraak,
      run: state.run
    })
  });

  const rawBody = await response.text();
  let responseBody = null;
  if (rawBody) {
    try {
      responseBody = JSON.parse(rawBody);
    } catch {
      responseBody = rawBody;
    }
  }

  if (!response.ok) {
    const message = responseBody && typeof responseBody === 'object' && responseBody.error
      ? responseBody.error
      : 'Wijziging opslaan is mislukt.';
    throw new Error(message);
  }

  return responseBody;
}

function bindEvents() {
  pincodeForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    pincodeFeedback.textContent = '';

    if (!afspraakId) {
      pincodeFeedback.textContent = 'Ontbrekende afspraak_id in de link.';
      return;
    }

    const formData = new FormData(pincodeForm);
    const pincode = String(formData.get('pincode') || '').trim();
    if (!/^\d{6}$/.test(pincode)) {
      pincodeFeedback.textContent = 'Vul de 6-cijferige pincode in.';
      return;
    }

    verifyBtn.disabled = true;
    pincodeFeedback.textContent = 'Verifiëren...';

    try {
      const result = await verifyPincode(pincode);
      state.pincode = pincode;
      state.run = result.run || 'test';
      state.duurKwartieren = Number(result.duur_kwartieren) || 3;
      state.vormAfspraak = result.vorm_afspraak || 'online';
      state.postcode = result.postcode || null;

      pincodeStep.classList.add('hidden');
      calendarStep.classList.remove('hidden');

      const today = new Date();
      const maxDate = addDays(today, 12 * 7);
      state.minDate = toIsoDate(today);
      state.maxDate = toIsoDate(maxDate);
      state.monthCursor = firstDayOfMonth(today);

      await refreshMonth();
    } catch (error) {
      pincodeFeedback.textContent = error.message;
    } finally {
      verifyBtn.disabled = false;
    }
  });

  prevMonthButton.addEventListener('click', async () => {
    state.monthCursor = firstDayOfMonth(addMonths(state.monthCursor, -1));
    state.selectedTime = null;
    await refreshMonth();
  });

  nextMonthButton.addEventListener('click', async () => {
    state.monthCursor = firstDayOfMonth(addMonths(state.monthCursor, 1));
    state.selectedTime = null;
    await refreshMonth();
  });

  calendarGrid.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-date]');
    if (!button || button.disabled) {
      return;
    }
    state.selectedDate = button.dataset.date;
    state.selectedTime = null;
    renderCalendar();
    renderSlots();
  });

  slotsGrid.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-time]');
    if (!button) {
      return;
    }
    state.selectedTime = button.dataset.time;
    const slot = (state.dayAvailability.get(state.selectedDate) || []).find((item) => item.time === state.selectedTime);
    state.selectedAdvisorIds = slot ? slot.advisorIds : [];
    renderSlots();
  });

  saveBtn.addEventListener('click', async () => {
    state.saving = true;
    updateSaveState();
    saveFeedback.textContent = 'Opslaan...';

    try {
      await saveWijziging();
      saveFeedback.textContent = 'Uw afspraak is gewijzigd.';
      saveBtn.disabled = true;
    } catch (error) {
      state.saving = false;
      saveFeedback.textContent = error.message;
      updateSaveState();
    }
  });
}

bindEvents();

if (!afspraakId) {
  pincodeFeedback.textContent = 'Ontbrekende afspraak_id in de link.';
  verifyBtn.disabled = true;
}
```

- [ ] **Step 4: Syntax-check**

```bash
node --check public/wijzig-afspraak.js
```

Expected: geen output (slaagt).

- [ ] **Step 5: Verifieer handmatig in de browser**

Met `npm start` en AfspraakMaken's `func start` beide actief, open:

```
http://localhost:3001/wijzig-afspraak.html?afspraak_id=999999
```

Vul de echte pincode in (opnieuw aangevraagd via Taak 2's curl), verifieer dat de kalender verschijnt met
beschikbare dagen, kies een datum/tijd, klik Opslaan. Expected: (tot de SP bestaat) een foutmelding die
verwijst naar de ontbrekende `spWijzigAfspraakDatumTijd` — dat bevestigt dat de hele keten tot en met de
laatste stap werkt.

- [ ] **Step 6: Commit**

```bash
git add public/wijzig-afspraak.html public/wijzig-afspraak.css public/wijzig-afspraak.js
git commit -m "feat: wijzig-afspraak.html pagina voor klant-facing afspraak-wijziging"
```

---

## Taak 8: Documentatie AgendaPicker bijwerken

**Files:**
- Modify: `README.md`
- Modify: `docs/TODO.md`
- Modify: `docs/DECISIONS.md`

**Interfaces:** geen (documentatie-only).

- [ ] **Step 1: `README.md` uitbreiden**

Voeg, direct na de env-var-regel `AFSPRAAK_AVAILABILITY_URL=...` in sectie "2) Benodigde
omgevingsvariabelen", twee regels toe:

```
AFSPRAAK_WIJZIG_VERIFICATIE_URL=https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net/wijzig-verificatie
AFSPRAAK_WIJZIG_OPSLAAN_URL=https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net/wijzig-opslaan
```

Voeg daarna, in sectie "3) API-overzicht", ná de bestaande `### POST /api/reservering`-sectie, een nieuwe
sectie toe:

```markdown
### `POST /api/wijziging/verifieer-pincode`
Controleert een pincode die de klant per e-mail heeft ontvangen (zie AfspraakMaken's
`/wijzig-aanvraag`-endpoint). Stuurt door naar `AFSPRAAK_WIJZIG_VERIFICATIE_URL`.

Body:
- `afspraak_id` (**verplicht**)
- `pincode` (**verplicht**, 6 cijfers)

Bij succes retourneert het endpoint `adviseur_id`, `duur_kwartieren`, `vorm_afspraak`, `postcode`, `run`
uit het pincode-record — dit vult de kalender in `wijzig-afspraak.html`.

### `POST /api/wijziging/opslaan`
Slaat de nieuw gekozen datum/tijd/adviseur/vorm op voor een afspraak. Stuurt door naar
`AFSPRAAK_WIJZIG_OPSLAAN_URL`. Vereist een geldige, nog niet verlopen pincode (zelfde als hierboven).

Body:
- `afspraak_id`, `pincode` (**verplicht**)
- `adviseur_id` (positieve integer, **verplicht**)
- `datum` (`YYYY-MM-DD`, **verplicht**)
- `tijd` (`HH:mm`, **verplicht**)
- `duur_kwartieren` (positieve integer, **verplicht**)
- `vorm_afspraak` (`online`/`buitendienst`, **verplicht**)
- `run` (`test|prod`, optioneel; fallback `test`)
```

Voeg tot slot, in sectie "4) Frontendgedrag" of een nieuwe sectie ernaast, één regel toe die
`/wijzig-afspraak.html` vermeldt als de klant-facing pagina die deze twee endpoints gebruikt (geopend via
de link in de pincode-mail, niet embedded via iframe).

- [ ] **Step 2: `docs/TODO.md` bijwerken**

Voeg toe:

```
- [ ] `spWijzigAfspraakDatumTijd` moet in SQL Server bestaan voordat de wijzig-afspraak-flow
  end-to-end getest kan worden (zie AfspraakMaken's `docs/TODO.md` en
  `docs/superpowers/specs/2026-09-03-wijzig-afspraak-pincode-design.md` in AfspraakMaken).
- [ ] `AFSPRAAK_WIJZIG_VERIFICATIE_URL`/`AFSPRAAK_WIJZIG_OPSLAAN_URL` in productie-App-Settings zetten.
```

- [ ] **Step 3: `docs/DECISIONS.md` — nieuwe ADR toevoegen**

Voeg onderaan (append-only) toe:

```

## 2026-09-03 — Nieuwe pagina wijzig-afspraak.html hergebruikt de bestaande beschikbaarheids-kalender

**Context:** klanten moeten een bestaande afspraak kunnen wijzigen via een gemailde pincode
(AfspraakMaken-kant, zie de ADR van dezelfde datum in dat project). AgendaPicker moest hiervoor een nieuwe,
niet-embedded pagina krijgen.

**Beslissing:** `public/wijzig-afspraak.html` (+ .css/.js) is een nieuw, op zichzelf staand drietal (geen
iframe-embed, geen postMessage-config) dat de kalender/tijdslot-logica van `horizontal.js` hergebruikt
tegen het bestaande `/api/availability`, met `duur_kwartieren`/`vorm_afspraak`/`postcode` als vaste
filters uit de pincode-verificatie-respons — `adviseur_id` staat niet vast, de klant kan dus een andere
adviseur/tijdslot kiezen dan de oorspronkelijke afspraak. Twee nieuwe dunne proxy-routes
(`/api/wijziging/verifieer-pincode`, `/api/wijziging/opslaan`) volgen hetzelfde patroon als
`/api/reservering`.

**Gevolgen:** nieuwe env vars `AFSPRAAK_WIJZIG_VERIFICATIE_URL`/`AFSPRAAK_WIJZIG_OPSLAAN_URL` nodig in
productie. De flow is pas end-to-end bruikbaar zodra `spWijzigAfspraakDatumTijd` in SQL Server bestaat
(AfspraakMaken-kant).
```

- [ ] **Step 4: Commit**

```bash
git add README.md docs/TODO.md docs/DECISIONS.md
git commit -m "docs: documenteer wijzig-afspraak.html en pincode-proxy-routes"
```
