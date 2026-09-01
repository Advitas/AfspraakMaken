# Reservering-emailnotificatie naar planning@advitas.nl Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bij elke succesvolle `/reservering`-aanroep (zowel het dynamische als het fallback-pad) stuurt `AfspraakMaken` via Microsoft Graph een nette HTML-mail naar `planning@advitas.nl` met het reserveringsnummer en overige relevante gegevens, zodat het planningsteam actie kan ondernemen.

**Architecture:** Drie nieuwe, losse helpers in `function_app.py`: een Graph-authenticatiehelper (client-credentials-flow, spiegelt `PhytonFuncties/sharepoint_pdf_sync.py`), een pure content-bouwer (geen I/O, dus los testbaar), en een verzendhelper die beide combineert en naar Graph's `sendMail`-endpoint post. Een dunne, apart testbare non-blocking wrapper zorgt dat een mislukte mail nooit de `/reservering`-response beïnvloedt. De mail wordt altijd verstuurd (test én productie), met een `[TEST]`-prefix in het onderwerp en een waarschuwingsbanner in de body wanneer `run` niet naar productie resolveert.

**Tech Stack:** Python, nieuwe dependency `requests` (HTTP naar Microsoft Graph), Microsoft Graph `sendMail` REST-API, OAuth2 client-credentials-flow tegen `login.microsoftonline.com`.

**Spec:** Geen apart specbestand — *bounded* wijziging (brainstorming-skill), ontwerp in de chatsessie gepresenteerd en goedgekeurd. Samenvatting:
- Verzendmechanisme: Microsoft Graph API, credentials hergebruikt van dezelfde app-registratie als `PhytonFuncties/sharepoint_pdf_sync.py` (env-vars `SHAREPOINT_TENANT_ID`/`SHAREPOINT_CLIENT_ID`/`SHAREPOINT_CLIENT_SECRET`, met `AZURE_TENANT_ID`/`AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET` als fallback-namen).
- Afzender = ontvanger: `planning@advitas.nl` (self-notification).
- Non-blocking: een mislukte mail faalt de `/reservering`-aanroep nooit; alleen loggen.
- Geldt voor zowel het dynamische SP-pad als het fallback-pad van `/reservering`.
- Altijd versturen, ook bij `run` != `prod` (testruns) — met `[TEST]`-prefix in onderwerp + waarschuwingsbanner in de body om verwarring met echte reserveringen te voorkomen.
- Inhoud: reserveringsnummer prominent, plus datum/tijd/adviseur_id/duur_kwartieren (gegarandeerd aanwezig in de payload, afgedwongen door `_validate_make_reservation_payload`), plus klant_id/campagne_id/campagne_naam/naam/email waar beschikbaar, plus een vangnet voor overige SP-output-velden.

## Global Constraints

- Geen directe SQL INSERT/UPDATE — niet van toepassing op deze wijziging (geen nieuwe databasebewerkingen), maar wel op de bredere codebase.
- Non-blocking: falen van de mail-stap mag de `/reservering`-response nooit veranderen.
- Domeinbegrippen in het Nederlands (`reservering_id`, `adviseur_id`, etc.), consistent met de rest van `function_app.py`.
- Eén bestand tegelijk (`function_app.py`) — geen gelegenheids-refactor van andere routes.
- Secrets nooit hardcoded — alleen via environment variables, nooit gelogd of in de response.

---

### Task 1: Dependency + Graph-authenticatiehelper

**Files:**
- Modify: `requirements.txt`
- Modify: `function_app.py` (imports bovenaan, nieuwe helpers vlak vóór `_call_sp_maak_afspraak`, rond regel 203)

**Interfaces:**
- Produces: `_require_any_env(*names: str) -> str` — geeft de waarde van de eerste gezette env-var terug, of gooit `RuntimeError` als geen enkele gezet is.
- Produces: `_get_graph_access_token() -> str` — haalt een Microsoft Graph access token op via client-credentials-flow. Gooit `RuntimeError` bij een niet-200-statuscode.

- [ ] **Step 1: Voeg `requests` toe aan `requirements.txt`**

Huidige inhoud:
```
azure-functions
pyodbc
```

Nieuwe inhoud:
```
azure-functions
pyodbc
requests
```

- [ ] **Step 2: Installeer de nieuwe dependency**

Run: `.venv\Scripts\python.exe -m pip install -r requirements.txt`
Expected: `Successfully installed ... requests-...` (of "Requirement already satisfied" als een andere library 'm al meebracht).

- [ ] **Step 3: Voeg de imports toe bovenaan `function_app.py`**

Huidige top van het bestand (regel 1-8):
```python
import json
import logging
import os
import re
from datetime import date, time

import azure.functions as func
import pyodbc
```

Nieuwe versie:
```python
import html
import json
import logging
import os
import re
from datetime import date, time

import azure.functions as func
import pyodbc
import requests
```

- [ ] **Step 4: Voeg `_require_any_env` en `_get_graph_access_token` toe, vlak vóór `_call_sp_maak_afspraak` (rond regel 203)**

```python
def _require_any_env(*names: str) -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    raise RuntimeError("Ontbrekende Graph-credential. Zet een van: " + ", ".join(names))


def _get_graph_access_token() -> str:
    tenant_id = _require_any_env("SHAREPOINT_TENANT_ID", "AZURE_TENANT_ID")
    client_id = _require_any_env("SHAREPOINT_CLIENT_ID", "AZURE_CLIENT_ID")
    client_secret = _require_any_env("SHAREPOINT_CLIENT_SECRET", "AZURE_CLIENT_SECRET")

    token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    response = requests.post(
        token_url,
        data={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": "https://graph.microsoft.com/.default",
        },
        timeout=15,
    )
    if response.status_code != 200:
        try:
            error_body = response.json()
            err = error_body.get("error")
            err_desc = str(error_body.get("error_description", ""))[:500]
        except ValueError:
            err = response.status_code
            err_desc = response.text[:500]
        raise RuntimeError(f"Microsoft Graph token-fout ({response.status_code}): {err} - {err_desc}")

    return response.json()["access_token"]
```

- [ ] **Step 5: Verifieer `_require_any_env` direct (DB- en netwerk-onafhankelijk)**

Run:
```bash
.venv\Scripts\python.exe -c "
import os
from function_app import _require_any_env

os.environ.pop('TEST_VAR_A', None)
os.environ['TEST_VAR_B'] = 'gevonden'
assert _require_any_env('TEST_VAR_A', 'TEST_VAR_B') == 'gevonden'

os.environ.pop('TEST_VAR_A', None)
os.environ.pop('TEST_VAR_B', None)
try:
    _require_any_env('TEST_VAR_A', 'TEST_VAR_B')
    raise SystemExit('FOUT: verwachtte RuntimeError')
except RuntimeError:
    pass

print('OK: _require_any_env gedraagt zich zoals verwacht')
"
```
Expected: `OK: _require_any_env gedraagt zich zoals verwacht`

**Let op:** `_get_graph_access_token` kan hier niet end-to-end getest worden — dat vereist echte `SHAREPOINT_*`/`AZURE_*`-credentials met `Mail.Send`-rechten, die niet in deze sessie beschikbaar zijn. Dat is een handmatige verificatiestap voor later (zie Task 4).

- [ ] **Step 6: Syntax-check**

Run: `.venv\Scripts\python.exe -m py_compile function_app.py`
Expected: geen output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add requirements.txt function_app.py
git commit -m "feat: voeg Graph-authenticatiehelper toe voor reserverings-mail"
```

---

### Task 2: Pure content-bouwer voor de mail

**Files:**
- Modify: `function_app.py` (nieuwe helper vlak ná `_get_graph_access_token`)

**Interfaces:**
- Consumes: niets van Task 1 behalve dat dit in hetzelfde bestand leeft.
- Produces: `_build_reservering_email(payload: dict, sp_output: dict, run_value) -> tuple[str, str]` — geeft `(subject, html_body)` terug. Latere taken (Task 3) roepen dit aan.

- [ ] **Step 1: Voeg `_build_reservering_email` toe**

```python
def _build_reservering_email(payload: dict, sp_output: dict, run_value) -> tuple[str, str]:
    is_prod = str(run_value).strip().lower() == "prod"

    reservering_id = sp_output.get("reservering_id")
    reservering_label = str(reservering_id) if reservering_id not in (None, "") else "onbekend"

    subject_prefix = "" if is_prod else "[TEST] "
    subject = f"{subject_prefix}Nieuwe reservering #{reservering_label} — actie vereist"

    bekende_velden = [
        ("Reserveringsnummer", sp_output.get("reservering_id")),
        ("Datum", payload.get("datum")),
        ("Tijd", payload.get("tijd")),
        ("Adviseur_id", payload.get("adviseur_id")),
        ("Duur (kwartieren)", payload.get("duur_kwartieren")),
        ("Klant_id", sp_output.get("klant_id")),
        ("Campagne_id", sp_output.get("campagne_id")),
        ("Campagne naam", sp_output.get("campagne_naam")),
        ("Naam", payload.get("naam")),
        ("Email", payload.get("email")),
    ]

    getoonde_output_keys = {"reservering_id", "klant_id", "campagne_id", "campagne_naam"}
    genegeerde_output_keys = getoonde_output_keys | {
        "foutmelding", "foutcode", "fout_stap", "fout_parameter", "fout_waarde", "fout_detailleer",
    }
    overige_velden = [
        (key, value) for key, value in sp_output.items() if key not in genegeerde_output_keys
    ]

    def _rij(label, waarde) -> str:
        weergave = html.escape(str(waarde)) if waarde not in (None, "") else "&mdash;"
        return (
            "<tr>"
            f'<td style="padding:6px 12px;border-bottom:1px solid #e5e5e5;font-weight:bold;'
            f'white-space:nowrap;">{html.escape(str(label))}</td>'
            f'<td style="padding:6px 12px;border-bottom:1px solid #e5e5e5;">{weergave}</td>'
            "</tr>"
        )

    rijen = "".join(_rij(label, waarde) for label, waarde in bekende_velden)
    if overige_velden:
        overige_tekst = ", ".join(f"{key}={value}" for key, value in overige_velden)
        rijen += _rij("Overige gegevens", overige_tekst)

    test_banner = (
        ""
        if is_prod
        else (
            '<p style="color:#b00020;font-weight:bold;">Dit is een TESTreservering '
            "(niet tegen productie) — geen actie ondernemen.</p>"
        )
    )

    html_body = (
        '<div style="font-family:Segoe UI, Arial, sans-serif;color:#222;max-width:600px;">'
        '<h2 style="color:#1a3c6e;">Nieuwe reservering</h2>'
        f"{test_banner}"
        f'<table style="border-collapse:collapse;width:100%;">{rijen}</table>'
        '<p style="color:#888;font-size:12px;margin-top:16px;">'
        "Automatisch gegenereerd door AfspraakMaken bij het aanmaken van een reservering."
        "</p>"
        "</div>"
    )

    return subject, html_body
```

- [ ] **Step 2: Verifieer `_build_reservering_email` direct met representatieve voorbeelddata**

Run:
```bash
.venv\Scripts\python.exe -c "
from function_app import _build_reservering_email

payload = {
    'datum': '2026-09-07', 'tijd': '10:30', 'adviseur_id': '123',
    'duur_kwartieren': 4, 'naam': 'Jan Jansen', 'email': 'jan@example.com',
}
sp_output = {
    'reservering_id': 42, 'klant_id': 7, 'campagne_id': 230,
    'campagne_naam': 'MMJO', 'foutmelding': None, 'foutcode': 0,
}

# Geval 1: productie
subject, body = _build_reservering_email(payload, sp_output, 'prod')
assert subject == 'Nieuwe reservering #42 — actie vereist', subject
assert 'TESTreservering' not in body
assert '42' in body and 'Jan Jansen' in body and 'MMJO' in body
print('Geval 1 (prod) OK')

# Geval 2: testrun
subject, body = _build_reservering_email(payload, sp_output, 'test')
assert subject.startswith('[TEST] '), subject
assert 'TESTreservering' in body
print('Geval 2 (test) OK')

# Geval 3: ontbrekend reserveringsnummer + overig SP-veld
subject, body = _build_reservering_email(
    {'datum': '2026-09-07', 'tijd': '10:30', 'adviseur_id': '1', 'duur_kwartieren': 1},
    {'reservering_id': None, 'extra_kolom': 'iets'},
    'prod',
)
assert '#onbekend' in subject, subject
assert 'extra_kolom=iets' in body, body
print('Geval 3 (ontbrekend/vangnet) OK')

# Geval 4: HTML-escaping van gebruikersinvoer
subject, body = _build_reservering_email(
    {'datum': '2026-09-07', 'tijd': '10:30', 'adviseur_id': '1', 'duur_kwartieren': 1, 'naam': '<script>alert(1)</script>'},
    {'reservering_id': 1},
    'prod',
)
assert '<script>' not in body, body
assert '&lt;script&gt;' in body, body
print('Geval 4 (escaping) OK')
"
```
Expected: vier regels eindigend op `OK`, geen `AssertionError`.

- [ ] **Step 3: Syntax-check**

Run: `.venv\Scripts\python.exe -m py_compile function_app.py`
Expected: geen output, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add function_app.py
git commit -m "feat: voeg pure content-bouwer toe voor reserverings-mail"
```

---

### Task 3: Verzendhelper + non-blocking wiring in /reservering

**Files:**
- Modify: `function_app.py` (nieuwe helpers ná `_build_reservering_email`; wiring in de `reservering()`-route, rond regel 671)

**Interfaces:**
- Consumes: `_get_graph_access_token()` (Task 1), `_build_reservering_email(payload, sp_output, run_value)` (Task 2).
- Produces: `_send_reservering_email(payload: dict, sp_output: dict, run_value) -> None` — verstuurt de mail via Graph, gooit door bij een fout. `_try_send_reservering_email(payload: dict, sp_output: dict, run_value) -> None` — non-blocking wrapper, slikt elke exceptie in en logt 'm.

- [ ] **Step 1: Voeg `_send_reservering_email` en `_try_send_reservering_email` toe, vlak ná `_build_reservering_email`**

```python
def _send_reservering_email(payload: dict, sp_output: dict, run_value) -> None:
    sender = "planning@advitas.nl"
    subject, html_body = _build_reservering_email(payload, sp_output, run_value)
    access_token = _get_graph_access_token()

    response = requests.post(
        f"https://graph.microsoft.com/v1.0/users/{sender}/sendMail",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
        json={
            "message": {
                "subject": subject,
                "body": {"contentType": "HTML", "content": html_body},
                "toRecipients": [{"emailAddress": {"address": sender}}],
            },
            "saveToSentItems": "false",
        },
        timeout=15,
    )
    if response.status_code >= 300:
        raise RuntimeError(f"Graph sendMail-fout ({response.status_code}): {response.text[:500]}")


def _try_send_reservering_email(payload: dict, sp_output: dict, run_value) -> None:
    try:
        _send_reservering_email(payload, sp_output, run_value)
    except Exception:
        logging.exception("Fout bij versturen van reserverings-mail naar planning@advitas.nl")
```

- [ ] **Step 2: Verifieer de non-blocking garantie direct (zonder echte Graph-aanroep)**

Run:
```bash
.venv\Scripts\python.exe -c "
import function_app

def _kapotte_send(payload, sp_output, run_value):
    raise RuntimeError('gesimuleerde Graph-fout')

function_app._send_reservering_email = _kapotte_send

# Mag NIET raisen, ook al gooit _send_reservering_email een RuntimeError
function_app._try_send_reservering_email({'datum': '2026-09-07'}, {'reservering_id': 1}, 'prod')
print('OK: _try_send_reservering_email onderdrukt de fout zoals verwacht')
"
```
Expected: `OK: _try_send_reservering_email onderdrukt de fout zoals verwacht` (geen traceback, geen exit code 1).

- [ ] **Step 3: Wire `_try_send_reservering_email` in de `reservering()`-route, direct ná `conn.commit()` (regel 671), vóór de succes-response**

Vervang (regel 671-686):
```python
        conn.commit()

        return func.HttpResponse(
            json.dumps(
                {
                    "result": "success",
                    "input": payload,
                    "matched_parameters": sp_result["matched_parameters"],
                    "stored_procedure_output": sp_result["output"],
                    "stored_procedure_result": sp_result["result_sets"],
                },
                default=str,
            ),
            status_code=200,
            mimetype="application/json",
        )
```

Door:
```python
        conn.commit()

        _try_send_reservering_email(prepared_payload, sp_output, prepared_payload.get("run"))

        return func.HttpResponse(
            json.dumps(
                {
                    "result": "success",
                    "input": payload,
                    "matched_parameters": sp_result["matched_parameters"],
                    "stored_procedure_output": sp_result["output"],
                    "stored_procedure_result": sp_result["result_sets"],
                },
                default=str,
            ),
            status_code=200,
            mimetype="application/json",
        )
```

Dit ene aanroeppunt dekt zowel het dynamische pad als het fallback-pad van `/reservering` — beide zetten `sp_result`/`sp_output` vóór deze regel, ongeacht welk pad daadwerkelijk werd gebruikt (zie regel 640-648: de `except RuntimeError`-tak op de dynamische aanroep wijst `sp_result` opnieuw toe aan het resultaat van `_call_sp_maak_reservering_fallback`, waarna beide paden dezelfde `sp_output = sp_result.get("output", {})`-regel delen).

- [ ] **Step 4: Syntax-check**

Run: `.venv\Scripts\python.exe -m py_compile function_app.py`
Expected: geen output, exit code 0.

- [ ] **Step 5: Herhaal Task 1 Step 5, Task 2 Step 2 en Task 3 Step 2's verificaties tegen het volledige, gewijzigde bestand**

Run alle drie de losse `python -c "..."`-snippets opnieuw (uit Task 1 Step 5, Task 2 Step 2, Task 3 Step 2).
Expected: dezelfde `OK`-regels als eerder — bevestigt dat de wiring in Step 3 niets heeft gebroken.

- [ ] **Step 6: Commit**

```bash
git add function_app.py
git commit -m "feat: verstuur reserverings-mail naar planning@advitas.nl (non-blocking) bij succesvolle /reservering"
```

---

### Task 4: Documentatie bijwerken

**Files:**
- Modify: `docs/DECISIONS.md` (append-only, nieuwe ADR onderaan)
- Modify: `docs/TODO.md` (nieuw actiepunt)

**Interfaces:**
- Consumes: geen — pure documentatiewijziging.

- [ ] **Step 1: Append ADR aan `docs/DECISIONS.md`**

```markdown

## 2026-09-01 — Emailnotificatie naar planning@advitas.nl bij nieuwe reservering

**Context:** Het planningsteam (planning@advitas.nl) moet handmatig actie ondernemen op elke nieuwe reservering, maar had daar geen automatisch signaal voor. `/reservering` had tot nu toe geen enkele uitgaande afhankelijkheid buiten SQL Server.

**Beslissing:** bij elke succesvolle `/reservering`-aanroep (zowel het dynamische als het fallback-SP-pad) stuurt de functie een HTML-mail naar `planning@advitas.nl` via Microsoft Graph's `sendMail`-API, met dezelfde OAuth2 client-credentials-authenticatie als `PhytonFuncties/sharepoint_pdf_sync.py` (env-vars `SHAREPOINT_TENANT_ID`/`SHAREPOINT_CLIENT_ID`/`SHAREPOINT_CLIENT_SECRET`, met `AZURE_TENANT_ID`/`AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET` als fallback). De mail bevat het reserveringsnummer, kernvelden (datum/tijd/adviseur_id/duur_kwartieren/klant_id/campagne_id/campagne_naam/naam/email) en een vangnet voor overige SP-output-velden. De stap is non-blocking: een mislukte mail (`_try_send_reservering_email`) wordt alleen gelogd en verandert de `/reservering`-response nooit. De mail wordt altijd verstuurd, ook bij testruns (`run` != `prod`) — met een `[TEST]`-prefix in het onderwerp en een waarschuwingsbanner in de body, zodat het planningsteam een testreservering niet aanziet voor een echte.

**Gevolgen:** `/reservering` heeft nu voor het eerst een uitgaande HTTP-afhankelijkheid buiten SQL Server (nieuwe dependency `requests`). De app-registratie die `SHAREPOINT_TENANT_ID`/`CLIENT_ID`/`CLIENT_SECRET` (of `AZURE_*`) vertegenwoordigt moet `Mail.Send`-rechten hebben voor `planning@advitas.nl` — dat is niet in deze sessie geverifieerd of geregeld (geen tenant-toegang). Zonder die rechten faalt het versturen stil (alleen zichtbaar in Application Insights via `logging.exception`), de reservering zelf blijft wél gewoon succesvol.
```

- [ ] **Step 2: Voeg actiepunt toe aan `docs/TODO.md`**

```markdown
- [ ] Reserverings-mail naar planning@advitas.nl (zie `docs/DECISIONS.md`, 2026-09-01) vereist dat de app-registratie achter `SHAREPOINT_TENANT_ID`/`CLIENT_ID`/`CLIENT_SECRET` (of `AZURE_TENANT_ID`/`CLIENT_ID`/`CLIENT_SECRET`) `Mail.Send`-rechten heeft voor `planning@advitas.nl`, en dat die env-vars in de Function App's App Settings staan. Nog niet geverifieerd — controleer via een test-reservering en check of de mail daadwerkelijk aankomt (bij een ontbrekende permissie faalt dit stil; zie Application Insights voor de echte foutmelding).
```

- [ ] **Step 3: Commit**

```bash
git add docs/DECISIONS.md docs/TODO.md
git commit -m "docs: leg reserverings-mail-beslissing vast en noteer benodigde Mail.Send-rechten"
```
