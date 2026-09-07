/****** Object: Table [dbo].[WijzigAfspraakPincodes]
Voorstel — NOG NIET UITGEVOERD. Vervangt de Azure Table Storage-opslag van pincodes door een SQL-tabel
(op verzoek van de gebruiker, 2026-09-03) — één actieve pincode per afspraak_id.
******/
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
GO

CREATE INDEX [IX_WijzigAfspraakPincodes_email] ON [dbo].[WijzigAfspraakPincodes] ([email]);
GO

CREATE INDEX [IX_WijzigAfspraakPincodes_afspraak_id] ON [dbo].[WijzigAfspraakPincodes] ([afspraak_id]);
GO
