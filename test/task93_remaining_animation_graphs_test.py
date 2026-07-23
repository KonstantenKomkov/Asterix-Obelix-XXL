import copy
import hashlib
import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task93_remaining_animation_graphs",
    ROOT / "scripts/task93_remaining_animation_graphs.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Task93RemainingAnimationGraphsTest(unittest.TestCase):
    def setUp(self):
        self.registry = json.loads(
            (ROOT / "assets/animation_bindings.v1.json").read_text()
        )

    def test_checked_in_resource_covers_all_remaining_bindings(self):
        path = ROOT / "assets/animation_graphs/actors.authored-graphs.v1.json"
        payload = path.read_bytes()
        resource = json.loads(payload)
        MODULE.validate_resource(resource)
        self.assertEqual(payload, MODULE.canonical_bytes(resource))
        self.assertEqual(resource["summary"], {
            "profileCount": 56,
            "bindingCount": 318,
            "controllerBindings": 209,
            "simultaneousTrackBindings": 46,
            "timelineBindings": 63,
        })
        self.assertEqual(payload, MODULE.canonical_bytes(
            MODULE.build_resource(self.registry)
        ))

    def test_world_transaction_preserves_simultaneous_tracks(self):
        resource = MODULE.build_resource(self.registry)
        shop = next(p for p in resource["profiles"] if p["id"] == "world-dictionary-20")
        transaction = next(
            event for event in shop["events"]
            if event["id"] == "interaction-event:shop.transaction"
        )
        self.assertEqual(
            transaction["states"], ["dictionary_slot_1", "dictionary_slot_4"]
        )
        self.assertEqual(shop["dispatchMode"], "simultaneous-track-adapter")

    def test_cinematics_have_ordered_typed_cues_and_terminal_states(self):
        resource = MODULE.build_resource(self.registry)
        scene = next(
            p for p in resource["profiles"] if p["id"] == "cinematic-scene-data-1"
        )
        self.assertEqual(scene["dispatchMode"], "timeline-adapter")
        self.assertEqual(
            [event["id"] for event in scene["events"]],
            [f"script.cinematic.scene-data-1:cue-{index}" for index in range(8)],
        )
        self.assertEqual(scene["terminalStates"], ["dictionary_slot_7"])
        self.assertEqual(scene["states"][-1]["completion"], "terminal")

    def test_dictionary_slots_are_never_inferred_from_skin(self):
        resource = MODULE.build_resource(self.registry)
        scripted = next(
            p for p in resource["profiles"] if p["id"] == "scripted-dictionary-4"
        )
        self.assertEqual(scripted["states"][0]["clip"], {
            "asset": "0235.animation.json",
            "dictionary": 4,
            "slot": 0,
        })

    def test_deterministic_variant_keys_are_unique(self):
        resource = MODULE.build_resource(self.registry)
        keys = [
            state["deterministicVariantKey"]
            for profile in resource["profiles"] for state in profile["states"]
        ]
        self.assertEqual(len(keys), 318)
        self.assertEqual(len(set(keys)), 318)

    def test_rejects_fallback_and_incomplete_coverage(self):
        registry = copy.deepcopy(self.registry)
        binding = next(
            row for row in registry["bindings"]
            if row["actor"] == "obelix" and row["context"] == "gameplay"
        )
        binding["fallback"] = True
        with self.assertRaisesRegex(ValueError, "fallback is forbidden"):
            MODULE.build_resource(registry)

        resource = MODULE.build_resource(self.registry)
        resource["profiles"][0]["states"].pop()
        with self.assertRaisesRegex(ValueError, "unknown state|coverage is incomplete"):
            MODULE.validate_resource(resource)

    def test_source_digest_pins_exact_registry(self):
        resource = MODULE.build_resource(self.registry)
        self.assertEqual(
            resource["source"]["sha256"],
            hashlib.sha256(MODULE.canonical_bytes(self.registry)).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
