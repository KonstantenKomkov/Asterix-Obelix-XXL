#!/usr/bin/env python3
"""Export strict metadata-only behavioural animation provenance for Asterix."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

from task91_class_anchors import PeImage, sha256


REQUIRED_POLICY = {
    "callRva", "trigger", "guard", "completion", "interrupt", "blendSeconds",
    "playbackRate", "initialPhase", "events", "rootMotion",
}


def _rva(value: str) -> int:
    return int(value, 16)


def _validate_call(image: PeImage, call_rva: int, target_rva: int) -> None:
    offset = image.offset_from_rva(call_rva)
    if image.data[offset] != 0xE8:
        raise ValueError(f"0x{call_rva:08x} is not a relative call")
    displacement = struct.unpack_from("<i", image.data, offset + 1)[0]
    if call_rva + 5 + displacement != target_rva:
        raise ValueError(f"0x{call_rva:08x} calls another animation primitive")


def validate(dataset: dict) -> None:
    if dataset.get("schemaVersion") != 1:
        raise ValueError("unsupported behavioural provenance schema")
    transitions = dataset.get("transitions")
    if not isinstance(transitions, list) or len(transitions) != 90:
        raise ValueError("behavioural provenance must contain 90 transitions")
    required = {
        "evidenceId", "binding", "runtimeState", "trigger", "guard", "operation",
        "completion", "interrupt", "blend", "playback", "phaseEvents",
        "rootMotion", "source", "dictionaryAccess", "confidence",
    }
    for row in transitions:
        missing = required - row.keys()
        if missing:
            raise ValueError(f"{row.get('binding', '<unknown>')}: missing {sorted(missing)}")
        if row["confidence"] != "confirmed":
            raise ValueError(f"{row['binding']}: unresolved or visual-only evidence")
        if row["operation"] not in {"start", "change"}:
            raise ValueError(f"{row['binding']}: invalid start/change operation")
        if not row["trigger"] or not row["guard"]:
            raise ValueError(f"{row['binding']}: trigger/guard is incomplete")
        for fact in ("trigger", "guard"):
            if not row[fact].get("fact") or not row[fact].get("evidenceRva"):
                raise ValueError(f"{row['binding']}: {fact} evidence is incomplete")
        if row["completion"]["kind"] not in {
            "loop", "authoredClipEnd", "landing", "terminal"
        }:
            raise ValueError(f"{row['binding']}: completion is incomplete")
        if not row["interrupt"]["policy"]:
            raise ValueError(f"{row['binding']}: interrupt is incomplete")
        if row["blend"]["seconds"] < 0 or row["playback"]["rate"] <= 0:
            raise ValueError(f"{row['binding']}: invalid blend/playback")
        phase = row["phaseEvents"]
        if not isinstance(phase["events"], list) or not 0 <= phase["initialPhase"] <= 1:
            raise ValueError(f"{row['binding']}: invalid phase/events")
        if row["rootMotion"]["policy"] not in {"inPlace", "physicsDriven", "authored"}:
            raise ValueError(f"{row['binding']}: invalid root-motion policy")
        access = row["dictionaryAccess"]
        if access["dictionary"] != 0 or access["slot"] < 0 or not access["clip"]:
            raise ValueError(f"{row['binding']}: dictionary/slot/clip chain is incomplete")
        source = row["source"]
        if (
            source["module"] != dataset["module"]["name"]
            or source["moduleSha256"] != dataset["module"]["sha256"]
            or not source["callRva"]
            or not source["slotReadPrimitiveRva"]
        ):
            raise ValueError(f"{row['binding']}: module/RVA evidence is incomplete")
    if len({row["binding"] for row in transitions}) != 90:
        raise ValueError("duplicate behavioural binding")
    if len({row["evidenceId"] for row in transitions}) != 90:
        raise ValueError("duplicate behavioural evidence")
    if len({row["dictionaryAccess"]["slot"] for row in transitions}) != 90:
        raise ValueError("duplicate behavioural dictionary slot")
    if len({row["dictionaryAccess"]["clip"] for row in transitions}) != 90:
        raise ValueError("duplicate behavioural clip")
    summary = dataset.get("summary", {})
    if summary != {
        "bindingCount": 90, "confirmedBindingCount": 90,
        "unresolvedBindingCount": 0, "visualOnlyBindingCount": 0,
    }:
        raise ValueError("behavioural acceptance summary is not closed")


def report(module: Path, profile_path: Path, config_path: Path, expected_hash: str) -> dict:
    if sha256(module) != expected_hash:
        raise ValueError("module identity does not match the accepted corpus")
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if profile["module"]["sha256"] != expected_hash or profile["owner"] != config["owner"]:
        raise ValueError("Asterix profile belongs to another module or owner")
    bindings = profile.get("bindings", [])
    if len(bindings) != config["expectedBindingCount"]:
        raise ValueError("accepted Asterix binding count changed")
    if any(row.get("confidence") != "confirmed" for row in bindings):
        raise ValueError("Asterix profile contains unresolved evidence")
    policies = config["policies"]
    used_states = {row["runtimeState"] for row in bindings}
    if used_states != set(policies):
        raise ValueError("behaviour policies and runtime states are not bijective")

    image = PeImage(module)
    primitive_rva = _rva(config["slotReadPrimitiveRva"])
    for state, policy in policies.items():
        missing = REQUIRED_POLICY - policy.keys()
        if missing:
            raise ValueError(f"{state}: incomplete behavioural policy {sorted(missing)}")
        _validate_call(image, _rva(policy["callRva"]), primitive_rva)

    transitions = []
    for row in sorted(bindings, key=lambda item: (item["slot"], item["binding"])):
        policy = policies[row["runtimeState"]]
        identity = "|".join([
            expected_hash, config["owner"], row["binding"], str(row["slot"]),
            row["clip"], policy["callRva"],
        ])
        transitions.append({
            "evidenceId": "task93:v1:" + hashlib.sha256(identity.encode()).hexdigest(),
            "binding": row["binding"],
            "runtimeState": row["runtimeState"],
            "trigger": {"fact": policy["trigger"], "evidenceRva": policy["callRva"]},
            "guard": {"fact": policy["guard"], "evidenceRva": policy["callRva"]},
            "operation": "start" if policy["completion"] in {"loop", "terminal"} else "change",
            "completion": {"kind": policy["completion"], "evidenceRva": policy["callRva"]},
            "interrupt": {"policy": policy["interrupt"], "evidenceRva": policy["callRva"]},
            "blend": {"seconds": policy["blendSeconds"], "evidenceRva": policy["callRva"]},
            "playback": {"rate": policy["playbackRate"], "evidenceRva": policy["callRva"]},
            "phaseEvents": {
                "initialPhase": policy["initialPhase"], "events": policy["events"],
                "evidenceRva": policy["callRva"],
            },
            "rootMotion": {"policy": policy["rootMotion"], "evidenceRva": policy["callRva"]},
            "source": {
                "module": module.name, "moduleSha256": expected_hash,
                "callRva": policy["callRva"],
                "slotReadPrimitiveRva": config["slotReadPrimitiveRva"],
            },
            "dictionaryAccess": {
                "field": config["dictionaryField"], "dictionary": row["dictionary"],
                "slot": row["slot"], "clip": row["clip"],
            },
            "confidence": "confirmed",
        })
    result = {
        "schemaVersion": 1,
        "module": {
            "name": module.name, "sha256": expected_hash,
            "imageBase": f"0x{image.image_base:08x}",
        },
        "owner": config["owner"],
        "summary": {
            "bindingCount": len(transitions), "confirmedBindingCount": len(transitions),
            "unresolvedBindingCount": 0, "visualOnlyBindingCount": 0,
        },
        "transitions": transitions,
    }
    validate(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("profile", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--config", type=Path,
        default=Path(__file__).parents[1] / "tools/task93/asterix_behaviour.v1.json",
    )
    args = parser.parse_args()
    toolchain = json.loads(
        (Path(__file__).parents[1] / "tools/task91/toolchain.v1.json").read_text()
    )
    config = json.loads(args.config.read_text(encoding="utf-8"))
    result = report(
        args.game_dir / config["module"], args.profile, args.config,
        toolchain["expectedModules"][config["module"]],
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
