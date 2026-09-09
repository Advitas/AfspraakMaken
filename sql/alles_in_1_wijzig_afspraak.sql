/*
=================================================================================================
 Wijzig-afspraak-flow: alle SQL in één bestand, in de juiste uitvoeringsvolgorde.

 Idempotent — dit hele bestand kan zonder nadenken opnieuw (of voor het eerst) uitgevoerd worden,
 ook als delen ervan al eerder gedraaid zijn: de tabel/indexen worden alleen aangemaakt als ze nog
 niet bestaan (IF NOT EXISTS), de stored procedures gebruiken CREATE OR ALTER, en de GRANT-statements
 zijn van zichzelf al veilig om te herhalen. Eén druk op de knop in SSMS (heel bestand selecteren en
 uitvoeren) volstaat.

 Bevat, in volgorde:
   1) Tabel dbo.WijzigAfspraakPincodes         (sql/WijzigAfspraakPincodes_tabel.sql)
   2) SP   dbo.spZoekAfspraakVoorWijziging     (sql/spZoekAfspraakVoorWijziging.sql)
   3) SP   dbo.spBewaarWijzigPincode           (sql/spBewaarWijzigPincode.sql)
   4) SP   dbo.spValideerWijzigPincode         (sql/spValideerWijzigPincode.sql)
   5) SP   dbo.spWijzigAfspraakDatumTijd       (sql/spWijzigAfspraakDatumTijd.sql)
   6) GRANT-statements voor svc-AppMaakAfspraak (beide rechten-bestanden samengevoegd)

 Losse bestanden per object blijven ook bestaan in deze map (sql/*.sql) — dit bestand is puur
 gemak om alles in één keer in SSMS te kunnen doorlopen/uitvoeren.

 BELANGRIJKSTE AANNAMES DIE NOG GEVERIFIEERD MOETEN WORDEN (zie ook de losse bestanden):
   1) [dbo].[Afspraak]'s PK-kolom heet [afspraak-id] MET KOPPELTEKEN (bevestigd 2026-09-03 — zelfde
      patroon als [afspraakstate-id]/[insteek-id]/[prodcat-id]). Let op: [dbo].[actions] gebruikt
      wél [afspraak_id] met underscore (zo aangeleverd in usp_Reservering_OmzettenNaarAfspraak) —
      dit verschilt dus per tabel. Onze eigen nieuwe tabel [dbo].[WijzigAfspraakPincodes] gebruikt
      bewust ook underscore (eigen naamgevingsconventie, geen bestaand schema om aan te sluiten).
   2) [dbo].[Afspraak].[vorm_afspraak] gebruikt de schrijfwijzen 'Online' / 'Buitendienst'
      (Titel-case) — alleen 'Online' is bevestigd, 'Buitendienst' is een aanname naar analogie.
   3) [dbo].[Klanten] bestaat met kolommen [klant_id], [email] en [postcode] (dat laatste sinds
      2026-09-07 weer nodig als fallback, zie punt 7) — AgendaPicker's eigen code detecteert dit
      schema juist DYNAMISCH omdat het kan variëren; deze SP's gaan uit van de meest waarschijnlijke,
      vaste namen. Check dit eerst met bijv. `sp_help '[dbo].[Klanten]'`.
   4) [dbo].[users] heeft een PK-kolom [id] (voor de creator_id-fallback in spWijzigAfspraakDatumTijd).
   5) Een aantal [dbo].[actions]-kolommen (direction, product_id, tag, communication, Oorsprong,
      Oorsprong_categorie, insteek_id, field_contents_4 t/m 12) staan op NULL — check of dat
      businessmatig klopt voor het "Afspraakwijziging"-scenario.
   6) spValideerWijzigPincode leidt @agenda af uit [insteek-id]/[prodcat-id] (mapping aangeleverd
      2026-09-03): insteek_id=5 -> hypotheek, insteek_id=1 -> vermogen, insteek_id=35+prodcat_id=22
      -> schade (die combinatie is op zich meerduidig — kan ook 'oakk'/'service' zijn — maar
      AgendaPicker's /api/availability accepteert toch alleen hypotheek/vermogen/schade, dus 'schade'
      is de enige bruikbare uitkomst). NIET bevestigd: of [insteek-id]/[prodcat-id] daadwerkelijk
      koppeltekens gebruiken (aangenomen, naar analogie van [afspraakstate-id]).
   7) @postcode (alleen relevant bij vorm_afspraak=buitendienst) komt sinds 2026-09-07 primair uit het
      afspraak-adres zelf: [dbo].[Afspraak].[adres_sleutel] (underscore) -> [dbo].[Adres].[Adres-id]
      (koppelteken) -> LEFT([PKD], 4). Kolomnamen [adres_sleutel]/[Adres-id]/[PKD] zijn NIET
      geverifieerd tegen het echte schema, alleen aangeleverd als tekst door de gebruiker —
      controleer dit vóór uitvoering (zelfde risico als eerdere aannames hierboven: een verkeerde
      kolomnaam geeft een "Invalid column name"-fout). Als er geen adres gekoppeld is of het adres
      geen postcode oplevert, valt @postcode terug op [dbo].[Klanten].[postcode] (aangeleverd
      2026-09-07, na een praktijkgeval waarbij een afspraak geen gekoppeld adres bleek te hebben).
   8) @doorgepland (nieuw, 2026-09-07) komt uit [dbo].[Afspraak].[pre_aid] (underscore) — gevuld =
      "doorgepland", AgendaPicker moet dan altijd op de oorspronkelijke adviseur filteren en geen
      "toon meer tijden"-keuze aanbieden. Kolomnaam [pre_aid] NIET geverifieerd tegen het echte
      schema, alleen aangeleverd als tekst door de gebruiker.

 Controleer vóór het GRANT-blok eerst wat svc-AppMaakAfspraak al heeft, om overbodige grants te
 vermijden:
   SELECT pr.name AS principal, pe.permission_name, pe.state_desc, o.name AS object_name
   FROM sys.database_permissions pe
   JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
   LEFT JOIN sys.objects o ON pe.major_id = o.object_id
   WHERE pr.name = 'svc-AppMaakAfspraak';
=================================================================================================
*/

-- =================================================================================================
-- 1) Tabel dbo.WijzigAfspraakPincodes
-- Vervangt de Azure Table Storage-opslag van pincodes door een SQL-tabel — één actieve pincode
-- per afspraak_id. Eigen tabel, eigen naamgeving (underscore) — sluit niet aan op [dbo].[Afspraak].
-- Idempotent (IF NOT EXISTS) zodat dit hele bestand veilig herhaald uitgevoerd kan worden, ook als
-- de tabel/indexen al bestaan van een vorige run.
-- =================================================================================================
IF OBJECT_ID('[dbo].[WijzigAfspraakPincodes]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[WijzigAfspraakPincodes] (
        [id]            INT IDENTITY(1,1) PRIMARY KEY,
        [afspraak_id]   INT NOT NULL,
        [email]         NVARCHAR(255) NOT NULL,
        [pincode]       CHAR(6) NOT NULL,
        [postcode]      NVARCHAR(10) NULL,
        [attempts]      INT NOT NULL DEFAULT 0,
        [aangemaakt_op] DATETIME2 NOT NULL,
        [verloopt_op]   DATETIME2 NOT NULL
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_WijzigAfspraakPincodes_email'
      AND object_id = OBJECT_ID('[dbo].[WijzigAfspraakPincodes]')
)
BEGIN
    CREATE INDEX [IX_WijzigAfspraakPincodes_email] ON [dbo].[WijzigAfspraakPincodes] ([email]);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_WijzigAfspraakPincodes_afspraak_id'
      AND object_id = OBJECT_ID('[dbo].[WijzigAfspraakPincodes]')
)
BEGIN
    CREATE INDEX [IX_WijzigAfspraakPincodes_afspraak_id] ON [dbo].[WijzigAfspraakPincodes] ([afspraak_id]);
END
GO


-- =================================================================================================
-- 2) SP dbo.spZoekAfspraakVoorWijziging
-- Zoekt de eerstvolgende toekomstige afspraak met status 'Open' voor het opgegeven e-mailadres.
-- Wordt aangeroepen door AfspraakMaken's /wijzig-aanvraag, vóórdat er een pincode gegenereerd
-- wordt — als er geen afspraak gevonden wordt, wordt er geen pincode aangemaakt/verstuurd
-- (voorkomt dat je via deze route kunt achterhalen welke e-mailadressen wel/niet een klant zijn).
-- =================================================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[spZoekAfspraakVoorWijziging]
    @email           NVARCHAR(255),
    @afspraak_id     INT OUTPUT,
    @adviseur_id     INT OUTPUT,
    @datum           DATE OUTPUT,
    @tijd            TIME OUTPUT,
    @duur_kwartieren INT OUTPUT,
    @vorm_afspraak   NVARCHAR(20) OUTPUT,
    @postcode        NVARCHAR(10) OUTPUT,
    @gevonden        BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @gevonden = 0;

    DECLARE @klant_id INT;
    DECLARE @open_state_id INT;
    DECLARE @adres_sleutel INT;
    DECLARE @klanten_postcode NVARCHAR(10);

    SELECT TOP 1 @open_state_id = [afspraakstate-id]
    FROM [dbo].[Status afspraak]
    WHERE [afspraakstate_label] = N'Open';

    IF @open_state_id IS NULL
        RETURN;

    -- LET OP (2026-09-09): één e-mailadres kan op MEERDERE rijen in [dbo].[Klanten] staan (in
    -- productie aangetroffen: hetzelfde adres op klant_id 55567 én 651059, waarvan alleen de laatste
    -- een openstaande afspraak had). Daarom wordt hier NIET eerst één klant gekozen en daarna diens
    -- afspraken opgezocht: dat deed voorheen een TOP 1 op [dbo].[Klanten] zonder ORDER BY, landde op
    -- de klant zonder afspraak en gaf dus "geen afspraak gevonden" terwijl de afspraak er wél was.
    -- In plaats daarvan zoeken we de afspraak rechtstreeks, over alle klantrijen met dit e-mailadres,
    -- en leiden we klant_id/postcode af uit de gevonden afspraak. [afspraak-id] als laatste
    -- tiebreaker maakt de keuze deterministisch bij exact gelijke datum+tijd.
    SELECT TOP 1
        @afspraak_id = a.[afspraak-id],
        @adviseur_id = a.[adviseur_id],
        @datum = CAST(a.[datum_adviesgesprek] AS date),
        @tijd = CAST(a.[tijd_adviesgesprek] AS time),
        @duur_kwartieren = a.[duur],
        @vorm_afspraak = a.[vorm_afspraak],
        @adres_sleutel = a.[adres_sleutel],
        @klant_id = k.[klant_id],
        @klanten_postcode = k.[postcode]
    FROM [dbo].[Afspraak] AS a
    INNER JOIN [dbo].[Klanten] AS k
        ON k.[klant_id] = a.[klant_id]
    WHERE LOWER(LTRIM(RTRIM(k.[email]))) = LOWER(LTRIM(RTRIM(@email)))
      AND a.[afspraakstate-id] = @open_state_id
      AND a.[datum_adviesgesprek] >= CAST(GETDATE() AS date)
    ORDER BY a.[datum_adviesgesprek] ASC, a.[tijd_adviesgesprek] ASC, a.[afspraak-id] ASC;

    IF @afspraak_id IS NOT NULL
    BEGIN
        SET @gevonden = 1;

        IF @adres_sleutel IS NOT NULL
        BEGIN
            SELECT TOP 1 @postcode = LEFT([PKD], 4)
            FROM [dbo].[Adres]
            WHERE [Adres-id] = @adres_sleutel;
        END

        -- Geen (bruikbaar) afspraak-adres gevonden: terugvallen op de klant-postcode.
        IF @postcode IS NULL
            SET @postcode = @klanten_postcode;
    END
END
GO


-- =================================================================================================
-- 3) SP dbo.spBewaarWijzigPincode
-- Slaat een nieuw gegenereerde pincode op. Eén actieve pincode per afspraak_id: een nieuwe
-- aanvraag voor dezelfde afspraak verwijdert het oude record.
-- =================================================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[spBewaarWijzigPincode]
    @afspraak_id        INT,
    @email              NVARCHAR(255),
    @pincode            CHAR(6),
    @postcode           NVARCHAR(10) = NULL,
    @geldigheid_minuten INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    BEGIN TRY
        DELETE FROM [dbo].[WijzigAfspraakPincodes] WHERE [afspraak_id] = @afspraak_id;

        INSERT INTO [dbo].[WijzigAfspraakPincodes]
            ([afspraak_id], [email], [pincode], [postcode], [attempts], [aangemaakt_op], [verloopt_op])
        VALUES
            (@afspraak_id, @email, @pincode, @postcode, 0, SYSUTCDATETIME(), DATEADD(minute, @geldigheid_minuten, SYSUTCDATETIME()));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


-- =================================================================================================
-- 4) SP dbo.spValideerWijzigPincode
-- Valideert een ingevoerde pincode op basis van e-mailadres. Wordt aangeroepen door zowel
-- /wijzig-verificatie als opnieuw door /wijzig-opslaan. Bij mismatch/verlopen/te vaak fout:
-- @geldig = 0, generieke @foutmelding (voorkomt informatie-lekken). Bij match: retourneert de
-- actuele afspraak-informatie en @geldig = 1.
-- =================================================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[spValideerWijzigPincode]
    @email            NVARCHAR(255),
    @pincode          CHAR(6),
    @max_pogingen     INT = 5,
    @afspraak_id      INT OUTPUT,
    @adviseur_id      INT OUTPUT,
    @datum            DATE OUTPUT,
    @tijd             TIME OUTPUT,
    @duur_kwartieren  INT OUTPUT,
    @vorm_afspraak    NVARCHAR(20) OUTPUT,
    @postcode         NVARCHAR(10) OUTPUT,
    @agenda           NVARCHAR(20) OUTPUT,
    @doorgepland      BIT OUTPUT,
    @geldig           BIT OUTPUT,
    @foutmelding      NVARCHAR(200) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @geldig = 0;
    SET @foutmelding = N'Ongeldige of verlopen pincode.';

    DECLARE @id INT, @opgeslagen_pincode CHAR(6), @verloopt_op DATETIME2, @attempts INT, @gekoppeld_afspraak_id INT;

    SELECT TOP 1
        @id = [id],
        @opgeslagen_pincode = [pincode],
        @verloopt_op = [verloopt_op],
        @attempts = [attempts],
        @gekoppeld_afspraak_id = [afspraak_id]
    FROM [dbo].[WijzigAfspraakPincodes]
    WHERE LOWER(LTRIM(RTRIM([email]))) = LOWER(LTRIM(RTRIM(@email)))
    ORDER BY [aangemaakt_op] DESC;

    IF @id IS NULL
        RETURN;

    IF SYSUTCDATETIME() >= @verloopt_op
    BEGIN
        DELETE FROM [dbo].[WijzigAfspraakPincodes] WHERE [id] = @id;
        RETURN;
    END

    IF @attempts >= @max_pogingen
    BEGIN
        DELETE FROM [dbo].[WijzigAfspraakPincodes] WHERE [id] = @id;
        RETURN;
    END

    IF @opgeslagen_pincode <> @pincode
    BEGIN
        UPDATE [dbo].[WijzigAfspraakPincodes] SET [attempts] = [attempts] + 1 WHERE [id] = @id;
        IF @attempts + 1 >= @max_pogingen
            DELETE FROM [dbo].[WijzigAfspraakPincodes] WHERE [id] = @id;
        RETURN;
    END

    DECLARE @insteek_id INT, @prodcat_id INT, @adres_sleutel INT, @pre_aid INT, @klant_id INT;

    SELECT
        @afspraak_id = [afspraak-id],
        @adviseur_id = [adviseur_id],
        @datum = CAST([datum_adviesgesprek] AS date),
        @tijd = CAST([tijd_adviesgesprek] AS time),
        @duur_kwartieren = [duur],
        @vorm_afspraak = [vorm_afspraak],
        @insteek_id = [insteek-id],
        @prodcat_id = [prodcat-id],
        @adres_sleutel = [adres_sleutel],
        @pre_aid = [pre_aid],
        @klant_id = [klant_id]
    FROM [dbo].[Afspraak]
    WHERE [afspraak-id] = @gekoppeld_afspraak_id;

    IF @afspraak_id IS NULL
    BEGIN
        -- De gekoppelde afspraak bestaat niet meer (bijv. verwijderd sinds de pincode-aanvraag).
        SET @foutmelding = N'De bijbehorende afspraak is niet meer beschikbaar.';
        RETURN;
    END

    IF @adres_sleutel IS NOT NULL
    BEGIN
        SELECT TOP 1 @postcode = LEFT([PKD], 4)
        FROM [dbo].[Adres]
        WHERE [Adres-id] = @adres_sleutel;
    END

    -- Geen (bruikbaar) afspraak-adres gevonden: terugvallen op de klant-postcode.
    IF @postcode IS NULL AND @klant_id IS NOT NULL
    BEGIN
        SELECT TOP 1 @postcode = [postcode]
        FROM [dbo].[Klanten]
        WHERE [klant_id] = @klant_id;
    END

    SET @agenda = CASE
        WHEN @insteek_id = 5 THEN N'hypotheek'
        WHEN @insteek_id = 1 THEN N'vermogen'
        WHEN @insteek_id = 35 AND @prodcat_id = 22 THEN N'schade'
        ELSE NULL
    END;

    SET @doorgepland = CASE WHEN @pre_aid IS NOT NULL THEN 1 ELSE 0 END;

    SET @geldig = 1;
    SET @foutmelding = NULL;
END
GO


-- =================================================================================================
-- 5) SP dbo.spWijzigAfspraakDatumTijd
-- Slaat de nieuwe datum/tijd/adviseur/vorm op voor een bestaande afspraak, logt de wijziging in
-- dbo.actions (zelfde patroon als [PowerBI].[usp_Reservering_OmzettenNaarAfspraak]), en ruimt de
-- bijbehorende pincode op (one-time use).
-- =================================================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[spWijzigAfspraakDatumTijd]
  @afspraak_id      int,
  @adviseur_id      int,
  @datum            date,
  @tijd             time,
  @duur_kwartieren  int,
  @vorm_afspraak    nvarchar(20),
  @oud_adviseur_id  int OUTPUT,
  @oud_datum        date OUTPUT,
  @oud_tijd         time OUTPUT,
  @oud_vorm_afspraak    nvarchar(20) OUTPUT,
  @klant_id             int OUTPUT,
  @klant_naam           nvarchar(255) OUTPUT,
  @oud_adviseur_naam    nvarchar(255) OUTPUT,
  @nieuw_adviseur_naam  nvarchar(255) OUTPUT,
  @validatiefout    nvarchar(500) OUTPUT,
  @foutmelding      nvarchar(500) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  SET @foutmelding = NULL;
  SET @validatiefout = NULL;

  -- Normaliseer 'online'/'buitendienst' (zoals de Python-laag ze aanlevert) naar de
  -- Titel-case-schrijfwijze die [dbo].[Afspraak].[vorm_afspraak] gebruikt.
  DECLARE @vormAfspraakGenormaliseerd nvarchar(20) = CASE LOWER(@vorm_afspraak)
    WHEN 'online' THEN N'Online'
    WHEN 'buitendienst' THEN N'Buitendienst'
    ELSE @vorm_afspraak
  END;

  -- usp_Reservering_OmzettenNaarAfspraak laat zien dat [tijd_adviesgesprek], als die kolom
  -- gebruikt wordt, de VOLLE datum+tijd bevat (zie de COALESCE/TRY_CONVERT-fallback aldaar) —
  -- niet alleen het tijdsdeel. Dat patroon volgen we hier ook.
  DECLARE @datumTijd datetime2 = CAST(
    CONVERT(varchar(10), @datum, 120) + ' ' + CONVERT(varchar(8), @tijd, 108) AS datetime2
  );

  -- Een wijziging naar een moment dat (bijna) voorbij is wordt hier hard geweigerd. De AgendaPicker-
  -- frontend biedt zulke sloten al niet meer aan (KEUZE_MARGE_UREN in public/wijzig-afspraak.js, zie
  -- AgendaPicker ADR-024), maar dat is puur een UI-filter: de klant kan de pagina uren laten
  -- openstaan of de API rechtstreeks aanroepen. Deze SP is het enige schrijfpad naar
  -- [dbo].[Afspraak] voor een zelfservice-wijziging en dus de plek waar de marge werkelijk
  -- afgedwongen wordt (verzoek gebruiker 2026-09-09: "echt afdwingen").
  --
  -- SYSDATETIMEOFFSET() ... AT TIME ZONE maakt de conversie naar Nederlandse tijd expliciet en
  -- DST-correct: [datum_adviesgesprek]/[tijd_adviesgesprek] staan in Nederlandse lokale tijd, terwijl
  -- de servertijd van Azure SQL UTC is. Zonder die conversie zou de marge er in de zomer 2 uur (in de
  -- winter 1 uur) naast zitten, en dus te soepel zijn.
  DECLARE @margeUren int = 4;
  DECLARE @nuNederland datetime2(0) =
    CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'W. Europe Standard Time' AS datetime2(0));

  IF @datumTijd < DATEADD(hour, @margeUren, @nuNederland)
  BEGIN
    SET @validatiefout = N'De nieuwe datum en tijd moeten minstens '
      + CAST(@margeUren AS nvarchar(10))
      + N' uur in de toekomst liggen. Kies een later tijdstip.';
    RETURN;
  END;

  -- Nesting-safe transactiebeheer: deze SP wordt aangeroepen via pyodbc met autocommit=False, dus
  -- de caller heeft meestal al een ambient transactie open (@@TRANCOUNT = 1) vóórdat deze SP start.
  -- Een onvoorwaardelijke ROLLBACK TRANSACTION rolt in SQL Server ALTIJD terug tot TRANCOUNT 0,
  -- ongeacht nesting-diepte — dat rolt dus ook de ambient transactie van de caller weg, wat de
  -- "Transaction count after EXECUTE indicates a mismatching number of BEGIN and COMMIT
  -- statements"-fout (266) veroorzaakte (bevestigd 2026-09-07). Alleen zelf BEGIN/COMMIT/ROLLBACK
  -- doen als deze SP de transactie ook echt zelf is gestart.
  DECLARE @ownsTransaction bit = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

  IF @ownsTransaction = 1
    BEGIN TRANSACTION;

  BEGIN TRY
    -- sale_oppertunity_id van de bestaande afspraak ophalen (nodig voor de actions-insert
    -- hieronder) en tegelijk bevestigen dat de afspraak bestaat. Tegelijk de OUDE adviseur/datum/tijd
    -- vastleggen (vóór de UPDATE hieronder) — nodig voor de wijzigings-samenvatting-mail naar
    -- planning@advitas.nl (aangevraagd 2026-09-07), die niet meer los kan worden opgehaald sinds
    -- /wijzig_opslaan geen pincode-hervalidatie meer doet.
    DECLARE @saleOpportunityId nvarchar(255);

    SELECT
        @saleOpportunityId = [saleop_id],
        @oud_adviseur_id = [adviseur_id],
        @oud_datum = CAST([datum_adviesgesprek] AS date),
        @oud_tijd = CAST([tijd_adviesgesprek] AS time),
        @oud_vorm_afspraak = [vorm_afspraak],
        @klant_id = [klant_id]
    FROM [dbo].[Afspraak]
    WHERE [afspraak-id] = @afspraak_id;

    IF @@ROWCOUNT = 0
    BEGIN
      IF @ownsTransaction = 1
        ROLLBACK TRANSACTION;
      SET @foutmelding = N'Afspraak niet gevonden.';
      RETURN;
    END;

    -- Klant- en adviseursnaam voor de wijzigings-samenvattingsmail (aangevraagd 2026-09-07). Puur
    -- informatief, dus geen foutafhandeling nodig als er geen match is — blijft dan NULL.
    IF @klant_id IS NOT NULL
    BEGIN
      SELECT TOP 1 @klant_naam = NULLIF(LTRIM(RTRIM(CONCAT_WS(N' ',
          NULLIF(LTRIM(RTRIM([voorletters])), N''),
          NULLIF(LTRIM(RTRIM([tussenvoegsel])), N''),
          NULLIF(LTRIM(RTRIM([naam])), N'')
        ))), N'')
      FROM [dbo].[Klanten]
      WHERE [klant_id] = @klant_id;
    END

    SELECT TOP 1 @oud_adviseur_naam = [Adviseur] FROM [dbo].[Adviseurs] WHERE [adviseur_ID] = @oud_adviseur_id;
    SELECT TOP 1 @nieuw_adviseur_naam = [Adviseur] FROM [dbo].[Adviseurs] WHERE [adviseur_ID] = @adviseur_id;

    UPDATE [dbo].[Afspraak]
    SET
      [adviseur_id] = @adviseur_id,
      [datum_adviesgesprek] = CAST(@datum AS datetime2),
      [tijd_adviesgesprek] = @datumTijd,
      [duur] = @duur_kwartieren,
      [vorm_afspraak] = @vormAfspraakGenormaliseerd,
      [updated_at] = GETDATE()
    WHERE [afspraak-id] = @afspraak_id;

    -- Actions-log voor de wijziging. Deze SP wordt aangeroepen door de AfspraakMaken Azure
    -- Function (function-key-auth, geen ingelogde gebruiker) — er is dus nooit een "ingelogde
    -- gebruiker"-context beschikbaar, vandaar altijd de fallback naar de eerste rij van dbo.users
    -- (TOP 1 zonder ORDER BY is geen garantie voor een specifieke rij — voeg een ORDER BY/WHERE
    -- toe als er een vaste systeemgebruiker moet zijn).
    DECLARE @creatorId uniqueidentifier;
    SELECT TOP 1 @creatorId = [id] FROM dbo.users;

    DECLARE @actionTypeId uniqueidentifier = '17AE20FB-8E45-4201-8FB8-952FB2C8CA4F'; -- PLANNING_MOVE_ACTION_TYPE_ID ("Afspraakwijziging")

    INSERT INTO [dbo].[actions] (
      [id],
      [creator_id],
      [sale_oppertunity_id],
      [action_type_id],
      [state_id],
      [comments],
      [role],
      [field_contents_1],
      [field_contents_2],
      [field_contents_3],
      [created_at],
      [updated_at],
      [field_contents_4],
      [field_contents_5],
      [direction],
      [field_contents_6],
      [field_contents_7],
      [field_contents_8],
      [field_contents_9],
      [field_contents_10],
      [product_id],
      [tag],
      [source],
      [communication],
      [afspraak_id],
      [auto_type],
      [Oorsprong],
      [Oorsprong_categorie],
      [field_contents_11],
      [field_contents_12],
      [insteek_id],
      [created_at_dutch]
    )
    VALUES (
      NEWID(),
      @creatorId,
      @saleOpportunityId,
      @actionTypeId,
      35,
      N'',
      N'telemarketer',
      CAST(@afspraak_id AS nvarchar(50)),
      CAST(@adviseur_id AS nvarchar(50)),
      CONVERT(nvarchar(50), @datumTijd, 120),
      SYSUTCDATETIME(),
      SYSUTCDATETIME(),
      NULL,
      NULL,
      N'inbound',
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      N'Manual (Swap)',
      NULL,
      @afspraak_id,
      N'manual',
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), SYSUTCDATETIME())
    );

    -- Pincode is nu verbruikt (one-time use) — opruimen zodat 'ie niet herbruikt kan worden.
    DELETE FROM [dbo].[WijzigAfspraakPincodes] WHERE [afspraak_id] = @afspraak_id;

    IF @ownsTransaction = 1
      COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    -- SET XACT_ABORT ON zorgt dat een echte runtime-fout (niet het gecontroleerde "niet
    -- gevonden"-pad hierboven) de transactie meestal volledig "doomed" maakt (XACT_STATE() = -1),
    -- ook als @ownsTransaction = 0 (ambient transactie van de caller). In dat geval kan de caller's
    -- batch geen enkel statement meer uitvoeren (ook niet de SELECT @foutmelding erna, wat eerder de
    -- verwarrende "Uncommittable transaction is detected at the end of the batch"-fout gaf i.p.v. de
    -- echte oorzaak) — dus dan meteen de oorspronkelijke fout doorgeven i.p.v. proberen netjes terug
    -- te keren (bevestigd 2026-09-07).
    IF @ownsTransaction = 1 AND XACT_STATE() <> 0
      ROLLBACK TRANSACTION;

    IF XACT_STATE() = -1
      THROW;

    SET @foutmelding = ERROR_MESSAGE();
  END CATCH
END;
GO


-- =================================================================================================
-- 6) Rechten voor svc-AppMaakAfspraak
-- Zelfde patroon als de buitendienst-availability-fix (docs/DECISIONS.md, 2026-09-01) —
-- ontbrekende GRANT EXECUTE/SELECT op een nieuwe SP + onderliggende tabellen gaf daar een
-- generieke HTTP 500. Pas de gebruikersnaam hieronder aan als het service-account inmiddels
-- anders heet dan svc-AppMaakAfspraak.
-- =================================================================================================
GRANT EXECUTE ON [dbo].[spZoekAfspraakVoorWijziging] TO [svc-AppMaakAfspraak];
GRANT EXECUTE ON [dbo].[spBewaarWijzigPincode] TO [svc-AppMaakAfspraak];
GRANT EXECUTE ON [dbo].[spValideerWijzigPincode] TO [svc-AppMaakAfspraak];
GRANT EXECUTE ON [dbo].[spWijzigAfspraakDatumTijd] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Klanten] TO [svc-AppMaakAfspraak];
GRANT SELECT, UPDATE ON [dbo].[Afspraak] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Status afspraak] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Adres] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Adviseurs] TO [svc-AppMaakAfspraak];
GRANT INSERT ON [dbo].[actions] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[users] TO [svc-AppMaakAfspraak];
GRANT DELETE ON [dbo].[WijzigAfspraakPincodes] TO [svc-AppMaakAfspraak];
GO
