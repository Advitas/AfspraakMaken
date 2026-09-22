# Ontwerp: funnel-endpoint voor de FunnelKnop

**Datum:** 2026-09-22
**Status:** ter review
**Route:** B (kleine feature), inline uitgevoerd

## Aanleiding

`POST /api/funnel-afspraak` in het AgendaPicker-project geeft een HTTP 500 met
`AFSPRAAK_FUNNEL_URL is niet geconfigureerd.` De omgevingsvariabele is leeg omdat er nooit een
endpoint is gebouwd om naar te wijzen: `function_app.py` kent `reservering`, `availability`,
`afspraak`, `wijzig_aanvraag`, `wijzig_verificatie` en `wijzig_opslaan`, maar geen funnel-route.

Dit staat als openstaand punt in `AgendaPicker/docs/TODO.md:360-373`: de FunnelKnop is
code-compleet, maar `spFunnelCreateOrCheck.sql` is nooit tegen een database uitgevoerd en het
ontvangende endpoint bestaat niet.

## Doel

Een klik op de FunnelKnop moet de funnel-inzending vastleggen, de klant en het product aanmaken
(of hergebruiken), én een reservering maken op de gekozen datum, tijd en adviseur.

## Gekozen aanpak

Een nieuw endpoint `POST /api/funnel` in AfspraakMaken dat twee stored procedures achter elkaar
aanroept:

1. `dbo.spFunnelCreateOrCheck` — slaat de funnel-JSON op in `dbo.Funnel`, maakt of hergebruikt de
   klant, maakt het product aan, en geeft `@klant_id` terug als OUTPUT-parameter.
2. `dbo.spMaakReservering` — maakt de reservering met dat `klant_id` plus `datum`, `tijd`,
   `adviseur_id`, `duur_kwartieren` en `campagne_id`.

### Overwogen alternatief

De bestaande MMJO-hook in `spMaakReservering` (`sql/spMaakReservering.sql:90`) doet deze
orkestratie al, maar hardgecodeerd op `@campagne_id = 230`. Die voorwaarde verbreden naar "er is een
`@funnel` en een `@route`" zou geen nieuw endpoint vergen en geen Python-wijziging, omdat
`/reservering` parameters dynamisch matcht via `sys.parameters`.

Dat alternatief is besproken en afgewezen: het raakt de stored procedure waar alle live
reserveringen doorheen lopen. De keuze voor een apart endpoint houdt dat risico buiten de
bestaande flow, tegen de prijs van een tweede aanroeppad dat apart onderhouden moet worden.

## Wijzigingen aan `spFunnelCreateOrCheck`

De procedure noemt zichzelf generiek, maar de productconfiguratie erin is MMJO-specifiek
(regels 49-53): productnaam `meermetjeoverwaarde.nl`, verzekeraar 33, hoofdbranche 51,
intermediair 602. Zonder wijziging krijgt elke funnel — schade, hypotheek — een product met de
MMJO-productnaam.

Deze vier waarden worden parameters met de huidige waarden als default:

```sql
@productnaam      NVARCHAR(255) = N'meermetjeoverwaarde.nl',
@verzekeraar_id   INT           = 33,
@hoofdbranche_id  INT           = 51,
@intermediair_id  INT           = 602
```

`@intermediair_id` vult zowel `intermediair_ID` als `Hoofdintermediair`, die vandaag allebei op 602
staan via twee aparte variabelen.

Een aanroeper die niets meegeeft, gedraagt zich dus exact als nu. Dit is geen gedragswijziging voor
bestaande data, want de procedure is nog nooit uitgevoerd.

## Contract van het endpoint

`POST /api/funnel`, function-level key, JSON in en uit.

### Verplichte velden

| Veld | Type | Opmerking |
| --- | --- | --- |
| `datum` | string | `YYYY-MM-DD` |
| `tijd` | string | `HH:mm` |
| `adviseur_id` | string | mag een komma-lijst zijn, zoals bij `/reservering` |
| `duur_kwartieren` | int | > 0 |
| `campagne_id` | int | ook geaccepteerd als `campaign_id` |
| `route` | string | vrij label, komt op de `dbo.Funnel`-rij |
| `funnel` | string | JSON-tekst met de funnel-data |
| `run` | string | `test` of `prod`, bepaalt welke database |

### Optionele velden

`klant_id` (0 of leeg betekent: klant opzoeken of aanmaken), `productnaam`, `verzekeraar_id`,
`hoofdbranche_id`, `intermediair_id`, `vorm_afspraak`, `naam`, `email`, `informatie`.

`server.js` stuurt het hele request-body ongewijzigd door en vult daar `datum`, `tijd`,
`duur_kwartieren`, `campagne_id`, `adviseur_id`, `klant_id`, `route`, `funnel` en `run` overheen, dus
alle verplichte velden komen binnen zoals hierboven beschreven.

### Antwoord

```json
{
  "result": "success",
  "klant_id": 123456,
  "funnel_output": { "klant_id": 123456 },
  "reservering_output": { "reservering_id": 789, "campagne_naam": "...", "foutcode": 0 }
}
```

Bij een fout: status 500 met `error` en de output van de procedure die faalde, in dezelfde vorm als
`/reservering` dat vandaag doet.

## Transacties

`_get_connection()` gebruikt `pyodbc.connect()` zonder `autocommit`, dus elke aanroep loopt in een
impliciete transactie die het endpoint zelf moet afsluiten. Dat is bepalend voor dit ontwerp, want
`spFunnelCreateOrCheck` waarschuwt in zijn eigen commentaar dat hij zijn funnel-rij alleen kan
terugzetten na een fout als hij de transactie zelf gestart heeft — en dat is hier niet het geval.

Daarom: **na de funnel-procedure wordt gecommit, vóór de reservering.**

Gevolg, en dit is een bewuste keuze: mislukt de reservering, dan blijven de funnel-rij, de klant en
het product bestaan. Dat sluit aan bij waar `dbo.Funnel` voor bedoeld is — de inzending vastleggen,
ook als er verderop iets misgaat — en bij het commentaar in de procedure dat een mislukte inzending
herkenbaar moet zijn. De klant is dan geregistreerd zonder afspraak, wat als lead bruikbaar is.

De reservering krijgt daarna een eigen commit of rollback, volgens het bestaande patroon van
`/reservering`: bij `foutcode != 0` een rollback en een 500, anders committen.

## De funnel gaat niet mee naar de reservering

`spMaakReservering` heeft zelf een `@funnel`-parameter en roept daarmee `spMMJOcreateOrcheck` aan
zodra `@campagne_id = 230` is (`sql/spMaakReservering.sql:90`). Zou dit endpoint de `funnel`-waarde
ongefilterd doorgeven aan de tweede aanroep, dan zou een funnel-inzending met campagne 230 de klant
twee keer registreren: één keer via `spFunnelCreateOrCheck` en nog eens via `spMMJOcreateOrcheck`.

Daarom krijgt de reserveringsaanroep bewust géén `funnel` en géén `route` mee. De funnel-data is op
dat moment al vastgelegd in `dbo.Funnel` en de klant is al bekend via het teruggegeven `klant_id`.
Dit maakt het endpoint ook veilig voor campagne 230 zonder daar een aparte uitzondering voor te
hoeven schrijven.

## Wat dit ontwerp niet doet

- `spMaakReservering` en `spMMJOcreateOrcheck` worden niet gewijzigd.
- De MMJO-flow (`campagne_id 230` via `/reservering`) blijft ongemoeid.
- Het dynamische parameter-matchingmechanisme (`_call_sp_dynamic`) wordt niet aangepast; het nieuwe
  endpoint gebruikt het zoals `/reservering` dat doet.
- Er wordt geen e-mail verstuurd. `/reservering` doet dat via `_try_send_reservering_email`; of dat
  voor funnel-reserveringen ook moet, is niet besproken en valt buiten deze wijziging.
- Er worden geen directe INSERT/UPDATE-statements toegevoegd; alle writes lopen via de stored
  procedures.

## Volgorde van uitvoeren

1. `dboFunnel_tabel.sql` en de aangepaste `spFunnelCreateOrCheck.sql` uitvoeren op de
   testdatabase. Dit is de eerste keer dat die procedure draait; de procedure bevat zelf een
   waarschuwing dat hij nooit tegen het live schema is getest.
2. Het endpoint bouwen in `function_app.py`.
3. Testen tegen `SQL_DATABASE_TEST` via `run=test`, zoals `CLAUDE.md` voorschrijft voor elke
   wijziging aan een stored-procedure-aanroep.
4. Pas daarna `AFSPRAAK_FUNNEL_URL` in de App Settings van de AgendaPicker-app zetten op de
   `/api/funnel`-URL.

Stap 1 en stap 4 vragen database- respectievelijk Azure-toegang en worden door Rob of Daniel
uitgevoerd; ik heb die toegang niet en lees geen secret-bestanden.

## Open punt

De procedure is nooit uitgevoerd. De twee punten waar het commentaar zelf om vraagt, moeten bij de
eerste uitvoering gecontroleerd worden:

1. Of `dbo.Klanten` en `dbo.Producten` dezelfde kolommen en types hebben als waar
   `spMMJOcreateOrcheck` vanuit gaat.
2. Of `@klant_id` als OUTPUT-parameter hergebruikt mag worden als doel van de geneste
   `sp_executesql`-aanroep.
