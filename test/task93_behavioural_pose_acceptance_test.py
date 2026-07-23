import copy
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location(
    "task93_behavioural_pose_acceptance",
    ROOT / "scripts/task93_behavioural_pose_acceptance.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

KINDS = [
    "jump.stationary", "jump.moving", "jump.hold", "jump.double",
    "jump.apex-landing", "jump.interrupt-damage", "jump.interrupt-pause",
]
LANDMARKS = ["head", "leftHand", "rightHand", "leftFoot", "rightFoot"]


def trace(scenario="jump-stationary", source="original"):
    samples = []
    for index, marker in enumerate(("takeoff", "apex", "landing")):
        samples.append({
            "marker": marker,
            "timeSeconds": index * 0.25,
            "binding": {
                "dictionary": 0, "slot": 13, "asset": "clip-0031"
            },
            "phase": index * 0.4,
            "transition": "select:jump",
            "pose": {
                "space": "normalizedScreen",
                "landmarks": {
                    landmark: [0.2 + point * 0.1, 0.3 + index * 0.1]
                    for point, landmark in enumerate(LANDMARKS)
                },
            },
        })
    return {
        "schemaVersion": 1,
        "traceType": "asterix.behavioural-pose",
        "scenario": scenario,
        "source": source,
        "capture": {"artifactSha256": "a" * 64, "sampleRateHz": 60.0},
        "samples": samples,
    }


def manifest(reference):
    digest = MODULE.sha256_bytes(MODULE.canonical_bytes(reference))
    scenarios = []
    for index, kind in enumerate(KINDS):
        scenarios.append({
            "id": "jump-stationary" if index == 0 else f"scenario-{index}",
            "kind": kind,
            "referenceTraceSha256": digest if index == 0 else f"{index:064x}",
            "sourceCaptureSha256": "a" * 64,
            "requiredMarkers": ["takeoff", "apex", "landing"],
        })
    return {
        "schemaVersion": 1,
        "acceptanceType": "asterix.behavioural-pose",
        "profile": "actor:CKHkAsterix",
        "requiredLandmarks": LANDMARKS,
        "tolerances": {
            "markerTimeSeconds": 0.04,
            "phase": 0.08,
            "poseNormalizedDistance": 0.035,
        },
        "scenarios": scenarios,
    }


class Task93BehaviouralPoseAcceptanceTest(unittest.TestCase):
    def test_accepts_binding_phase_transition_and_visual_pose(self):
        reference = trace()
        candidate = trace(source="runtime")
        candidate["samples"][1]["timeSeconds"] += 0.02
        candidate["samples"][1]["phase"] += 0.03
        candidate["samples"][1]["pose"]["landmarks"]["head"][0] += 0.02
        result = MODULE.compare(
            manifest(reference), manifest(reference)["scenarios"][0],
            reference, candidate,
        )
        self.assertTrue(result["passed"])
        self.assertEqual(result["sampleCount"], 3)

    def test_rejects_correct_clip_with_wrong_pose(self):
        reference = trace()
        candidate = trace(source="runtime")
        candidate["samples"][1]["pose"]["landmarks"]["head"][0] += 0.1
        result = MODULE.compare(
            manifest(reference), manifest(reference)["scenarios"][0],
            reference, candidate,
        )
        self.assertFalse(result["passed"])
        self.assertIn("apex/head: pose distance", result["failures"][0])

    def test_rejects_binding_transition_phase_and_timing_regressions(self):
        reference = trace()
        candidate = trace(source="runtime")
        candidate["samples"][0]["binding"]["slot"] = 35
        candidate["samples"][1]["transition"] = "select:fall"
        candidate["samples"][1]["phase"] += 0.2
        candidate["samples"][2]["timeSeconds"] += 0.1
        result = MODULE.compare(
            manifest(reference), manifest(reference)["scenarios"][0],
            reference, candidate,
        )
        self.assertFalse(result["passed"])
        self.assertGreaterEqual(len(result["failures"]), 4)

    def test_rejects_modified_or_wrong_capture_reference(self):
        reference = trace()
        accepted = manifest(reference)
        modified = copy.deepcopy(reference)
        modified["samples"][0]["phase"] = 0.1
        with self.assertRaisesRegex(ValueError, "digest"):
            MODULE.compare(
                accepted, accepted["scenarios"][0], modified,
                trace(source="runtime"),
            )
        with self.assertRaisesRegex(ValueError, "source capture"):
            modified["capture"]["artifactSha256"] = "b" * 64
            accepted["scenarios"][0]["referenceTraceSha256"] = (
                MODULE.sha256_bytes(MODULE.canonical_bytes(modified))
            )
            MODULE.compare(
                accepted, accepted["scenarios"][0], modified,
                trace(source="runtime"),
            )

    def test_manifest_requires_complete_jump_scenario_matrix(self):
        reference = trace()
        accepted = manifest(reference)
        accepted["scenarios"].pop()
        with self.assertRaisesRegex(ValueError, "coverage"):
            MODULE.validate_manifest(accepted)

    def test_checked_in_manifest_is_canonical_and_complete(self):
        path = ROOT / "tools/task93/behavioural_pose_acceptance.v1.json"
        payload = path.read_bytes()
        accepted = json.loads(payload)
        MODULE.validate_manifest(accepted)
        self.assertEqual(payload, MODULE.canonical_bytes(accepted))
        self.assertEqual(len(accepted["scenarios"]), 7)

    def test_directory_gate_writes_metadata_only_report(self):
        reference = trace()
        accepted = manifest(reference)
        accepted["scenarios"] = [accepted["scenarios"][0]]
        # The directory runner is orthogonal to matrix validation; exercise
        # its report path with a temporarily narrowed validated manifest.
        original_validate = MODULE.validate_manifest
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            references = root / "references"
            candidates = root / "candidates"
            references.mkdir()
            candidates.mkdir()
            (references / "jump-stationary.json").write_bytes(
                MODULE.canonical_bytes(reference)
            )
            (candidates / "jump-stationary.json").write_bytes(
                MODULE.canonical_bytes(trace(source="runtime"))
            )
            manifest_path = root / "manifest.json"
            manifest_path.write_bytes(MODULE.canonical_bytes(accepted))
            output = root / "report.json"
            MODULE.validate_manifest = lambda _: None
            try:
                report = MODULE.run(
                    manifest_path, references, candidates, output
                )
            finally:
                MODULE.validate_manifest = original_validate
            self.assertTrue(report["passed"])
            self.assertEqual(json.loads(output.read_text())["scenarioCount"], 1)


if __name__ == "__main__":
    unittest.main()
