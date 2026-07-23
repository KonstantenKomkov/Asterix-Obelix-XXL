import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task91_world_cinematics_profile",
    ROOT / "scripts/task91_world_cinematics_profile.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class WorldCinematicsProfileTest(unittest.TestCase):
    def test_parses_exact_numeric_dictionary_selector(self):
        self.assertEqual(MODULE._dictionary_slot("dictionary_slot_42"), 42)
        self.assertEqual(MODULE._selector("dictionary-48-slot-42"), (48, 42))

    def test_rejects_non_numeric_or_malformed_selectors(self):
        with self.assertRaisesRegex(ValueError, "numeric dictionary binding"):
            MODULE._dictionary_slot("idle")
        with self.assertRaisesRegex(ValueError, "dictionary selector"):
            MODULE._selector("dictionary-48-clip-42")

    def test_config_covers_world_and_cinematic_gates(self):
        config = json.loads(
            (
                ROOT / "tools/task91/world_cinematics_profile.v1.json"
            ).read_text()
        )
        self.assertEqual(len(config["worldProfiles"]), 13)
        self.assertEqual(
            {
                int(row["profile"].removeprefix("world-dictionary-"))
                for row in config["worldProfiles"]
            },
            {19, 20, 21, 22, 23, 24, 25, 26, 29, 30, 49, 50, 51},
        )
        self.assertEqual(config["expectedWorldBindingCount"], 46)
        self.assertEqual(config["expectedCinematicTimelineCount"], 14)
        self.assertEqual(config["expectedCinematicCueCount"], 63)


if __name__ == "__main__":
    unittest.main()
