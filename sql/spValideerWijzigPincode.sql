/****** Object: StoredProcedure [dbo].[spValideerWijzigPincode]
Voorstel — NOG NIET UITGEVOERD. Valideert een ingevoerde pincode tegen [dbo].[WijzigAfspraakPincodes] op
basis van e-mailadres (niet meer op basis van afspraak_id — de klant kent dat nummer niet meer, het komt
nu uit de database via spZoekAfspraakVoorWijziging). Wordt aangeroepen door zowel /wijzig-verificatie als
opnieuw door /wijzig-opslaan (zelfde hervalidatie-patroon als de vorige Table Storage-opzet).

Gedrag bij mismatch/verlopen/te vaak fout: @geldig = 0, generieke @foutmelding, geen onderscheid tussen de
exacte reden (voorkomt informatie-lekken). Bij match: retourneert de actuele afspraak-informatie
(kan afwijken van het moment van aanvragen, als de afspraak intussen elders gewijzigd is) en @geldig = 1.

Aannames: zelfde als sql/spZoekAfspraakVoorWijziging.sql — met name de PK-kolomnaam [afspraak_id] op
[dbo].[Afspraak].
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

    SELECT
        @afspraak_id = [afspraak_id],
        @adviseur_id = [adviseur_id],
        @datum = CAST([datum_adviesgesprek] AS date),
        @tijd = CAST([tijd_adviesgesprek] AS time),
        @duur_kwartieren = [duur],
        @vorm_afspraak = [vorm_afspraak]
    FROM [dbo].[Afspraak]
    WHERE [afspraak_id] = @gekoppeld_afspraak_id;

    IF @afspraak_id IS NULL
    BEGIN
        -- De gekoppelde afspraak bestaat niet meer (bijv. verwijderd sinds de pincode-aanvraag).
        SET @foutmelding = N'De bijbehorende afspraak is niet meer beschikbaar.';
        RETURN;
    END

    SET @geldig = 1;
    SET @foutmelding = NULL;
END
GO
