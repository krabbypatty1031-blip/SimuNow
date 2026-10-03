"""Seat sampling accounts for every seat; invalid points are omitted, not 0.

Seat T and |U| must come from the solve-mesh cell fields. A seat outside the
fluid is omitted with a reason; it never becomes a fabricated room value.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
P1 = ROOT / "test" / "p1"
if str(P1) not in sys.path:
    sys.path.insert(0, str(P1))

from run_room import sample_seats  # noqa: E402


def _room(seats: list[dict]) -> dict:
    return {
        "size": {"x_m": {"value": 6}, "y_m": {"value": 6}, "z_m": {"value": 2.8}},
        "seats": seats,
    }


class SampleSeatsTests(unittest.TestCase):
    def test_out_of_room_seat_is_omitted_not_fabricated(self):
        room = _room(
            [
                {"id": "S1", "x_m": 1.5, "y_m": 1.5, "z_m": 1.1},
                {"id": "S9", "x_m": 7.0, "y_m": 3.0, "z_m": 1.1},
            ]
        )
        # Two solve-mesh cells; cell 0 sits exactly at seat S1 (foam Y-up).
        result = sample_seats(
            room,
            temperature=[300.15, 295.15],
            velocity=[(1.0, 0.0, 0.0), (0.0, 0.0, 0.0)],
            cx=[1.5, 5.0],
            cy=[1.1, 1.1],
            cz=[1.5, 3.0],
        )
        seats = result["seats"]
        self.assertEqual([seat["id"] for seat in seats], ["S1"])
        # Seat values are the solve-mesh cell values, K -> C via seat_sample.
        self.assertAlmostEqual(seats[0]["T_C"], 27.0)
        self.assertAlmostEqual(seats[0]["U_mag"], 1.0)
        self.assertEqual(seats[0]["x"], 1.5)
        self.assertEqual(seats[0]["z"], 1.1)

        omitted = result["omitted_seats"]
        self.assertEqual(len(omitted), 1)
        self.assertEqual(omitted[0]["id"], "S9")
        self.assertTrue(omitted[0]["omitted"])
        self.assertEqual(omitted[0]["reason"], "not_in_fluid")

    def test_every_seat_is_accounted_for(self):
        room = _room(
            [
                {"id": "S1", "x_m": 1.5, "y_m": 1.5, "z_m": 1.1},
                {"id": "S2", "x_m": 4.5, "y_m": 4.5, "z_m": 1.1},
                {"id": "S3", "x_m": 3.0, "y_m": 3.0, "z_m": 5.0},
            ]
        )
        result = sample_seats(
            room,
            temperature=[298.15, 299.15],
            velocity=[(0.0, 0.0, 0.2), (0.0, 0.0, 0.0)],
            cx=[1.5, 4.5],
            cy=[1.1, 1.1],
            cz=[1.5, 4.5],
        )
        sampled = len(result["seats"])
        omitted = len(result["omitted_seats"])
        # No silent drops: sampled + omitted must equal the seat count.
        self.assertEqual(sampled + omitted, 3)
        self.assertEqual([row["id"] for row in result["omitted_seats"]], ["S3"])
        self.assertTrue(all(row["reason"] == "not_in_fluid" for row in result["omitted_seats"]))

    def test_seat_values_are_solve_mesh_cells_not_display_resamples(self):
        # Two cells at different temperatures; the seat sits next to the
        # hotter cell. Whatever a display slice later interpolates, the seat
        # value is the nearest solve-mesh cell.
        room = _room([{"id": "S1", "x_m": 2.0, "y_m": 1.5, "z_m": 1.1}])
        result = sample_seats(
            room,
            temperature=[303.15, 293.15],
            velocity=[(0.0, 0.3, 0.0), (0.0, 0.0, 0.0)],
            cx=[1.9, 5.0],
            cy=[1.1, 1.1],
            cz=[1.4, 1.4],
        )
        seat = result["seats"][0]
        self.assertAlmostEqual(seat["T_C"], 30.0)
        self.assertAlmostEqual(seat["U_mag"], 0.3)


if __name__ == "__main__":
    unittest.main()
