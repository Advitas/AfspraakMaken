/****** Rechten voor svc-AppMaakAfspraak op de wijzig-afspraak-tabel + SP's.
Voer dit uit NA sql/WijzigAfspraakPincodes_tabel.sql, sql/spZoekAfspraakVoorWijziging.sql,
sql/spBewaarWijzigPincode.sql, sql/spValideerWijzigPincode.sql en sql/spWijzigAfspraakDatumTijd.sql.
Controleer eerst wat het account al heeft (zie sql/spWijzigAfspraakDatumTijd.sql voor het check-query'tje).

GRANT-statements zijn van zichzelf al idempotent (opnieuw uitvoeren geeft geen fout) — dit bestand
kan dus zonder nadenken herhaald worden. Bijgewerkt op 2026-09-07: bevat nu ook de rechten die
sql/spWijzigAfspraakDatumTijd.sql en de postcode-uit-adres-wijziging nodig hebben (was eerder
onvolledig t.o.v. het GRANT-blok in sql/alles_in_1_wijzig_afspraak.sql — nu gelijkgetrokken).
******/
GRANT EXECUTE ON [dbo].[spZoekAfspraakVoorWijziging] TO [svc-AppMaakAfspraak];
GRANT EXECUTE ON [dbo].[spBewaarWijzigPincode] TO [svc-AppMaakAfspraak];
GRANT EXECUTE ON [dbo].[spValideerWijzigPincode] TO [svc-AppMaakAfspraak];
GRANT EXECUTE ON [dbo].[spWijzigAfspraakDatumTijd] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Klanten] TO [svc-AppMaakAfspraak];
GRANT SELECT, UPDATE ON [dbo].[Afspraak] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Status afspraak] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[Adres] TO [svc-AppMaakAfspraak];
GRANT INSERT ON [dbo].[actions] TO [svc-AppMaakAfspraak];
GRANT SELECT ON [dbo].[users] TO [svc-AppMaakAfspraak];
GRANT DELETE ON [dbo].[WijzigAfspraakPincodes] TO [svc-AppMaakAfspraak];
GO
