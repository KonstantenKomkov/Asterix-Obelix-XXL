import importlib.util
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task91_asterix_profile", ROOT / "scripts/task91_asterix_profile.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeImage:
    def __init__(self):
        self.data = bytearray(32)

    def offset_from_rva(self, rva):
        return rva


class AsterixProfileTest(unittest.TestCase):
    def test_validates_relative_slot_read_call(self):
        image = FakeImage()
        image.data[4] = 0xE8
        struct.pack_into("<i", image.data, 5, 20 - 9)
        MODULE._validate_relative_call(image, 4, 20)

    def test_rejects_call_to_another_primitive(self):
        image = FakeImage()
        image.data[4] = 0xE8
        struct.pack_into("<i", image.data, 5, 21 - 9)
        with self.assertRaisesRegex(ValueError, "another primitive"):
            MODULE._validate_relative_call(image, 4, 20)

    def test_maps_named_and_numeric_profile_slots(self):
        profile = {
            "states": {
                "jump": {"action": "locomotion.jump", "variant": "clip-a"},
                "hero_slot_7": {
                    "action": "locomotion.move",
                    "variant": "clip-b",
                },
            }
        }
        rows = MODULE._profile_slots(profile, {"jump": 13})
        self.assertEqual([row["slot"] for row in rows], [7, 13])

    def test_config_has_separate_single_and_double_jump_chains(self):
        config = json.loads(
            (ROOT / "tools/task91/asterix_profile.v1.json").read_text()
        )
        chains = config["jumpChains"]
        self.assertEqual({row["semantic"] for row in chains}, {"singleJump", "doubleJump"})
        self.assertEqual(len({row["slot"] for row in chains}), 2)
        self.assertNotEqual(chains[0]["inputTrace"], chains[1]["inputTrace"])


if __name__ == "__main__":
    unittest.main()
