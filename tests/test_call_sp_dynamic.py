"""Tests voor de SQL die _call_sp_dynamic genereert.

Draait zonder database: sys.parameters wordt vervangen door een vaste lijst en de cursor legt
alleen vast welke SQL en welke argumenten hij krijgt. Uitvoeren met
.venv\\Scripts\\python.exe -m unittest discover -s tests -v
"""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import function_app


class VastleggendeCursor:
    """Vangt de aanroep op zonder iets uit te voeren."""

    def __init__(self):
        self.sql = None
        self.args = None
        self.description = None

    def execute(self, sql, *args):
        self.sql = sql
        self.args = args

    def fetchall(self):
        return []

    def nextset(self):
        return False


def parameter(naam, sql_type, is_output=False, max_length=200, precision=0, scale=0):
    return {
        "name": naam,
        "sql_type": sql_type,
        "max_length": max_length,
        "precision": precision,
        "scale": scale,
        "is_output": is_output,
    }


def roep_aan(parameters, payload):
    cursor = VastleggendeCursor()
    with patch.object(function_app, "_get_sp_parameters", return_value=parameters):
        function_app._call_sp_dynamic(cursor, "dbo", "spTest", payload)
    return cursor


FUNNEL_JSON = '{"naam":"Testpersoon","email":"test@example.com"}'


class OutputNaInputTest(unittest.TestCase):
    """De vorm van spFunnelCreateOrCheck: twee inputs, daarna een OUTPUT met een waarde.

    De DECLARE-regel staat in de gegenereerde tekst vóór de EXEC, dus haar argument hoort ook
    vooraan. Verzamel je de argumenten in parametervolgorde, dan krijgt DECLARE @out_klant_id INT
    de funnel-string en geeft SQL Server "Conversion failed ... to data type int".
    """

    PARAMETERS = [
        parameter("@funnel", "nvarchar", max_length=-1),
        parameter("@route", "nvarchar"),
        parameter("@klant_id", "int", is_output=True, max_length=4, precision=10),
    ]

    def test_declare_argument_staat_vooraan(self):
        cursor = roep_aan(
            self.PARAMETERS,
            {"funnel": FUNNEL_JSON, "route": "funnelpicker-funnelknop", "klant_id": 2536},
        )
        self.assertEqual(cursor.args, (2536, FUNNEL_JSON, "funnelpicker-funnelknop"))

    def test_declare_regel_komt_eerst_in_de_tekst(self):
        cursor = roep_aan(
            self.PARAMETERS,
            {"funnel": FUNNEL_JSON, "route": "funnelpicker-funnelknop", "klant_id": 2536},
        )
        self.assertTrue(cursor.sql.startswith("DECLARE @out_klant_id int"))

    def test_zonder_klant_id_geen_extra_argument(self):
        cursor = roep_aan(self.PARAMETERS, {"funnel": FUNNEL_JSON, "route": "r"})
        self.assertEqual(cursor.args, (FUNNEL_JSON, "r"))


class OutputEersteTest(unittest.TestCase):
    """De vorm van spMaakReservering: OUTPUT-parameters met een waarde staan vooraan.

    Deze volgorde werkte al en moet exact hetzelfde blijven - dit is de bewaking dat de fix
    /reservering niet raakt.
    """

    PARAMETERS = [
        parameter("@klant_id", "int", is_output=True, max_length=4, precision=10),
        parameter("@campagne_id", "int", is_output=True, max_length=4, precision=10),
        parameter("@adviseur_id", "nvarchar"),
        parameter("@datum", "nvarchar"),
        parameter("@foutcode", "int", is_output=True, max_length=4, precision=10),
    ]

    def test_argumentvolgorde_blijft_ongewijzigd(self):
        cursor = roep_aan(
            self.PARAMETERS,
            {
                "klant_id": 1,
                "campagne_id": 77,
                "adviseur_id": "300",
                "datum": "2026-09-30",
            },
        )
        self.assertEqual(cursor.args, (1, 77, "300", "2026-09-30"))

    def test_output_zonder_waarde_levert_geen_argument(self):
        cursor = roep_aan(
            self.PARAMETERS,
            {"klant_id": 1, "campagne_id": 77, "adviseur_id": "300", "datum": "2026-09-30"},
        )
        self.assertIn("DECLARE @out_foutcode int;", cursor.sql)
        self.assertEqual(len(cursor.args), 4)


class ZonderOutputTest(unittest.TestCase):
    """De vorm van de availability-procedures: geen OUTPUT-parameters.

    Zonder DECLARE-argumenten kan de volgorde niet verschuiven; dit is de bewaking dat de fix
    /availability niet raakt.
    """

    PARAMETERS = [
        parameter("@Datum", "nvarchar"),
        parameter("@MonthView", "bit", max_length=1),
    ]

    def test_argumentvolgorde_blijft_ongewijzigd(self):
        cursor = roep_aan(self.PARAMETERS, {"datum": "2026-09-01", "monthview": True})
        self.assertEqual(cursor.args, ("2026-09-01", 1))


if __name__ == "__main__":
    unittest.main()
