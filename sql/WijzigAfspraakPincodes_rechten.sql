/****** Rechten voor svc-AppMaakAfspraak op de nieuwe pincode-tabel + SP's.
Voer dit uit NA sql/WijzigAfspraakPincodes_tabel.sql, sql/spZoekAfspraakVoorWijziging.sql,
sql/spBewaarWijzigPincode.sql en sql/spValideerWijzigPincode.sql.
Controleer eerst wat het account al heeft (zie sql/spWijzigAfspraakDatumTijd.sql voor het check-query'tje).
******/
GRANT EXECUTE ON [dbo].[spZoekAfspraakVoorWijziging] TO [svc-AppMaakAfspraak];
GRANT EXECUTE ON [dbo].[spBewaarWijzigPincode] TO [svc-AppMaakAfspraak];
GRANT EXECUTE ON [dbo].[spValideerWijzigPincode] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Klanten] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Afspraak] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Status afspraak] TO [svc-AppMaakAfspraak];
GO
