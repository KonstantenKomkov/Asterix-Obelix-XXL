import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task91_enemies_scripted_profile",
    ROOT / "scripts/task91_enemies_scripted_profile.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class EnemiesScriptedProfileTest(unittest.TestCase):
    def test_parses_exact_numeric_dictionary_selector(self):
        self.assertEqual(MODULE._dictionary_slot("dictionary_slot_42"), 42)
        self.assertEqual(MODULE._selector("dictionary-48-slot-42"), (48, 42))

    def test_rejects_non_numeric_or_malformed_selectors(self):
        with self.assertRaisesRegex(ValueError, "numeric dictionary binding"):
            MODULE._dictionary_slot("idle")
        with self.assertRaisesRegex(ValueError, "dictionary selector"):
            MODULE._selector("dictionary-48-clip-42")

    def test_extracts_authored_clip_id(self):
        self.assertEqual(
            MODULE._clip_id({"clip": "0199.animation.json"}), "clip-0199"
        )

    def test_config_covers_enemy_and_scripted_gates(self):
        config = json.loads(
            (
                ROOT / "tools/task91/enemies_scripted_profile.v1.json"
            ).read_text()
        )
        self.assertEqual(
            {row["profile"] for row in config["enemyProfiles"]},
            {
                "basic-roman-enemy",
                "roman-leader-equipment",
                "roman-leader-body",
            },
        )
        self.assertEqual(config["expectedEnemyBindingCount"], 85)
        self.assertEqual(config["expectedScriptedOwnerCount"], 24)
        self.assertEqual(config["compositeLeader"]["synchronizedSlots"], [0, 1, 2])


if __name__ == "__main__":
    unittest.main()
