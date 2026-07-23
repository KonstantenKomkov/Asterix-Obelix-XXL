import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task91_final_acceptance", ROOT / "scripts/task91_final_acceptance.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalAcceptanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = json.loads(
            (ROOT / "assets/animation_bindings.v1.json").read_text()
        )
        bindings = cls.registry["bindings"]
        evidence = []
        next_slot = 0
        reserved_slots = {13, 35}
        for profile in cls.registry["runtimeProfiles"]:
            for state, selector in profile["states"].items():
                binding = next(
                    row
                    for row in bindings
                    if row["actor"] == profile["actor"]
                    and row["skin"] == profile["skin"]
                    and row["costume"] == profile["costume"]
                    and row["context"] == profile["context"]
                    and row["action"] == selector["action"]
                    and row["variant"] == selector["variant"]
                )
                key = f"{profile['id']}:{state}"
                if key == "asterix-player:jump":
                    slot = 13
                elif key == "asterix-player:double_jump":
                    slot = 35
                else:
                    while next_slot in reserved_slots:
                        next_slot += 1
                    slot = next_slot
                    next_slot += 1
                clip = f"clip-{binding['clip'].removesuffix('.animation.json')}"
                evidence.append(
                    {
                        "bindingKey": key,
                        "profile": profile["id"],
                        "binding": state,
                        "evidenceId": f"synthetic:{len(evidence):04d}",
                        "assetJoin": {"dictionary": 0, "slot": slot, "clip": clip},
                        "stateOrEvent": {
                            "kind": "runtimeState",
                            "value": selector["action"],
                        },
                    }
                )
        cls.provenance = {"evidence": evidence}
        sources = sorted({row["clip"] for row in bindings})
        cls.catalog = {
            "clipCount": 345,
            "dictionaryCount": 52,
            "dictionaries": [
                {"slots": [None] * 518},
                *({"slots": []} for _ in range(51)),
            ],
            "clips": [{"source": source} for source in sources],
        }
        assert len(sources) == 345

    def _finalize(self, catalog=None, registry=None, provenance=None):
        with mock.patch.object(MODULE.task91_provenance_gate, "validate"), mock.patch.object(
            MODULE, "_sha256", wraps=MODULE._sha256
        ) as digest:
            digest.side_effect = lambda value: (
                MODULE.EXPECTED_PROVENANCE_SHA256
                if value is (provenance or self.provenance)
                else MODULE.hashlib.sha256(MODULE._canonical_bytes(value)).hexdigest()
            )
            return MODULE.finalize(
                copy.deepcopy(catalog or self.catalog),
                copy.deepcopy(registry or self.registry),
                provenance or self.provenance,
            )

    def test_accepts_all_bindings_and_separate_jump_chains(self):
        catalog, registry, report = self._finalize()
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["summary"]["confirmedBindings"], 408)
        self.assertEqual(report["summary"]["unresolvedBindings"], 0)
        self.assertEqual(report["summary"]["ambiguousBindings"], 0)
        self.assertEqual(report["summary"]["visualOnlyBindings"], 0)
        self.assertEqual(
            report["jumpAssertions"]["asterix-player:jump"]["slot"], 13
        )
        self.assertEqual(
            report["jumpAssertions"]["asterix-player:double_jump"]["slot"], 35
        )
        self.assertEqual(catalog["authoredBindingProvenance"]["confirmedBindings"], 408)
        self.assertEqual(registry["authoredBindingProvenance"]["confirmedBindings"], 408)

    def test_rejects_registry_clip_drift(self):
        registry = copy.deepcopy(self.registry)
        profile = next(
            row for row in registry["runtimeProfiles"] if row["id"] == "asterix-player"
        )
        profile["states"]["jump"]["variant"] = "clip-0064"
        with self.assertRaisesRegex(ValueError, "exact binding|disagrees"):
            self._finalize(registry=registry)

    def test_rejects_catalog_slot_drift(self):
        catalog = copy.deepcopy(self.catalog)
        clip = next(row for row in catalog["clips"] if row["source"] == "0031.animation.json")
        clip["source"] = "missing.animation.json"
        with self.assertRaisesRegex(ValueError, "catalog clip disagrees"):
            self._finalize(catalog=catalog)


if __name__ == "__main__":
    unittest.main()
