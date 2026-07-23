import copy
import importlib.util
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task93_asterix_behaviour", ROOT / "scripts/task93_asterix_behaviour.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeImage:
    image_base = 0x400000

    def __init__(self, _path):
        self.data = bytearray(0x100)

    def offset_from_rva(self, _rva):
        return 0


class Task93AsterixBehaviourTest(unittest.TestCase):
    def setUp(self):
        self.config = json.loads(
            (ROOT / "tools/task93/asterix_behaviour.v1.json").read_text()
        )
        self.bindings = []
        for index, state in enumerate(self.config["policies"]):
            self.bindings.append({
                "binding": f"binding-{index}", "runtimeState": state,
                "dictionary": 0, "slot": index, "clip": f"clip-{index:04d}",
                "confidence": "confirmed",
            })
        while len(self.bindings) < 90:
            index = len(self.bindings)
            self.bindings.append({
                "binding": f"binding-{index}", "runtimeState": "locomotion.idle",
                "dictionary": 0, "slot": index, "clip": f"clip-{index:04d}",
                "confidence": "confirmed",
            })
        self.profile = {
            "module": {"sha256": "a" * 64}, "owner": "CKHkAsterix",
            "bindings": self.bindings,
        }

    def _report(self, config=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = root / "profile.json"
            config_path = root / "config.json"
            profile.write_text(json.dumps(self.profile))
            config_path.write_text(json.dumps(config or self.config))
            with mock.patch.object(MODULE, "sha256", return_value="a" * 64), \
                    mock.patch.object(MODULE, "PeImage", FakeImage), \
                    mock.patch.object(MODULE, "_validate_call"):
                return MODULE.report(
                    root / "GameModule.elb", profile, config_path, "a" * 64
                )

    def test_exports_closed_deterministic_metadata_only_dataset(self):
        first = self._report()
        second = self._report()
        self.assertEqual(first, second)
        self.assertEqual(first["summary"]["confirmedBindingCount"], 90)
        self.assertEqual(first["summary"]["unresolvedBindingCount"], 0)
        self.assertEqual(first["summary"]["visualOnlyBindingCount"], 0)
        jump = next(row for row in first["transitions"] if row["runtimeState"] == "locomotion.jump")
        self.assertEqual(jump["dictionaryAccess"]["dictionary"], 0)
        self.assertIn("trigger", jump)
        self.assertIn("rootMotion", jump)

    def test_rejects_missing_policy_fact(self):
        config = copy.deepcopy(self.config)
        del config["policies"]["locomotion.jump"]["guard"]
        with self.assertRaisesRegex(ValueError, "incomplete behavioural policy"):
            self._report(config)

    def test_rejects_unconfirmed_input_profile(self):
        self.profile["bindings"][0]["confidence"] = "unresolved"
        with self.assertRaisesRegex(ValueError, "unresolved evidence"):
            self._report()

    def test_rejects_visual_only_and_incomplete_phase(self):
        dataset = self._report()
        dataset["transitions"][0]["confidence"] = "visual-only"
        with self.assertRaisesRegex(ValueError, "visual-only"):
            MODULE.validate(dataset)
        dataset = self._report()
        del dataset["transitions"][0]["phaseEvents"]
        with self.assertRaisesRegex(ValueError, "missing"):
            MODULE.validate(dataset)

    def test_validates_relative_call_target(self):
        image = FakeImage(None)
        image.data[0] = 0xE8
        struct.pack_into("<i", image.data, 1, 0x20 - 5)
        MODULE._validate_call(image, 0, 0x20)
        with self.assertRaisesRegex(ValueError, "another animation primitive"):
            MODULE._validate_call(image, 0, 0x21)


if __name__ == "__main__":
    unittest.main()
