# Buitendienst-beschikbaarheid in /availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/availability` in `AfspraakMaken/function_app.py` roept, net als `AfspraakPlanner`, de nieuwe stored procedure `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan wanneer `vorm_afspraak=buitendienst` is opgegeven, in plaats van altijd de bestaande `dbo.psAgendaPicker_GetAvailability`.

**Architecture:** Eén nieuwe private helper `_prepare_availability_call(payload)` bepaalt op basis van `vorm_afspraak` welke procedure aangeroepen wordt en levert een (mogelijk lokaal aangepaste) payload terug. Bij `buitendienst` wordt een lokale kopie van de payload gemaakt met een `postcode4`-key erin, zodat `_call_sp_dynamic`'s bestaande matching-logica die automatisch koppelt aan de SP-parameter `@Postcode4`. Het gedeelde alias-mechanisme in `_build_value_lookup` (dat ook `/reservering` gebruikt) wordt niet aangeraakt.

**Tech Stack:** Python (Azure Functions v2, `azure-functions`, `pyodbc`), geen testframework aanwezig in de repo — verificatie gebeurt via een directe, DB-onafhankelijke aanroep van de nieuwe pure-Python helper.

**Spec:** Geen apart specbestand — dit is een *bounded* wijziging (brainstorming-skill), het ontwerp is in de chatsessie gepresenteerd en goedgekeurd. Samenvatting:
- Alleen `AfspraakMaken/function_app.py` wijzigt.
- `vorm_afspraak` moet `"online"` (default) of `"buitendienst"` zijn, anders HTTP 400 — zelfde regel als `AfspraakPlanner`.
- Bij `"buitendienst"` moet `postcode` exact 4 cijfers zijn, anders HTTP 400 — zelfde regel als `AfspraakPlanner`.
- Procedurekeuze: `psAgendaPicker_GetAvailability` (online) of `psAgendaPicker_GetAvailabilityBuitendienst` (buitendienst).
- `postcode` uit de payload wordt lokaal ook als `postcode4` aangeboden aan `_call_sp_dynamic`, zonder het gedeelde alias-mechanisme te wijzigen.

## Global Constraints

- Geen directe SQL INSERT/UPDATE — alle DB-writes lopen via stored procedures (bestaande regel, niet van toepassing op deze read-only wijziging maar wel op de bredere codebase).
- Het gedeelde dynamische matching-mechanisme (`_build_value_lookup`, gebruikt door zowel `/reservering` als `/availability`) mag niet wijzigen.
- Domeinbegrippen in het Nederlands (`vorm_afspraak`, `postcode`), consistent met de rest van `function_app.py`.
- Één bestand tegelijk (`function_app.py`) — geen gelegenheids-refactor van andere routes.

---

### Task 1: `_prepare_availability_call` helper + wiring in `_handle_availability`

**Files:**
- Modify: `function_app.py:730-794` (functie `_handle_availability` en de regels erboven)

**Interfaces:**
- Produces: `_prepare_availability_call(payload: dict) -> tuple[str, dict]` — geeft `(procedure_name, sp_payload)` terug, of gooit `ValidationError` bij een ongeldige `vorm_afspraak` of `postcode`.
- Consumes: bestaande `ValidationError`, `_call_sp_dynamic`, `re` (al geïmporteerd, regel 4).

- [ ] **Step 1: Baseline vaststellen (huidig gedrag zonder de wijziging)**

  Bevestig met een korte code-lezing dat `_handle_availability` momenteel *altijd* `"psAgendaPicker_GetAvailability"` aanroept, ongeacht `vorm_afspraak` (regel 747: `sp_result = _call_sp_dynamic(cursor, "dbo", "psAgendaPicker_GetAvailability", payload)`). Dit is de bug/gap die dit plan oplost — geen testframework aanwezig, dus dit dient als het "voor"-beeld in plaats van een falende test.

- [ ] **Step 2: Voeg `_prepare_availability_call` toe, vlak vóór `_handle_availability` (rond regel 729)**

```python
def _prepare_availability_call(payload: dict) -> tuple[str, dict]:
    vorm_afspraak = str(payload.get("vorm_afspraak") or "online").strip().lower()

    if vorm_afspraak not in {"online", "buitendienst"}:
        raise ValidationError("Parameter 'vorm_afspraak' moet 'online' of 'buitendienst' zijn.")

    if vorm_afspraak == "buitendienst":
        postcode = str(payload.get("postcode") or "").strip()
        if not re.fullmatch(r"\d{4}", postcode):
            raise ValidationError("Parameter 'postcode' moet uit exact 4 cijfers bestaan.")

        sp_payload = dict(payload)
        sp_payload.setdefault("postcode4", postcode)
        return "psAgendaPicker_GetAvailabilityBuitendienst", sp_payload

    return "psAgendaPicker_GetAvailability", payload
```

- [ ] **Step 3: Verifieer de helper direct (DB-onafhankelijk, geen testframework nodig)**

  Run vanuit de projectmap (met de venv actief, of `.venv\Scripts\python.exe`):

  ```bash
  python -c "
from function_app import _prepare_availability_call, ValidationError

proc, payload = _prepare_availability_call({'date': '2026-09-07'})
assert proc == 'psAgendaPicker_GetAvailability', proc
assert payload == {'date': '2026-09-07'}, payload

proc, payload = _prepare_availability_call({'date': '2026-09-07', 'vorm_afspraak': 'buitendienst', 'postcode': '1234'})
assert proc == 'psAgendaPicker_GetAvailabilityBuitendienst', proc
assert payload['postcode4'] == '1234', payload
assert payload['postcode'] == '1234', payload

try:
    _prepare_availability_call({'vorm_afspraak': 'buitendienst', 'postcode': 'abcd'})
    raise SystemExit('FOUT: verwachtte ValidationError voor ongeldige postcode')
except ValidationError:
    pass

try:
    _prepare_availability_call({'vorm_afspraak': 'fiets'})
    raise SystemExit('FOUT: verwachtte ValidationError voor ongeldige vorm_afspraak')
except ValidationError:
    pass

print('OK: alle vier de gevallen gedragen zich zoals verwacht')
"
  ```

  Expected: `OK: alle vier de gevallen gedragen zich zoals verwacht` — geen `AssertionError`, geen `FOUT:`-regel.

  **Let op:** het importeren van `function_app.py` voert `func.FunctionApp(...)` uit (module-niveau, regel 10) — dit heeft geen DB- of netwerktoegang nodig en faalt dus niet zonder `local.settings.json`.

- [ ] **Step 4: Wire de helper in `_handle_availability` (vervang regel 733-747)**

  Vervang:

  ```python
    try:
        payload = _extract_request_payload(req)
    except ValidationError as ex:
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
        sp_result = _call_sp_dynamic(cursor, "dbo", "psAgendaPicker_GetAvailability", payload)
        conn.commit()
  ```

  Door:

  ```python
    try:
        payload = _extract_request_payload(req)
        procedure_name, sp_payload = _prepare_availability_call(payload)
    except ValidationError as ex:
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
        sp_result = _call_sp_dynamic(cursor, "dbo", procedure_name, sp_payload)
        conn.commit()
  ```

  Laat de rest van `_handle_availability` (response-opbouw, foutafhandeling, `finally`-block) ongewijzigd — `payload` (niet `sp_payload`) blijft gebruikt in de `"input"`-key van de succesresponse, zodat de response altijd toont wat de aanroeper daadwerkelijk stuurde.

- [ ] **Step 5: Syntax-check van het volledige bestand**

  Run: `python -m py_compile function_app.py`
  Expected: geen output, exit code 0.

- [ ] **Step 6: Herhaal Step 3's verificatie tegen het gewijzigde bestand**

  Run dezelfde `python -c "..."`-snippet uit Step 3 nogmaals. Expected: zelfde `OK`-regel — bevestigt dat de wiring in Step 4 de helper niet gebroken heeft.

- [ ] **Step 7: Commit**

```bash
git add function_app.py
git commit -m "feat: roep psAgendaPicker_GetAvailabilityBuitendienst aan bij vorm_afspraak=buitendienst"
```

---

### Task 2: Documentatie bijwerken

**Files:**
- Modify: `docs/DECISIONS.md` (append-only, nieuwe ADR onderaan)
- Modify: `docs/TODO.md` (nieuw actiepunt)

**Interfaces:**
- Consumes: geen — pure documentatiewijziging, geen code-afhankelijkheden.

- [ ] **Step 1: Append ADR aan `docs/DECISIONS.md`**

  Voeg onderaan het bestand toe (na de bestaande entry van 2026-08-25):

```markdown

## 2026-09-01 — Buitendienst-beschikbaarheid in /availability zonder het gedeelde alias-mechanisme te wijzigen

**Context:** `AfspraakPlanner` (een apart project) riep al `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan voor `vorm_afspraak=buitendienst`, maar `AfspraakMaken`'s `/availability`-endpoint deed dat nog niet — die riep altijd de vaste `psAgendaPicker_GetAvailability` aan via `_call_sp_dynamic`. De nieuwe Buitendienst-SP verwacht `@Postcode4`, terwijl de inkomende payload (vanuit AgendaPicker) de key `postcode` gebruikt. `_call_sp_dynamic`'s gedeelde matching-logica (`_build_value_lookup`) wordt ook door `/reservering` gebruikt, en CLAUDE.md waarschuwt expliciet om dat mechanisme niet te wijzigen zonder de gevolgen voor beide endpoints te overzien.

**Beslissing:** in plaats van het gedeelde alias-mechanisme uit te breiden, bouwt een nieuwe helper `_prepare_availability_call` een lokale kopie van de payload met een `postcode4`-key erin, uitsluitend binnen `_handle_availability`. `/reservering` en zijn alias-mechanisme blijven volledig ongewijzigd. Welke stored procedure wordt aangeroepen (`psAgendaPicker_GetAvailability` vs. `psAgendaPicker_GetAvailabilityBuitendienst`) hangt af van `vorm_afspraak`, met dezelfde validatie als `AfspraakPlanner` (`vorm_afspraak` moet `'online'`/`'buitendienst'` zijn; `postcode` moet 4 cijfers zijn bij buitendienst).

**Gevolgen:** `/availability` ondersteunt nu zowel online- als buitendienst-beschikbaarheid, consistent met `AfspraakPlanner`'s implementatie. `psAgendaPicker_GetAvailabilityBuitendienst` moet nog op `Advitas_test`/productie uitgevoerd worden voordat dit end-to-end getest kan worden (zie `docs/TODO.md`) — tot die tijd geeft de buitendienst-tak een databasefout terug (procedure niet gevonden, of een rechten-gerelateerde fout als de procedure wel bestaat maar de gebruikte databasegebruiker er geen toegang toe heeft).
```

- [ ] **Step 2: Voeg actiepunt toe aan `docs/TODO.md`**

  Voeg toe aan de lijst:

```markdown
- [ ] `/availability` roept nu ook `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan bij `vorm_afspraak=buitendienst` (zie `docs/DECISIONS.md`, 2026-09-01). Deze SP staat nog niet op `Advitas_test`/productie (zie `AfspraakPlanner/docs/TODO.md`) — voer eerst het `CREATE OR ALTER PROCEDURE`-script uit en controleer of de databasegebruiker die `AfspraakMaken` gebruikt EXECUTE-rechten heeft op deze SP en SELECT-rechten op `PowerBI.AdviseurRegio`, vóór een end-to-end test tegen `SQL_DATABASE_TEST`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/DECISIONS.md docs/TODO.md
git commit -m "docs: leg buitendienst-availability-beslissing vast en noteer deploy-blocker"
```
