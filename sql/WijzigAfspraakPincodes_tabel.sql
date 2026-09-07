/****** Object: Table [dbo].[WijzigAfspraakPincodes]
Vervangt de Azure Table Storage-opslag van pincodes door een SQL-tabel (op verzoek van de gebruiker,
2026-09-03) — één actieve pincode per afspraak_id.

Idempotent (IF NOT EXISTS) — veilig om opnieuw uit te voeren, ook als de tabel/indexen al bestaan.
******/
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
