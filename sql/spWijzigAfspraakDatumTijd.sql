/****** Object:  StoredProcedure [dbo].[spWijzigAfspraakDatumTijd]
Voorstel — NOG NIET UITGEVOERD tegen SQL_DATABASE_TEST of productie.
Gebaseerd op het schema van [dbo].[Afspraak] zoals zichtbaar in
[PowerBI].[usp_Reservering_OmzettenNaarAfspraak] (aangeleverd 2026-09-03).

Twee aannames die geverifieerd moeten worden vóór uitvoering (zie comments hieronder):
1) De PK/identity-kolom van [dbo].[Afspraak] heet [afspraak_id].
2) [vorm_afspraak] gebruikt de schrijfwijzen 'Online' / 'Buitendienst' (Titel-case) —
   alleen 'Online' is bevestigd (hardcoded in usp_Reservering_OmzettenNaarAfspraak);
   'Buitendienst' is een aanname naar analogie.
******/
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
  @foutmelding      nvarchar(500) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  SET @foutmelding = NULL;

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

  BEGIN TRANSACTION;

  BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM [dbo].[Afspraak] WHERE [afspraak_id] = @afspraak_id)
    BEGIN
      ROLLBACK TRANSACTION;
      SET @foutmelding = N'Afspraak niet gevonden.';
      RETURN;
    END;

    UPDATE [dbo].[Afspraak]
    SET
      [adviseur_id] = @adviseur_id,
      [datum_adviesgesprek] = CAST(@datum AS datetime2),
      [tijd_adviesgesprek] = @datumTijd,
      [duur] = @duur_kwartieren,
      [vorm_afspraak] = @vormAfspraakGenormaliseerd,
      [updated_at] = GETDATE()
    WHERE [afspraak_id] = @afspraak_id;

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @foutmelding = ERROR_MESSAGE();
  END CATCH
END;
GO
