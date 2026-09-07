/****** Object: StoredProcedure [dbo].[spZoekAfspraakVoorWijziging]
Voorstel — NOG NIET UITGEVOERD.

Zoekt de eerstvolgende toekomstige afspraak met status 'Open' voor het opgegeven e-mailadres. Wordt
aangeroepen door AfspraakMaken's /wijzig-aanvraag, vóórdat er een pincode gegenereerd wordt — als er geen
afspraak gevonden wordt, wordt er geen pincode aangemaakt/verstuurd (voorkomt dat je via deze route kunt
achterhalen welke e-mailadressen wel/niet een klant zijn).

Aannames die geverifieerd moeten worden vóór uitvoering (zie ook sql/spWijzigAfspraakDatumTijd.sql voor
de eerdere aannames over [dbo].[Afspraak]):
1) De PK-kolom van [dbo].[Afspraak] heet [afspraak-id] (met koppelteken, bevestigd 2026-09-03).
2) De Klanten-tabel heet [dbo].[Klanten] met kolommen [klant_id] en [email] — AgendaPicker's eigen code
   (server.js, getKlantenTableInfo) detecteert dit juist DYNAMISCH omdat het schema kan variëren
   (kolomnamen als 'e-mailadres'/'mailadres' worden daar ook geaccepteerd) — deze SP gaat uit van de
   meest waarschijnlijke, vaste namen. Als dat niet klopt, moet de WHERE/SELECT hieronder aangepast
   worden.
3) '[afspraakstate-id]'/'[Status afspraak]'/'afspraakstate_label' = 'Open' zijn WEL bevestigd (rechtstreeks
   overgenomen uit [PowerBI].[usp_Reservering_OmzettenNaarAfspraak], aangeleverd 2026-09-03).
4) "Eerstvolgende toekomstige afspraak" = kleinste datum_adviesgesprek >= vandaag met status Open. Bij
   meerdere gelijktijdige afspraken voor dezelfde klant wordt er willekeurig één gekozen (geen expliciete
   tiebreaker anders dan tijd) — laat weten of dat businessmatig anders moet.
5) @postcode (alleen relevant bij vorm_afspraak=buitendienst, nodig voor de beschikbaarheids-kalender;
   mag NULL zijn voor online-afspraken) komt primair uit het afspraak-adres zelf:
   [dbo].[Afspraak].[adres_sleutel] (underscore, FK-conventie zoals klant_id/adviseur_id) verwijst naar
   [dbo].[Adres].[Adres-id] (koppelteken, PK-conventie zoals [afspraak-id]/[afspraakstate-id]).
   [dbo].[Adres] heeft een kolom [PKD] (postcode, bijv. "1234AB") — @postcode wordt de eerste 4 tekens
   daarvan (aangeleverd 2026-09-07). Kolomnamen [adres_sleutel]/[Adres-id]/[PKD] zijn NIET geverifieerd
   tegen het echte schema, alleen aangeleverd door de gebruiker als tekst — controleer dit vóór
   uitvoering. Als er geen adres gekoppeld is (@adres_sleutel IS NULL) of het adres geen postcode
   oplevert, valt @postcode terug op [dbo].[Klanten].[postcode] (aangeleverd 2026-09-07, na een
   praktijkgeval waarbij een afspraak geen gekoppeld adres bleek te hebben) — die Klanten-kolom is,
   net als [klant_id]/[email], zelf ook niet geverifieerd.
******/
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

    SELECT TOP 1 @klant_id = [klant_id], @klanten_postcode = [postcode]
    FROM [dbo].[Klanten]
    WHERE LOWER(LTRIM(RTRIM([email]))) = LOWER(LTRIM(RTRIM(@email)));

    IF @klant_id IS NULL
        RETURN;

    SELECT TOP 1 @open_state_id = [afspraakstate-id]
    FROM [dbo].[Status afspraak]
    WHERE [afspraakstate_label] = N'Open';

    IF @open_state_id IS NULL
        RETURN;

    SELECT TOP 1
        @afspraak_id = [afspraak-id],
        @adviseur_id = [adviseur_id],
        @datum = CAST([datum_adviesgesprek] AS date),
        @tijd = CAST([tijd_adviesgesprek] AS time),
        @duur_kwartieren = [duur],
        @vorm_afspraak = [vorm_afspraak],
        @adres_sleutel = [adres_sleutel]
    FROM [dbo].[Afspraak]
    WHERE [klant_id] = @klant_id
      AND [afspraakstate-id] = @open_state_id
      AND [datum_adviesgesprek] >= CAST(GETDATE() AS date)
    ORDER BY [datum_adviesgesprek] ASC, [tijd_adviesgesprek] ASC;

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
