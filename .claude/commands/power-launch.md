# /power-launch — intake-wizard Power Apps Code App

Doel: het launch-document `docs/TOEGANG-EN-RECHTEN.md` aanmaken (of bijwerken) op basis van
`.claude/reference/power-launch-template.md`, via intake-vragen aan de owner.

Voer de volgende stappen in deze volgorde uit:

1. **Modus bepalen.** Bestaat `docs/TOEGANG-EN-RECHTEN.md` al in dit project?
   - Nee → *nieuw*: kopieer `.claude/reference/power-launch-template.md` naar `docs/TOEGANG-EN-RECHTEN.md`.
   - Ja → *update*: laat de generieke secties (2 t/m 5) intact; alleen sectie 1 (intake), de bijlage
     en de launch-checklist worden bijgewerkt. Toon eerst de huidige bijlage en vraag wat er wijzigt.
2. **Intake-vragen stellen — één vraag tegelijk**, multiple choice waar mogelijk, in vijf blokken:
   a. **App & omgevingen:** app-naam + doel; welke omgevingen (test/acceptatie/productie) met
      environment-ID's; security group per omgeving (of "geen"). Environment-ID's zijn te vinden
      in admin.powerplatform.microsoft.com → Environments.
   b. **Toegang (laag 1):** welke medewerkers/groepen mogen de app openen; bestaat er al een
      parent-groep (naam + Object ID) of moet die nog aangemaakt worden?
   c. **Rollen & rechten (laag 2):** welke rollen (met hiërarchie); per rol: bron (Entra-groep —
      aanbevolen — of user-ID-lijst in code), leden of groep-ID, welke tabs, welke actie-gates.
      Vraag door tot elke rol een complete rij in de matrix heeft.
   d. **Datalaag & connectoren:** SQL-server + database; komen views/sprocs uit een bestaande
      `power.config.json` of worden ze nog toegevoegd; overige connectoren; is de DLP-check gedaan?
   e. **Deploy:** wie worden co-owner (mogen `pac code push`); is de play-URL al bekend?
3. **Document invullen.** Vul sectie 1 (intake-tabellen) en de bijlage in met de antwoorden.
   Vervang `<app>` in de bijlage-kop door de app-naam. Antwoorden die nog onbekend zijn:
   laat het `<vul in>`-veld staan en neem ze op in het open-punten-overzicht (stap 5).
4. **Launch-checklist bijwerken.** Vink in de checklist af wat al gedaan is (volgens de
   antwoorden); vul concrete waarden in de commando's in (environment-ID e.d.).
5. **Samenvatting geven:** wat is ingevuld, welke open punten resteren (aan te maken groepen,
   ontbrekende Object ID's, DLP-check), en wat de eerstvolgende portal- en code-stap is.
   Bied aan de code-stappen één voor één uit te voeren op verzoek.

BELANGRIJK:
- Voer zelf géén pac-/portal-stappen uit tijdens de wizard — de output is het document + checklist.
- Schrijf nooit secrets of credential-waarden in het document; GUID's (groepen, apps, omgevingen)
  zijn niet geheim en mogen wél.
- Lees nooit `.env*`-bestanden voor de variabelen — de variabel-namen staan al in sectie 4 van
  de template.
