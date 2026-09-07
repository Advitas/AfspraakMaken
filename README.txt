Azure Function: afspraak

Endpoint:
POST /afspraak
(ook /api/afspraak mogelijk als routePrefix niet leeg is)

Verplichte JSON-velden:
- klant_id (int; 0 = nieuwe klant via stored procedure)
- adviseur_id (int, array of ints, of comma-delimited string zoals "18,22,35")
- datum (YYYY-MM-DD, bijv. 2026-06-24)
- tijd (HH:MM of HH:MM:SS, bijv. 14:30)
- duur_kwartieren (int; 1=15 min, 2=30 min, ...)
- campagne_id (int)

Optioneel:
- naam (string)
- email (string)
- productnaam (string)
- afspraak_type (string, default "online")
- opmerkingen (string)
- insteek_id (int)
- prodcat_id (int)
- advcat_id (int)
- vorm_afspraak (string, default "online")
- is_nieuwe_afspraak (bool/0/1, default true)
- create_opportunity_if_missing (bool/0/1, default false)
- overige velden zijn toegestaan en worden teruggegeven in de response onder "input"

Gedrag:
1) De functie doet geen directe INSERT/UPDATE/SELECT meer op tabellen.
2) adviseur_id mag meerdere IDs bevatten; de functie geeft deze als comma-delimited string door aan de SP.
3) De functie roept alleen [dbo].[spMaakAfspraak] aan met alle inputparameters.
4) Output parameters (@klant_id, @campagne_id, @afspraak_id, @campagne_naam, @foutmelding) worden teruggegeven.

Environment variables (aanbevolen, gesplitst):
- SQL_SERVER
- SQL_PORT (optioneel, default 1433)
- SQL_DATABASE_PROD (voor run=prod)
- SQL_DATABASE_TEST (voor alle andere run-waardes)
- SQL_DATABASE (optionele fallback)
- SQL_USER
- SQL_PASSWORD
- SQL_ODBC_DRIVER (optioneel, default ODBC Driver 18 for SQL Server)
- SQL_ENCRYPT (optioneel, default yes)
- SQL_TRUST_SERVER_CERTIFICATE (optioneel, default no)
- SQL_CONNECTION_TIMEOUT (optioneel, default 30)

Alternatief:
- SQL_CONNECTION_STRING (wordt ook ondersteund)

Voorbeeld request body:
{
  "klant_id": 0,
  "adviseur_id": "18,22,35",
  "datum": "2026-06-24",
  "tijd": "14:30",
  "duur_kwartieren": 2,
  "campagne_id": 77,
  "opmerkingen": "bel klant terug",
  "vorm_afspraak": "online",
  "is_nieuwe_afspraak": true,
  "create_opportunity_if_missing": true
}

Voorbeeld response:
{
  "result": "success",
  "input": { "...": "originele body" },
  "adviseur_id_doorgestuurd": "18,22,35",
  "stored_procedure_output": {
    "klant_id": 1234,
    "campagne_id": 77,
    "afspraak_id": 5678,
    "campagne_naam": "Campagne X",
    "foutmelding": null
  },
  "stored_procedure_result": [
    [
      { "kolom": "waarde" }
    ]
  ]
}


Gebruik in calls: https://afspraken-dmcveachayhxfhaf.westeurope-01.azurewebsites.net/afspraak
Niet de root URL zonder pad, anders krijg je de standaard Azure "up and running" HTML-pagina.

---

Nieuw endpoint:
POST /api/reservering (of /reservering als routePrefix leeg staat)

Gedrag:
- Roept alleen [dbo].[spMaakReservering] aan.
- Procedure-parameters worden dynamisch gematcht op naam (case-insensitive, special chars genegeerd).
- Ondersteunt aliases zoals campaign_id/campagne_id en MMJO/funnel/mmjo_funnel/funnel.
- Stuurt adviseur_id als comma-delimited string door (bijv. "18,22,35").
- Geeft matched_parameters, output-parameters en resultsets terug.

Verplicht voor dit endpoint:
- datum
- tijd
- duur_kwartieren
- campaign_id (of campagne_id)
- adviseur_id
- run

Alleen verplicht bij campaign_id/campagne_id = 230:
- MMJO/funnel (of mmjo_funnel / funnel)

Voorbeeld:
POST https://<jouw-host>/api/reservering

Availability endpoint (hersteld):
GET/POST /availability
- Roept [dbo].[psAgendaPicker_GetAvailability] aan.
- Accepteert querystring en/of JSON body.
- Matcht procedure-parameters dynamisch.

Volledige handleiding:
Zie USER_MANUAL.md

---

Nieuwe endpoints: afspraak wijzigen via pincode (e-mail-eerst)

POST /api/wijzig_aanvraag (of /wijzig_aanvraag als routePrefix leeg staat)
(underscore, niet koppelteken — bewust gelijkgetrokken met de Python-functienaam, zie docs/DECISIONS.md)
Body: { email, run }
Gedrag: zoekt via [dbo].[spZoekAfspraakVoorWijziging] de eerstvolgende toekomstige afspraak met status
'Open' voor dit e-mailadres. Geen afspraak gevonden: HTTP 404, geen mail verstuurd (voorkomt dat je via
deze route kunt achterhalen welke e-mailadressen wel/niet klant zijn). Wel gevonden: genereert een
6-cijferige pincode (5 min geldig, max 5 pogingen — bewaakt in SQL, zie [dbo].[WijzigAfspraakPincodes]),
slaat die op via [dbo].[spBewaarWijzigPincode], en mailt alleen de pincode (geen knop/link — de klant
staat al op de AgendaPicker-wijzigpagina, dat scherm heeft juist deze aanvraag getriggerd) naar dat
e-mailadres.

POST /api/wijzig_verificatie
Body: { email, pincode, run }
Gedrag: controleert de pincode via [dbo].[spValideerWijzigPincode]. Bij succes: retourneert afspraak_id,
adviseur_id, datum, tijd, duur_kwartieren, vorm_afspraak, postcode, agenda (afgeleid uit insteek_id/
prodcat_id — hypotheek/vermogen/schade), doorgepland van de gekoppelde afspraak (voor de kalender +
informatieweergave in AgendaPicker). postcode komt (sinds 2026-09-07) primair uit het afspraak-adres
zelf — [dbo].[Afspraak].[adres_sleutel] -> [dbo].[Adres].[Adres-id] -> de eerste 4 tekens van [PKD] —
nodig voor de buitendienst-beschikbaarheid, die zonder postcode een 400-fout geeft (zie
/api/availability in USER_MANUAL.md). Is er geen adres gekoppeld (of levert het geen postcode op),
dan valt dit terug op [dbo].[Klanten].[postcode]. doorgepland (bool, ook nieuw 2026-09-07) is true
als [dbo].[Afspraak].[pre_aid] gevuld
is — geeft aan dat AgendaPicker altijd op de oorspronkelijke adviseur moet filteren (geen "toon meer
tijden"-keuze aanbieden).

POST /api/wijzig_opslaan
Body: { afspraak_id, adviseur_id, datum, tijd, duur_kwartieren, vorm_afspraak, run }
Gedrag: roept direct [dbo].[spWijzigAfspraakDatumTijd] aan met de meegestuurde afspraak_id. Die
procedure ruimt de bijbehorende pincode-rij zelf op bij succes (one-time use, opgeruimd op afspraak_id).

LET OP (2026-09-07, bewuste afwijking van het beveiligingsmodel hierboven): dit endpoint controleert
GEEN pincode meer — afspraak_id komt rechtstreeks van de client i.p.v. server-side afgeleid uit een
hervalidatie van de pincode. Voorheen (zoals /wijzig_verificatie hierboven nog doet) werd afspraak_id
altijd server-side bepaald, juist om te voorkomen dat een client een willekeurige afspraak_id kon
meesturen. Deze wijziging is expliciet door de gebruiker gevraagd omdat de 5-minuten-vervaltermijn van
de pincode een "verlopen pincode"-fout gaf als een klant lang in de AgendaPicker-kalender aan het
kiezen was. Gevolg: wie een afspraak_id kent (of raadt/opsomt) kan die wijzigen zonder verdere
identiteitscontrole bij het opslaan zelf. Zie docs/DECISIONS.md voor de volledige afweging.

Nieuwe environment variable:
- AGENDAPICKER_BASE_URL (optioneel, default
  https://agendapicker-ahe5g9g6gdh0gcdw.westeurope-01.azurewebsites.net — basis-URL voor de "Afspraak
  wijzigen"-link in de afspraak-bevestigingsmail hieronder; de pincode-mail zelf bevat geen link meer)

---

Afspraak-bevestigingsmail naar de klant (UIT by default)

/afspraak (POST) kan optioneel, na een succesvolle aanmaak, een bevestigingsmail naar de klant
(`email`-veld uit de body) sturen met datum/tijd/vorm en een "Afspraak wijzigen"-knop die naar
AgendaPicker's wijzig-afspraak.html?email=... linkt (vult alleen het e-mailveld voor; de klant moet zelf
op "Versturen" klikken).

Standaard UIT — /afspraak is een bestaand, al in productie actief endpoint; dit voorkomt dat er
ongemerkt bevestigingsmails naar echte klanten gaan zodra deze wijziging gedeployed wordt.

Nieuwe environment variable:
- AFSPRAAK_BEVESTIGING_MAIL_ENABLED (optioneel, default "false" — zet op "true" om de
  bevestigingsmail daadwerkelijk te versturen)

De mail respecteert (tijdelijk, zie docs/DECISIONS.md 2026-09-03) dezelfde WIJZIG_MAIL_OVERRIDE_TO als
de pincode-mail — zolang die actief is, gaat ook déze mail naar het override-adres in plaats van naar
het echte klant-e-mailadres.