/****** Object: StoredProcedure [dbo].[spValideerWijzigPincode]
Voorstel — NOG NIET UITGEVOERD. Valideert een ingevoerde pincode tegen [dbo].[WijzigAfspraakPincodes] op
basis van e-mailadres (niet meer op basis van afspraak_id — de klant kent dat nummer niet meer, het komt
nu uit de database via spZoekAfspraakVoorWijziging). Wordt aangeroepen door zowel /wijzig-verificatie als
opnieuw door /wijzig-opslaan (zelfde hervalidatie-patroon als de vorige Table Storage-opzet).

Gedrag bij mismatch/verlopen/te vaak fout: @geldig = 0, generieke @foutmelding, geen onderscheid tussen de
exacte reden (voorkomt informatie-lekken). Bij match: retourneert de actuele afspraak-informatie
(kan afwijken van het moment van aanvragen, als de afspraak intussen elders gewijzigd is) en @geldig = 1.

Aannames: zelfde als sql/spZoekAfspraakVoorWijziging.sql. Let op: [dbo].[Afspraak]'s PK heet
[afspraak-id] (koppelteken, bevestigd 2026-09-03) — [dbo].[WijzigAfspraakPincodes] (onze eigen
tabel) gebruikt wél [afspraak_id] met underscore, dat is bewust ons eigen naamgevingsconventie.

@agenda wordt afgeleid uit insteek_id/prodcat_id (mapping aangeleverd 2026-09-03):
  insteek_id=5              -> 'hypotheek'
  insteek_id=1              -> 'vermogen'
  insteek_id=35+prodcat_id=22 -> 'schade' (die combinatie is op zich meerduidig — kan ook 'oakk' of
                                 'service' betekenen — maar AgendaPicker's /api/availability accepteert
                                 toch alleen hypotheek/vermogen/schade als agenda-filter, dus 'schade'
                                 is de enige bruikbare van de drie in deze context)
NIET bevestigd: of [dbo].[Afspraak]'s kolommen [insteek-id]/[prodcat-id] koppeltekens gebruiken (zoals
[afspraakstate-id]) of underscores (zoals klant_id/adviseur_id) — hier aangenomen als koppelteken, naar
analogie van [afspraakstate-id]. Controleer dit vóór uitvoering.

@postcode wordt (sinds 2026-09-07) niet meer overgenomen uit de opgeslagen pincode-rij (die kan
verouderd zijn), maar net als de andere afspraak-velden vers herleid uit [dbo].[Afspraak] via
[adres_sleutel] -> [dbo].[Adres].[Adres-id] -> LEFT([PKD], 4). Zie sql/spZoekAfspraakVoorWijziging.sql
voor dezelfde, nog niet geverifieerde aanname over deze kolomnamen.

@doorgepland (nieuw, 2026-09-07): BIT, afgeleid uit [dbo].[Afspraak].[pre_aid] — als die kolom gevuld
is (niet NULL), is de afspraak "doorgepland" en moet AgendaPicker altijd op de oorspronkelijke
adviseur filteren (geen "toon meer tijden"-keuze aanbieden aan de klant). Kolomnaam [pre_aid]
(underscore, FK-conventie zoals klant_id/adviseur_id/adres_sleutel) is NIET geverifieerd tegen het
echte schema, alleen aangeleverd als tekst door de gebruiker.
******/
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

    DECLARE @insteek_id INT, @prodcat_id INT, @adres_sleutel INT, @pre_aid INT;

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
        @pre_aid = [pre_aid]
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
