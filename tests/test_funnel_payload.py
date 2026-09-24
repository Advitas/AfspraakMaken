"""Tests voor de payload-helpers van POST /funnel.

Draait zonder database: de helpers zijn pure functies. Uitvoeren met
.venv\\Scripts\\python.exe -m unittest discover -s tests -v
"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import function_app


def geldige_payload():
    return {
        "datum": "2026-09-30",
        "tijd": "16:00",
        "adviseur_id": "300",
        "duur_kwartieren": 2,
        "campagne_id": 77,
        "route": "funnelpicker-funnelknop",
        "funnel": '{"email":"test@example.com"}',
        "run": "test",
    }


class ValidatieTest(unittest.TestCase):
    def test_geldige_payload_gaat_door(self):
        function_app._validate_funnel_payload(geldige_payload())

    def test_ontbrekende_route_is_fout(self):
        payload = geldige_payload()
        del payload["route"]
        with self.assertRaises(function_app.ValidationError):
            function_app._validate_funnel_payload(payload)

    def test_lege_funnel_is_fout(self):
        payload = geldige_payload()
        payload["funnel"] = "   "
        with self.assertRaises(function_app.ValidationError):
            function_app._validate_funnel_payload(payload)

    def test_campaign_id_alias_wordt_geaccepteerd(self):
        payload = geldige_payload()
        payload["campaign_id"] = payload.pop("campagne_id")
        function_app._validate_funnel_payload(payload)

    def test_duur_kwartieren_nul_is_fout(self):
        payload = geldige_payload()
        payload["duur_kwartieren"] = 0
        with self.assertRaises(function_app.ValidationError):
            function_app._validate_funnel_payload(payload)


class FunnelCallTest(unittest.TestCase):
    def test_alleen_procedure_velden_gaan_mee(self):
        payload = geldige_payload()
        payload["productnaam"] = "schade.nl"
        prepared = function_app._prepare_funnel_call(payload)
        self.assertEqual(
            set(prepared),
            {"funnel", "route", "klant_id", "productnaam"},
        )
        self.assertEqual(prepared["productnaam"], "schade.nl")

    def test_klant_id_nul_wordt_none(self):
        payload = geldige_payload()
        payload["klant_id"] = 0
        self.assertIsNone(function_app._prepare_funnel_call(payload)["klant_id"])

    def test_klant_id_ontbreekt_wordt_none(self):
        self.assertIsNone(function_app._prepare_funnel_call(geldige_payload())["klant_id"])


class ReserveringPayloadTest(unittest.TestCase):
    def test_funnel_en_route_gaan_niet_mee(self):
        prepared = function_app._prepare_funnel_reservation_payload(geldige_payload(), 4242)
        self.assertNotIn("funnel", prepared)
        self.assertNotIn("route", prepared)

    def test_klant_id_komt_uit_de_eerste_procedure(self):
        payload = geldige_payload()
        payload["klant_id"] = 0
        prepared = function_app._prepare_funnel_reservation_payload(payload, 4242)
        self.assertEqual(prepared["klant_id"], 4242)

    def test_mmjo_funnel_alias_gaat_ook_niet_mee(self):
        payload = geldige_payload()
        payload["MMJO/funnel"] = payload["funnel"]
        prepared = function_app._prepare_funnel_reservation_payload(payload, 4242)
        self.assertNotIn("MMJO/funnel", prepared)
        self.assertNotIn("mmjo_funnel", prepared)


class FunnelInInformatieTest(unittest.TestCase):
    """De funnel moet altijd leesbaar in het informatie-veld van de reservering belanden.

    spMaakReservering vult @funnel_readable alleen bij campagne_id 230, dus voor elke andere
    campagne levert het endpoint die tekst zelf aan.
    """

    def test_leesbare_regels_per_veld(self):
        payload = geldige_payload()
        payload["funnel"] = json.dumps({"naam": "Testpersoon Advitas", "email": "test@example.com"})
        informatie = function_app._prepare_funnel_reservation_payload(payload, 1)["informatie"]
        self.assertIn("=== FUNNEL GEGEVENS ===", informatie)
        self.assertIn("Naam: Testpersoon Advitas", informatie)
        self.assertIn("Email: test@example.com", informatie)

    def test_onderstrepingen_worden_spaties(self):
        payload = geldige_payload()
        payload["funnel"] = json.dumps({"gewenste_opname": 25000})
        informatie = function_app._prepare_funnel_reservation_payload(payload, 1)["informatie"]
        self.assertIn("Gewenste opname: 25000", informatie)

    def test_genest_object_wordt_platgeslagen(self):
        payload = geldige_payload()
        payload["funnel"] = json.dumps({"contact": {"naam": "Jan", "telefoon": "0612345678"}})
        informatie = function_app._prepare_funnel_reservation_payload(payload, 1)["informatie"]
        self.assertIn("Naam: Jan", informatie)
        self.assertIn("Telefoon: 0612345678", informatie)
        self.assertNotIn("Contact:", informatie)

    def test_lege_waarden_vallen_weg(self):
        payload = geldige_payload()
        payload["funnel"] = json.dumps({"naam": "Jan", "toevoeging": "", "opmerking": None})
        informatie = function_app._prepare_funnel_reservation_payload(payload, 1)["informatie"]
        self.assertIn("Naam: Jan", informatie)
        self.assertNotIn("Toevoeging", informatie)
        self.assertNotIn("Opmerking", informatie)

    def test_bestaande_informatie_blijft_staan_en_komt_eerst(self):
        payload = geldige_payload()
        payload["informatie"] = "Klant belde zelf."
        payload["funnel"] = json.dumps({"naam": "Jan"})
        informatie = function_app._prepare_funnel_reservation_payload(payload, 1)["informatie"]
        self.assertTrue(informatie.startswith("Klant belde zelf."))
        self.assertIn("Naam: Jan", informatie)

    def test_ongeldige_json_gaat_alsnog_mee(self):
        payload = geldige_payload()
        payload["funnel"] = "adsadfsafasfsf"
        informatie = function_app._prepare_funnel_reservation_payload(payload, 1)["informatie"]
        self.assertIn("adsadfsafasfsf", informatie)

    def test_funnel_als_object_werkt_ook(self):
        payload = geldige_payload()
        payload["funnel"] = {"naam": "Jan"}
        informatie = function_app._prepare_funnel_reservation_payload(payload, 1)["informatie"]
        self.assertIn("Naam: Jan", informatie)

    def test_booleans_worden_ja_of_nee(self):
        payload = geldige_payload()
        payload["funnel"] = json.dumps({"akkoord": True, "nieuwsbrief": False})
        informatie = function_app._prepare_funnel_reservation_payload(payload, 1)["informatie"]
        self.assertIn("Akkoord: ja", informatie)
        self.assertIn("Nieuwsbrief: nee", informatie)


if __name__ == "__main__":
    unittest.main()
