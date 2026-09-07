/****** Object: StoredProcedure [dbo].[spZoekAfspraakVoorWijziging]
Voorstel — NOG NIET UITGEVOERD.

Zoekt de eerstvolgende toekomstige afspraak met status 'Open' voor het opgegeven e-mailadres. Wordt
aangeroepen door AfspraakMaken's /wijzig-aanvraag, vóórdat er een pincode gegenereerd wordt — als er geen
afspraak gevonden wordt, wordt er geen pincode aangemaakt/verstuurd (voorkomt dat je via deze route kunt
achterhalen welke e-mailadressen wel/niet een klant zijn).

Aannames die geverifieerd moeten worden vóór uitvoering (zie ook sql/spWijzigAfspraakDatumTijd.sql voor
de eerdere aannames over [dbo].[Afspraak]):
1) De PK-kolom van [dbo].[Afspraak] heet [afspraak_id] (zelfde aanname als eerder, nog niet bevestigd).
2) De Klanten-tabel heet [dbo].[Klanten] met kolommen [klant_id] en [email] — AgendaPicker's eigen code
   (server.js, getKlantenTableInfo) detecteert dit juist DYNAMISCH omdat het schema kan variëren
   (kolomnamen als 'e-mailadres'/'mailadres' worden daar ook geaccepteerd) — deze SP gaat uit van de
   meest waarschijnlijke, vaste namen. Als dat niet klopt, moet de WHERE/JOIN hieronder aangepast worden.
3) '[afspraakstate-id]'/'[Status afspraak]'/'afspraakstate_label' = 'Open' zijn WEL bevestigd (rechtstreeks
   overgenomen uit [PowerBI].[usp_Reservering_OmzettenNaarAfspraak], aangeleverd 2026-09-03).
4) "Eerstvolgende toekomstige afspraak" = kleinste datum_adviesgesprek >= vandaag met status Open. Bij
   meerdere gelijktijdige afspraken voor dezelfde klant wordt er willekeurig één gekozen (geen expliciete
   tiebreaker anders dan tijd) — laat weten of dat businessmatig anders moet.
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
    @gevonden        BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @gevonden = 0;

    DECLARE @klant_id INT;
    DECLARE @open_state_id INT;

    SELECT TOP 1 @klant_id = [klant_id]
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
        @afspraak_id = [afspraak_id],
        @adviseur_id = [adviseur_id],
        @datum = CAST([datum_adviesgesprek] AS date),
        @tijd = CAST([tijd_adviesgesprek] AS time),
        @duur_kwartieren = [duur],
        @vorm_afspraak = [vorm_afspraak]
    FROM [dbo].[Afspraak]
    WHERE [klant_id] = @klant_id
      AND [afspraakstate-id] = @open_state_id
      AND [datum_adviesgesprek] >= CAST(GETDATE() AS date)
    ORDER BY [datum_adviesgesprek] ASC, [tijd_adviesgesprek] ASC;

    IF @afspraak_id IS NOT NULL
        SET @gevonden = 1;
END
GO
