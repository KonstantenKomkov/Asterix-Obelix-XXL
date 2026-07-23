import copy
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task93_authored_animation_graph",
    ROOT / "scripts/task93_authored_animation_graph.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def provenance():
    rows = []
    for index in range(3):
        binding = f"asterix.binding-{index}"
        evidence = f"task93:v1:{index:064x}"
        rows.append({
            "evidenceId": evidence,
            "binding": binding,
            "runtimeState": "locomotion.idle" if index == 0 else "combat.attack",
            "trigger": {"fact": f"event-{index}", "evidenceRva": "0x00000010"},
            "guard": {"fact": f"guard-{index}", "evidenceRva": "0x00000010"},
            "operation": "start" if index == 0 else "change",
            "completion": {
                "kind": "loop" if index == 0 else "authoredClipEnd",
                "evidenceRva": "0x00000010",
            },
            "interrupt": {"policy": "action", "evidenceRva": "0x00000010"},
            "blend": {"seconds": 0.1, "evidenceRva": "0x00000010"},
            "playback": {"rate": 1.0, "evidenceRva": "0x00000010"},
            "phaseEvents": {
                "initialPhase": 0.0,
                "events": [] if index == 0 else ["completion"],
                "evidenceRva": "0x00000010",
            },
            "rootMotion": {"policy": "inPlace", "evidenceRva": "0x00000010"},
            "source": {
                "module": "GameModule.elb", "moduleSha256": "a" * 64,
                "callRva": "0x00000010", "slotReadPrimitiveRva": "0x00000020",
            },
            "dictionaryAccess": {
                "field": "CKHkHero.heroAnimDict", "dictionary": 0,
                "slot": index, "clip": f"clip-{index:04d}",
            },
            "confidence": "confirmed",
        })
    return {
        "schemaVersion": 1,
        "module": {
            "name": "GameModule.elb", "sha256": "a" * 64,
            "imageBase": "0x00400000",
        },
        "owner": "CKHkAsterix",
        "summary": {
            "bindingCount": 3, "confirmedBindingCount": 3,
            "unresolvedBindingCount": 0, "visualOnlyBindingCount": 0,
        },
        "transitions": rows,
    }


class Task93AuthoredAnimationGraphTest(unittest.TestCase):
    def _graph(self):
        with mock.patch.object(MODULE, "validate_provenance"):
            return MODULE.build_graph(provenance())

    def test_compiles_complete_versioned_runtime_resource(self):
        graph = self._graph()
        self.assertEqual(graph["schemaVersion"], 1)
        self.assertEqual(graph["resourceType"], "asterix.authored-animation-graph")
        self.assertEqual(len(graph["states"]), 3)
        self.assertEqual(len(graph["transitions"]), 3)
        self.assertEqual(graph["states"][1]["phaseEvents"], {
            "initialPhase": 0.0, "events": ["completion"]
        })
        MODULE.validate_graph(graph)

    def test_checked_in_asterix_resource_is_canonical_and_complete(self):
        path = ROOT / "assets/animation_graphs/asterix.authored-graph.v1.json"
        payload = path.read_bytes()
        graph = json.loads(payload)
        MODULE.validate_graph(graph)
        self.assertEqual(payload, MODULE.canonical_bytes(graph))
        self.assertEqual(len(graph["states"]), 90)
        self.assertEqual(len(graph["transitions"]), 90)
        self.assertEqual(
            hashlib.sha256(payload).hexdigest(),
            "47c2d557315c6cefe3b98957438ff4be4b0346f5bccd6b8c3f28d2151d6a9965",
        )

    def test_fresh_and_cached_exports_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "provenance.json"
            first = root / "fresh.json"
            second = root / "cached.json"
            source.write_text(json.dumps(provenance()))
            with mock.patch.object(MODULE, "validate_provenance"):
                fresh = MODULE.export(source, first, root / "cache")
                cached = MODULE.export(source, second, root / "cache")
            self.assertEqual(fresh, cached)
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_rejects_incomplete_graph(self):
        graph = self._graph()
        del graph["states"][0]["rootMotion"]
        with self.assertRaisesRegex(ValueError, "invalid fields"):
            MODULE.validate_graph(graph)

    def test_rejects_ambiguous_graph(self):
        graph = self._graph()
        duplicate = copy.deepcopy(graph["transitions"][0])
        duplicate["id"] = "select:duplicate"
        graph["transitions"].append(duplicate)
        with self.assertRaisesRegex(ValueError, "ambiguous transition"):
            MODULE.validate_graph(graph)

    def test_rejects_unreachable_graph(self):
        graph = self._graph()
        graph["transitions"].pop()
        with self.assertRaisesRegex(ValueError, "unreachable authored states"):
            MODULE.validate_graph(graph)

    def test_rejects_cross_profile_graph(self):
        graph = self._graph()
        graph["states"][0]["profile"] = "actor:CKHkObelix"
        with self.assertRaisesRegex(ValueError, "cross-profile state"):
            MODULE.validate_graph(graph)


if __name__ == "__main__":
    unittest.main()
