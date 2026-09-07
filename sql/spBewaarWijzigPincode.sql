/****** Object: StoredProcedure [dbo].[spBewaarWijzigPincode]
Voorstel — NOG NIET UITGEVOERD. Slaat een nieuw gegenereerde pincode op in [dbo].[WijzigAfspraakPincodes]
(zie sql/WijzigAfspraakPincodes_tabel.sql — voer die eerst uit). Vervangt de eerdere
Azure Table Storage-opslag. Eén actieve pincode per afspraak_id: een nieuwe aanvraag voor dezelfde
afspraak verwijdert het oude record.
******/
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
