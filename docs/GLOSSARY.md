# Glossary

| Term | Betekenis | Code-referentie |
|---|---|---|
| Klant | Klant/lead waarvoor een afspraak of reservering wordt gemaakt (`klant_id`, 0 = nieuwe klant via SP) | `function_app.py` — `_parse_payload`, `spMaakAfspraak` |
| Adviseur | Financieel/verkoopadviseur die de afspraak uitvoert; kan als losse id, lijst of CSV-string worden meegegeven | `function_app.py` — `_parse_adviseur_ids`, `adviseur_id` |
| Afspraak | Geplande afspraak tussen klant en adviseur, aangemaakt via `spMaakAfspraak` | route `/afspraak`, `_call_sp_maak_afspraak` |
| Reservering | Alternatieve/aparte boeking, aangemaakt via `spMaakReservering` met dynamische parameter-matching | route `/reservering`, `_call_sp_dynamic` |
| Campagne | Marketing-/verkoopcampagne waaraan de afspraak of reservering gekoppeld is | `campagne_id`/`campaign_id`, `campagne_naam` (SP-output) |
| Productcategorie (prodcat) | Categorie van het product waarover het adviesgesprek gaat | `prodcat_id` in `_parse_payload` |
| Adviescategorie (advcat) | Categorie van het gegeven advies | `advcat_id` in `_parse_payload` |
| Insteek | Gespreksinvalshoek/aanpak gekoppeld aan de afspraak — exacte betekenis niet uit de code af te leiden | `insteek_id` in `_parse_payload` — <!-- onbekend — vul aan --> |
| Opportunity | Sales-opportunity die (optioneel) automatisch aangemaakt wordt als er nog geen bestaat | `create_opportunity_if_missing` in `_parse_payload` |
| Vorm afspraak | Manier waarop de afspraak plaatsvindt (bijv. "online") | `vorm_afspraak` in `_parse_payload` |
| `run` | Omgeving-indicator die bepaalt welke database gebruikt wordt: `prod` → `SQL_DATABASE_PROD`, elke andere waarde → `SQL_DATABASE_TEST` | `_resolve_database_for_run` |
| MMJO/funnel | Funnel-identifier, verplicht bij `campagne_id`/`campaign_id` = 230 in `/reservering` | `_validate_make_reservation_payload`, `_prepare_make_reservation_payload` |
| Foutmelding / foutcode | Output-parameters van de stored procedures die een fout binnen de SP zelf signaleren (los van HTTP/pyodbc-fouten) | `_call_sp_maak_afspraak`, `_call_sp_maak_reservering_fallback` |
