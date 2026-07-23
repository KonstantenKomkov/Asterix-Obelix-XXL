import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task91_controlled_heroes_profile",
    ROOT / "scripts/task91_controlled_heroes_profile.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ControlledHeroesProfileTest(unittest.TestCase):
    def test_maps_named_and_numeric_profile_slots(self):
        profile = {
            "states": {
                "run": {"action": "locomotion.run", "variant": "clip-0187"},
                "hero_slot_5": {
                    "action": "locomotion.move-directional",
                    "variant": "clip-0187-move-directional",
                },
            }
        }
        rows = MODULE._profile_rows(profile, {"namedStateSlots": {"run": 2}})
        self.assertEqual([row["slot"] for row in rows], [2, 5])
        self.assertEqual({row["clip"] for row in rows}, {"clip-0187"})

    def test_reused_clip_keeps_separate_runtime_bindings(self):
        rows = [
            {"clip": "clip-0176", "slot": 0},
            {"clip": "clip-0176", "slot": 12},
            {"clip": "clip-0177", "slot": 84},
        ]
        reuse = MODULE._validate_reuse(rows, {"clip-0176": [0, 12]})
        self.assertEqual(reuse[0]["bindingCount"], 2)
        self.assertTrue(reuse[0]["separateRuntimeBindings"])

    def test_rejects_unexpected_reuse(self):
        rows = [
            {"clip": "clip-0176", "slot": 0},
            {"clip": "clip-0176", "slot": 12},
        ]
        with self.assertRaisesRegex(ValueError, "reused authored clips changed"):
            MODULE._validate_reuse(rows, {})

    def test_config_covers_both_remaining_controlled_heroes(self):
        config = json.loads(
            (
                ROOT / "tools/task91/controlled_heroes_profile.v1.json"
            ).read_text()
        )
        self.assertEqual(
            {row["owner"] for row in config["profiles"]},
            {"CKHkObelix", "CKHkIdefix"},
        )
        self.assertEqual(
            sum(row["expectedBindingCount"] for row in config["profiles"]), 100
        )


if __name__ == "__main__":
    unittest.main()
