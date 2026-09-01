# Decisions (ADR's)

Append-only. Nieuwe beslissingen worden onderaan toegevoegd, niet bewerkt.

**Format per entry:**

```
## YYYY-MM-DD — Titel

**Context:** waarom moest dit besloten worden
**Beslissing:** wat is gekozen
**Gevolgen:** wat betekent dit voor de rest van het project
```

---

## 2026-08-25 — Alle database-writes uitsluitend via stored procedures

**Context:** De Azure Function moet klantafspraken en -reserveringen kunnen aanmaken in SQL Server. Directe INSERT/UPDATE-statements vanuit de functie-code zouden business-logica (bijv. campagne-koppeling, klant-matching, foutafhandeling) dupliceren of laten afwijken van wat elders in het systeem al in de database is vastgelegd.

**Beslissing:** `function_app.py` doet nooit een directe INSERT/UPDATE. Alle writes lopen via stored procedures: `spMaakAfspraak` (vaste parameter-mapping, `_call_sp_maak_afspraak`) en `spMaakReservering` (dynamische parameter-matching via `sys.parameters`, `_call_sp_dynamic`). `psAgendaPicker_GetAvailability` wordt op dezelfde dynamische manier aangeroepen voor het ophalen van beschikbaarheid. Dit is expliciet vastgelegd in `README.txt`.

**Gevolgen:** Elke nieuwe of gewijzigde databasebewerking moet als stored procedure worden geïmplementeerd/aangepast in SQL Server, niet als inline SQL in Python. De Python-laag blijft daarmee een dunne aanroep-/validatielaag; schemawijzigingen en business-regels leven in de database, buiten deze repo.

## 2026-09-01 — Buitendienst-beschikbaarheid in /availability zonder het gedeelde alias-mechanisme te wijzigen

**Context:** `AfspraakPlanner` (een apart project) riep al `dbo.psAgendaPicker_GetAvailabilityBuitendienst` aan voor `vorm_afspraak=buitendienst`, maar `AfspraakMaken`'s `/availability`-endpoint deed dat nog niet — die riep altijd de vaste `psAgendaPicker_GetAvailability` aan via `_call_sp_dynamic`. De nieuwe Buitendienst-SP verwacht `@Postcode4`, terwijl de inkomende payload (vanuit AgendaPicker) de key `postcode` gebruikt. `_call_sp_dynamic`'s gedeelde matching-logica (`_build_value_lookup`) wordt ook door `/reservering` gebruikt, en CLAUDE.md waarschuwt expliciet om dat mechanisme niet te wijzigen zonder de gevolgen voor beide endpoints te overzien.

**Beslissing:** in plaats van het gedeelde alias-mechanisme uit te breiden, bouwt een nieuwe helper `_prepare_availability_call` een lokale kopie van de payload met een `postcode4`-key erin, uitsluitend binnen `_handle_availability`. `/reservering` en zijn alias-mechanisme blijven volledig ongewijzigd. Welke stored procedure wordt aangeroepen (`psAgendaPicker_GetAvailability` vs. `psAgendaPicker_GetAvailabilityBuitendienst`) hangt af van `vorm_afspraak`, met dezelfde validatie als `AfspraakPlanner` (`vorm_afspraak` moet `'online'`/`'buitendienst'` zijn; `postcode` moet 4 cijfers zijn bij buitendienst).

**Gevolgen:** `/availability` ondersteunt nu zowel online- als buitendienst-beschikbaarheid, consistent met `AfspraakPlanner`'s implementatie. `psAgendaPicker_GetAvailabilityBuitendienst` moet nog op `Advitas_test`/productie uitgevoerd worden voordat dit end-to-end getest kan worden (zie `docs/TODO.md`) — tot die tijd geeft de buitendienst-tak een databasefout terug (procedure niet gevonden, of een rechten-gerelateerde fout als de procedure wel bestaat maar de gebruikte databasegebruiker er geen toegang toe heeft).
