import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from maintenance_heartbeat import HEARTBEAT_SECONDS, heartbeat_due


class MaintenanceHeartbeatTests(unittest.TestCase):
    def test_fresh_and_29_days_are_not_due(self):
        now = 2_000_000_000
        self.assertFalse(heartbeat_due(now, now))
        self.assertFalse(heartbeat_due(now - 29 * 24 * 60 * 60, now))

    def test_exact_30_day_boundary_is_due(self):
        now = 2_000_000_000
        self.assertEqual(HEARTBEAT_SECONDS, 30 * 24 * 60 * 60)
        self.assertTrue(heartbeat_due(now - HEARTBEAT_SECONDS, now))

    def test_future_commit_is_not_due(self):
        self.assertFalse(heartbeat_due(2_000_000_001, 2_000_000_000))

    def test_negative_and_non_integer_epochs_are_rejected(self):
        for value in (-1, 1.5, True):
            with self.subTest(value=value), self.assertRaises(ValueError):
                heartbeat_due(value, 10)
        with self.assertRaises(ValueError):
            heartbeat_due(0, -1)


if __name__ == "__main__":
    unittest.main()
