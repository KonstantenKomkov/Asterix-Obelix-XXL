import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task91_provenance_gate", ROOT / "scripts/task91_provenance_gate.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProvenanceGateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bindings = json.loads(
            (ROOT / "assets/animation_bindings.v1.json").read_text()
        )
        rows = []
        for index, key in enumerate(sorted(MODULE._runtime_keys(cls.bindings))):
            profile, binding = key.split(":", 1)
            rows.append(
                {
                    "evidenceId": f"task91:v1:{index:064x}",
                    "bindingKey": key,
                    "profile": profile,
                    "binding": binding,
                    "owner": "SyntheticOwner",
                    "source": {
                        "module": MODULE.EXPECTED_MODULE,
                        "sha256": MODULE.EXPECTED_HASH,
                        "ownerVtableRva": "0x00000001",
                        "dispatchRva": "0x00000002",
                    },
                    "stateOrEvent": {
                        "kind": "numericStateOrEvent",
                        "value": index,
                    },
                    "dictionaryAccess": {"field": "animDict", "dictionary": 0},
                    "slotSelection": {
                        "kind": "numericRuntimeBinding",
                        "slot": index,
                    },
                    "assetJoin": {
                        "dictionary": 0,
                        "slot": index,
                        "clip": f"clip-{index:04d}",
                    },
                    "confidence": "confirmed",
                    "evidenceKinds": [
                        "staticDataFlow",
                        "runtimeBinding",
                        "authoredAssetJoin",
                    ],
                }
            )
        cls.dataset = {
            "schemaVersion": 1,
            "module": {
                "name": MODULE.EXPECTED_MODULE,
                "sha256": MODULE.EXPECTED_HASH,
                "imageBase": "0x00400000",
            },
            "summary": {
                "runtimeBindingCount": 408,
                "confirmedBindingCount": 408,
                "unresolvedBindingCount": 0,
                "ambiguousBindingCount": 0,
                "visualOnlyBindingCount": 0,
                "membershipOnlyBindingCount": 0,
            },
            "evidence": rows,
        }

    def test_accepts_complete_bijection(self):
        MODULE.validate(copy.deepcopy(self.dataset), self.bindings)

    def test_published_schema_is_versioned_and_requires_408(self):
        schema = json.loads(
            (ROOT / "tools/task91/provenance.schema.v1.json").read_text()
        )
        self.assertEqual(schema["properties"]["schemaVersion"]["const"], 1)
        self.assertEqual(schema["properties"]["evidence"]["minItems"], 408)
        self.assertEqual(schema["properties"]["evidence"]["maxItems"], 408)

    def test_rejects_duplicate_and_missing_runtime_evidence(self):
        dataset = copy.deepcopy(self.dataset)
        dataset["evidence"][-1] = copy.deepcopy(dataset["evidence"][0])
        with self.assertRaisesRegex(ValueError, "duplicate evidence"):
            MODULE.validate(dataset, self.bindings)

    def test_rejects_cross_version_evidence(self):
        dataset = copy.deepcopy(self.dataset)
        dataset["evidence"][0]["source"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "cross-version"):
            MODULE.validate(dataset, self.bindings)

    def test_rejects_incomplete_membership_only_evidence(self):
        dataset = copy.deepcopy(self.dataset)
        dataset["evidence"][0]["dictionaryAccess"]["field"] = ""
        with self.assertRaisesRegex(ValueError, "membership-only"):
            MODULE.validate(dataset, self.bindings)

    def test_rejects_visual_only_or_ambiguous_evidence(self):
        dataset = copy.deepcopy(self.dataset)
        dataset["evidence"][0]["confidence"] = "visual-only"
        with self.assertRaisesRegex(ValueError, "visual-only"):
            MODULE.validate(dataset, self.bindings)

    def test_rejects_broken_dictionary_slot_clip_join(self):
        dataset = copy.deepcopy(self.dataset)
        dataset["evidence"][0]["assetJoin"]["slot"] += 1
        with self.assertRaisesRegex(ValueError, "join is incomplete"):
            MODULE.validate(dataset, self.bindings)


if __name__ == "__main__":
    unittest.main()
