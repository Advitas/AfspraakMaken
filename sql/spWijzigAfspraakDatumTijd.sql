/****** Object:  StoredProcedure [dbo].[spWijzigAfspraakDatumTijd]
Voorstel — NOG NIET UITGEVOERD tegen SQL_DATABASE_TEST of productie.
Gebaseerd op het schema van [dbo].[Afspraak] zoals zichtbaar in
[PowerBI].[usp_Reservering_OmzettenNaarAfspraak] (aangeleverd 2026-09-03), en op de
[dbo].[actions]-insert + parameterwaarden voor "Afspraakwijziging" die daarna zijn aangeleverd
(action_type_id = PLANNING_MOVE_ACTION_TYPE_ID, state_id = 35, source = 'Manual (Swap)', enz.).

Aannames die geverifieerd moeten worden vóór uitvoering (zie comments hieronder):
1) De PK/identity-kolom van [dbo].[Afspraak] heet [afspraak_id].
2) [vorm_afspraak] gebruikt de schrijfwijzen 'Online' / 'Buitendienst' (Titel-case) —
   alleen 'Online' is bevestigd (hardcoded in usp_Reservering_OmzettenNaarAfspraak);
   'Buitendienst' is een aanname naar analogie.
3) dbo.users heeft een PK-kolom [id] (voor de creator_id-fallback hieronder).
4) Alle [actions]-kolommen die niet in de aangeleverde parametertabel stonden
   (direction, product_id, tag, communication, Oorsprong, Oorsprong_categorie,
   field_contents_4 t/m field_contents_12 behalve field_contents_1-3, insteek_id) zijn op NULL
   gezet — vul aan als het businessproces daar specifieke waarden voor verwacht.
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
    -- sale_oppertunity_id van de bestaande afspraak ophalen (nodig voor de actions-insert
    -- hieronder) en tegelijk bevestigen dat de afspraak bestaat.
    DECLARE @saleOpportunityId nvarchar(255);

    SELECT @saleOpportunityId = [saleop_id]
    FROM [dbo].[Afspraak]
    WHERE [afspraak_id] = @afspraak_id;

    IF @@ROWCOUNT = 0
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

    -- Actions-log voor de wijziging. Deze SP wordt aangeroepen door de AfspraakMaken Azure
    -- Function (function-key-auth, geen ingelogde gebruiker) — er is dus nooit een "ingelogde
    -- gebruiker"-context beschikbaar, vandaar altijd de fallback naar de eerste rij van dbo.users
    -- (zie aanname 3 hierboven; TOP 1 zonder ORDER BY is geen garantie voor een specifieke rij —
    -- voeg een ORDER BY/WHERE toe als er een vaste systeemgebruiker moet zijn).
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
      NULL,
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

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @foutmelding = ERROR_MESSAGE();
  END CATCH
END;
GO
