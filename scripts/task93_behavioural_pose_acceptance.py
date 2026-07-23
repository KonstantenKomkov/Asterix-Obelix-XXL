#!/usr/bin/env python3
"""Compare local original-game behavioural/pose traces with runtime traces."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


TRACE_KEYS = {
    "schemaVersion", "traceType", "scenario", "source", "capture", "samples"
}
SAMPLE_KEYS = {
    "marker", "timeSeconds", "binding", "phase", "transition", "pose"
}
BINDING_KEYS = {"dictionary", "slot", "asset"}
POSE_KEYS = {"space", "landmarks"}
SOURCES = {"original", "runtime"}
HEX64 = set("0123456789abcdef")


def canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode()


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or set(value) - HEX64:
        raise ValueError(f"{label} must be a lowercase SHA-256")
    return value


def _finite(value: Any, label: str, minimum: float = 0.0) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be numeric")
    value = float(value)
    if not math.isfinite(value) or value < minimum:
        raise ValueError(f"{label} is outside the accepted range")
    return value


def validate_trace(trace: dict[str, Any], expected_source: str | None = None) -> None:
    if not isinstance(trace, dict) or set(trace) != TRACE_KEYS:
        raise ValueError("trace has invalid fields")
    if trace["schemaVersion"] != 1 or trace["traceType"] != "asterix.behavioural-pose":
        raise ValueError("unsupported trace schema")
    if trace["source"] not in SOURCES:
        raise ValueError("trace source is invalid")
    if expected_source is not None and trace["source"] != expected_source:
        raise ValueError(f"expected {expected_source} trace")
    if not isinstance(trace["scenario"], str) or not trace["scenario"]:
        raise ValueError("trace scenario is missing")
    capture = trace["capture"]
    if not isinstance(capture, dict) or set(capture) != {
        "artifactSha256", "sampleRateHz"
    }:
        raise ValueError("trace capture metadata is invalid")
    _digest(capture["artifactSha256"], "capture artifactSha256")
    _finite(capture["sampleRateHz"], "capture sampleRateHz", 0.001)
    samples = trace["samples"]
    if not isinstance(samples, list) or len(samples) < 2:
        raise ValueError("trace must contain at least two samples")
    seen: set[str] = set()
    previous_time = -1.0
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict) or set(sample) != SAMPLE_KEYS:
            raise ValueError(f"sample {index} has invalid fields")
        marker = sample["marker"]
        if not isinstance(marker, str) or not marker or marker in seen:
            raise ValueError("trace markers must be unique non-empty strings")
        seen.add(marker)
        time = _finite(sample["timeSeconds"], f"{marker} timeSeconds")
        if time <= previous_time:
            raise ValueError("trace sample times must be strictly increasing")
        previous_time = time
        binding = sample["binding"]
        if not isinstance(binding, dict) or set(binding) != BINDING_KEYS:
            raise ValueError(f"{marker} binding is invalid")
        if (
            not isinstance(binding["dictionary"], int)
            or isinstance(binding["dictionary"], bool)
            or binding["dictionary"] < 0
            or not isinstance(binding["slot"], int)
            or isinstance(binding["slot"], bool)
            or binding["slot"] < 0
            or not isinstance(binding["asset"], str)
            or not binding["asset"]
        ):
            raise ValueError(f"{marker} binding is invalid")
        phase = _finite(sample["phase"], f"{marker} phase")
        if phase > 1:
            raise ValueError(f"{marker} phase is outside [0, 1]")
        if not isinstance(sample["transition"], str) or not sample["transition"]:
            raise ValueError(f"{marker} transition is invalid")
        pose = sample["pose"]
        if not isinstance(pose, dict) or set(pose) != POSE_KEYS:
            raise ValueError(f"{marker} pose is invalid")
        if pose["space"] != "normalizedScreen":
            raise ValueError(f"{marker} pose space is unsupported")
        landmarks = pose["landmarks"]
        if not isinstance(landmarks, dict) or not landmarks:
            raise ValueError(f"{marker} pose landmarks are missing")
        for name, point in landmarks.items():
            if not isinstance(name, str) or not name:
                raise ValueError(f"{marker} pose landmark name is invalid")
            if not isinstance(point, list) or len(point) != 2:
                raise ValueError(f"{marker}/{name} landmark must be [x, y]")
            for axis in point:
                value = _finite(axis, f"{marker}/{name} coordinate")
                if value > 1:
                    raise ValueError(f"{marker}/{name} coordinate is outside [0, 1]")


def validate_manifest(manifest: dict[str, Any]) -> None:
    if not isinstance(manifest, dict) or set(manifest) != {
        "schemaVersion", "acceptanceType", "profile", "requiredLandmarks",
        "tolerances", "scenarios",
    }:
        raise ValueError("acceptance manifest has invalid fields")
    if (
        manifest["schemaVersion"] != 1
        or manifest["acceptanceType"] != "asterix.behavioural-pose"
        or manifest["profile"] != "actor:CKHkAsterix"
    ):
        raise ValueError("unsupported acceptance manifest")
    landmarks = manifest["requiredLandmarks"]
    if (
        not isinstance(landmarks, list)
        or len(landmarks) < 3
        or len(set(landmarks)) != len(landmarks)
        or any(not isinstance(item, str) or not item for item in landmarks)
    ):
        raise ValueError("required landmarks are invalid")
    tolerances = manifest["tolerances"]
    if not isinstance(tolerances, dict) or set(tolerances) != {
        "markerTimeSeconds", "phase", "poseNormalizedDistance"
    }:
        raise ValueError("acceptance tolerances are invalid")
    for key, value in tolerances.items():
        _finite(value, f"tolerance {key}")
    scenarios = manifest["scenarios"]
    if not isinstance(scenarios, list) or not scenarios:
        raise ValueError("acceptance scenarios are missing")
    required_kinds = {
        "jump.stationary", "jump.moving", "jump.hold", "jump.double",
        "jump.apex-landing", "jump.interrupt-damage", "jump.interrupt-pause",
    }
    ids: set[str] = set()
    kinds: set[str] = set()
    for scenario in scenarios:
        if not isinstance(scenario, dict) or set(scenario) != {
            "id", "kind", "referenceTraceSha256", "sourceCaptureSha256",
            "requiredMarkers",
        }:
            raise ValueError("acceptance scenario has invalid fields")
        scenario_id = scenario["id"]
        if not isinstance(scenario_id, str) or not scenario_id or scenario_id in ids:
            raise ValueError("acceptance scenario IDs must be unique")
        ids.add(scenario_id)
        kind = scenario["kind"]
        if not isinstance(kind, str) or not kind:
            raise ValueError(f"{scenario_id} kind is invalid")
        kinds.add(kind)
        _digest(scenario["referenceTraceSha256"], "referenceTraceSha256")
        _digest(scenario["sourceCaptureSha256"], "sourceCaptureSha256")
        markers = scenario["requiredMarkers"]
        if (
            not isinstance(markers, list)
            or len(markers) < 2
            or len(set(markers)) != len(markers)
            or any(not isinstance(item, str) or not item for item in markers)
        ):
            raise ValueError(f"{scenario_id} requiredMarkers are invalid")
    if kinds != required_kinds:
        raise ValueError("acceptance scenario coverage is incomplete")


def _by_marker(trace: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {sample["marker"]: sample for sample in trace["samples"]}


def compare(
    manifest: dict[str, Any],
    scenario: dict[str, Any],
    reference: dict[str, Any],
    candidate: dict[str, Any],
) -> dict[str, Any]:
    validate_manifest(manifest)
    validate_trace(reference, "original")
    validate_trace(candidate, "runtime")
    if reference["scenario"] != scenario["id"] or candidate["scenario"] != scenario["id"]:
        raise ValueError("trace scenario does not match acceptance scenario")
    reference_digest = sha256_bytes(canonical_bytes(reference))
    if reference_digest != scenario["referenceTraceSha256"]:
        raise ValueError("local reference trace digest does not match manifest")
    if reference["capture"]["artifactSha256"] != scenario["sourceCaptureSha256"]:
        raise ValueError("reference trace is linked to the wrong source capture")

    expected = _by_marker(reference)
    actual = _by_marker(candidate)
    required = scenario["requiredMarkers"]
    if set(actual) != set(required) or set(expected) != set(required):
        raise ValueError("trace markers differ from required scenario markers")
    tolerances = manifest["tolerances"]
    landmarks = manifest["requiredLandmarks"]
    failures: list[str] = []
    maxima = {"timeSeconds": 0.0, "phase": 0.0, "poseDistance": 0.0}
    for marker in required:
        left, right = expected[marker], actual[marker]
        if left["binding"] != right["binding"]:
            failures.append(f"{marker}: binding differs")
        if left["transition"] != right["transition"]:
            failures.append(f"{marker}: transition differs")
        time_delta = abs(left["timeSeconds"] - right["timeSeconds"])
        phase_delta = abs(left["phase"] - right["phase"])
        maxima["timeSeconds"] = max(maxima["timeSeconds"], time_delta)
        maxima["phase"] = max(maxima["phase"], phase_delta)
        if time_delta > tolerances["markerTimeSeconds"]:
            failures.append(f"{marker}: marker time delta {time_delta:.6f}")
        if phase_delta > tolerances["phase"]:
            failures.append(f"{marker}: phase delta {phase_delta:.6f}")
        left_pose = left["pose"]["landmarks"]
        right_pose = right["pose"]["landmarks"]
        if set(left_pose) != set(landmarks) or set(right_pose) != set(landmarks):
            failures.append(f"{marker}: pose landmark set differs")
            continue
        for landmark in landmarks:
            distance = math.dist(left_pose[landmark], right_pose[landmark])
            maxima["poseDistance"] = max(maxima["poseDistance"], distance)
            if distance > tolerances["poseNormalizedDistance"]:
                failures.append(
                    f"{marker}/{landmark}: pose distance {distance:.6f}"
                )
    return {
        "schemaVersion": 1,
        "scenario": scenario["id"],
        "passed": not failures,
        "sampleCount": len(required),
        "maxima": maxima,
        "failures": failures,
        "referenceTraceSha256": reference_digest,
        "candidateTraceSha256": sha256_bytes(canonical_bytes(candidate)),
    }


def run(manifest_path: Path, reference_dir: Path, candidate_dir: Path,
        output_path: Path) -> dict[str, Any]:
    manifest = json.loads(manifest_path.read_text())
    validate_manifest(manifest)
    results = []
    for scenario in manifest["scenarios"]:
        name = scenario["id"] + ".json"
        reference = json.loads((reference_dir / name).read_text())
        candidate = json.loads((candidate_dir / name).read_text())
        results.append(compare(manifest, scenario, reference, candidate))
    report = {
        "schemaVersion": 1,
        "acceptanceType": manifest["acceptanceType"],
        "profile": manifest["profile"],
        "passed": all(item["passed"] for item in results),
        "scenarioCount": len(results),
        "scenarios": results,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(canonical_bytes(report))
    if not report["passed"]:
        failed = [item["scenario"] for item in results if not item["passed"]]
        raise ValueError("behavioural/pose acceptance failed: " + ", ".join(failed))
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("reference_dir", type=Path)
    parser.add_argument("candidate_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = run(
            args.manifest, args.reference_dir, args.candidate_dir, args.output
        )
    except (OSError, json.JSONDecodeError, ValueError) as error:
        parser.error(str(error))
    print(
        f"Accepted {report['scenarioCount']} behavioural/pose scenarios "
        f"for {report['profile']}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
