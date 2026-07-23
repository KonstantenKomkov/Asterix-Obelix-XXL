#!/usr/bin/env python3
"""Compile accepted Asterix provenance into a canonical runtime graph."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from task93_asterix_behaviour import validate as validate_provenance


SCHEMA_VERSION = 1
RESOURCE_TYPE = "asterix.authored-animation-graph"
STATE_FIELDS = {
    "id", "profile", "binding", "runtimeState", "clip", "playback",
    "phaseEvents", "rootMotion", "provenanceEvidenceId",
}
TRANSITION_FIELDS = {
    "id", "profile", "fromState", "toState", "trigger", "guard",
    "completion", "interrupt", "blend", "operation", "provenanceEvidenceId",
}


def canonical_bytes(value: dict) -> bytes:
    return (json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ) + "\n").encode("utf-8")


def _require_keys(value: dict, expected: set[str], context: str) -> None:
    if set(value) != expected:
        missing = sorted(expected - set(value))
        extra = sorted(set(value) - expected)
        raise ValueError(f"{context}: invalid fields; missing={missing}, extra={extra}")


def validate_graph(graph: dict) -> None:
    _require_keys(
        graph,
        {
            "schemaVersion", "resourceType", "profile", "entryState",
            "states", "transitions", "source",
        },
        "graph",
    )
    if graph["schemaVersion"] != SCHEMA_VERSION:
        raise ValueError("unsupported authored animation graph schema")
    if graph["resourceType"] != RESOURCE_TYPE:
        raise ValueError("unexpected authored animation resource type")

    profile = graph["profile"]
    _require_keys(profile, {"id", "owner", "module", "moduleSha256"}, "profile")
    if not all(isinstance(profile[key], str) and profile[key] for key in profile):
        raise ValueError("graph profile is incomplete")

    source = graph["source"]
    _require_keys(source, {"schemaVersion", "sha256"}, "source")
    if source["schemaVersion"] != 1 or not isinstance(source["sha256"], str):
        raise ValueError("graph provenance source is incompatible")

    states = graph["states"]
    transitions = graph["transitions"]
    if not isinstance(states, list) or not states:
        raise ValueError("authored animation graph has no states")
    if not isinstance(transitions, list) or not transitions:
        raise ValueError("authored animation graph has no transitions")

    state_ids: set[str] = set()
    evidence_ids: set[str] = set()
    bindings: set[str] = set()
    for index, state in enumerate(states):
        _require_keys(state, STATE_FIELDS, f"state[{index}]")
        if state["profile"] != profile["id"]:
            raise ValueError(f"{state['id']}: cross-profile state")
        if state["id"] in state_ids or state["binding"] in bindings:
            raise ValueError(f"{state['id']}: duplicate state or binding")
        if state["provenanceEvidenceId"] in evidence_ids:
            raise ValueError(f"{state['id']}: duplicate provenance evidence")
        clip = state["clip"]
        _require_keys(clip, {"dictionary", "slot", "asset"}, f"{state['id']}.clip")
        if clip["dictionary"] < 0 or clip["slot"] < 0 or not clip["asset"]:
            raise ValueError(f"{state['id']}: incomplete clip reference")
        playback = state["playback"]
        _require_keys(playback, {"rate"}, f"{state['id']}.playback")
        if playback["rate"] <= 0:
            raise ValueError(f"{state['id']}: invalid playback")
        phase_events = state["phaseEvents"]
        _require_keys(
            phase_events, {"initialPhase", "events"}, f"{state['id']}.phaseEvents"
        )
        if (
            not 0 <= phase_events["initialPhase"] <= 1
            or not isinstance(phase_events["events"], list)
            or any(not isinstance(event, str) or not event for event in phase_events["events"])
        ):
            raise ValueError(f"{state['id']}: incomplete phase events")
        root_motion = state["rootMotion"]
        _require_keys(root_motion, {"policy"}, f"{state['id']}.rootMotion")
        if root_motion["policy"] not in {"inPlace", "physicsDriven", "authored"}:
            raise ValueError(f"{state['id']}: invalid root-motion policy")
        state_ids.add(state["id"])
        bindings.add(state["binding"])
        evidence_ids.add(state["provenanceEvidenceId"])

    if graph["entryState"] not in state_ids:
        raise ValueError("entry state does not exist")

    incoming = {state_id: 0 for state_id in state_ids}
    state_by_id = {state["id"]: state for state in states}
    dispatch_keys: set[tuple[str, str, str]] = set()
    transition_ids: set[str] = set()
    for index, transition in enumerate(transitions):
        _require_keys(transition, TRANSITION_FIELDS, f"transition[{index}]")
        if transition["profile"] != profile["id"]:
            raise ValueError(f"{transition['id']}: cross-profile transition")
        if transition["id"] in transition_ids:
            raise ValueError(f"{transition['id']}: duplicate transition")
        if transition["fromState"] != "*" and transition["fromState"] not in state_ids:
            raise ValueError(f"{transition['id']}: unknown source state")
        if transition["toState"] not in state_ids:
            raise ValueError(f"{transition['id']}: unknown target state")
        trigger = transition["trigger"]
        _require_keys(trigger, {"fact", "evidenceRva"}, f"{transition['id']}.trigger")
        guard = transition["guard"]
        _require_keys(
            guard, {"fact", "binding", "evidenceRva"}, f"{transition['id']}.guard"
        )
        if not trigger["fact"] or not guard["fact"] or guard["binding"] not in bindings:
            raise ValueError(f"{transition['id']}: incomplete trigger/guard")
        target = state_by_id[transition["toState"]]
        if target["binding"] != guard["binding"]:
            raise ValueError(f"{transition['id']}: guard selects another binding")
        if target["provenanceEvidenceId"] != transition["provenanceEvidenceId"]:
            raise ValueError(f"{transition['id']}: provenance evidence mismatch")
        key = (transition["fromState"], trigger["fact"], guard["binding"])
        if key in dispatch_keys:
            raise ValueError(f"{transition['id']}: ambiguous transition")
        dispatch_keys.add(key)
        if transition["completion"]["kind"] not in {
            "loop", "authoredClipEnd", "landing", "terminal"
        }:
            raise ValueError(f"{transition['id']}: incomplete completion")
        if not transition["interrupt"]["policy"]:
            raise ValueError(f"{transition['id']}: incomplete interrupt")
        if transition["blend"]["seconds"] < 0:
            raise ValueError(f"{transition['id']}: invalid blend")
        if transition["operation"] not in {"start", "change"}:
            raise ValueError(f"{transition['id']}: invalid operation")
        incoming[transition["toState"]] += 1
        transition_ids.add(transition["id"])

    unreachable = sorted(state_id for state_id, count in incoming.items() if count == 0)
    if unreachable:
        raise ValueError(f"unreachable authored states: {unreachable}")
    if len(states) != len(transitions):
        raise ValueError("each authored state must have exactly one selector transition")


def build_graph(provenance: dict) -> dict:
    validate_provenance(provenance)
    owner = provenance["owner"]
    profile_id = f"actor:{owner}"
    rows = sorted(
        provenance["transitions"],
        key=lambda row: (row["dictionaryAccess"]["slot"], row["binding"]),
    )
    states = []
    transitions = []
    for row in rows:
        state_id = f"binding:{row['binding']}"
        states.append({
            "id": state_id,
            "profile": profile_id,
            "binding": row["binding"],
            "runtimeState": row["runtimeState"],
            "clip": {
                "dictionary": row["dictionaryAccess"]["dictionary"],
                "slot": row["dictionaryAccess"]["slot"],
                "asset": row["dictionaryAccess"]["clip"],
            },
            "playback": {
                "rate": row["playback"]["rate"],
            },
            "phaseEvents": {
                "initialPhase": row["phaseEvents"]["initialPhase"],
                "events": row["phaseEvents"]["events"],
            },
            "rootMotion": {"policy": row["rootMotion"]["policy"]},
            "provenanceEvidenceId": row["evidenceId"],
        })
        transitions.append({
            "id": f"select:{row['binding']}",
            "profile": profile_id,
            "fromState": "*",
            "toState": state_id,
            "trigger": row["trigger"],
            "guard": {
                "fact": row["guard"]["fact"],
                "binding": row["binding"],
                "evidenceRva": row["guard"]["evidenceRva"],
            },
            "completion": row["completion"],
            "interrupt": row["interrupt"],
            "blend": row["blend"],
            "operation": row["operation"],
            "provenanceEvidenceId": row["evidenceId"],
        })
    result = {
        "schemaVersion": SCHEMA_VERSION,
        "resourceType": RESOURCE_TYPE,
        "profile": {
            "id": profile_id,
            "owner": owner,
            "module": provenance["module"]["name"],
            "moduleSha256": provenance["module"]["sha256"],
        },
        "entryState": states[0]["id"],
        "states": states,
        "transitions": transitions,
        "source": {
            "schemaVersion": provenance["schemaVersion"],
            "sha256": hashlib.sha256(canonical_bytes(provenance)).hexdigest(),
        },
    }
    validate_graph(result)
    return result


def export(provenance_path: Path, output_path: Path, cache_dir: Path | None) -> bytes:
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    result = build_graph(provenance)
    payload = canonical_bytes(result)
    if cache_dir is not None:
        cache_dir.mkdir(parents=True, exist_ok=True)
        key = hashlib.sha256(payload).hexdigest()
        cached = cache_dir / f"authored-animation-graph-v{SCHEMA_VERSION}-{key}.json"
        if cached.exists():
            cached_payload = cached.read_bytes()
            validate_graph(json.loads(cached_payload))
            if cached_payload != payload:
                raise ValueError("cached authored animation graph is not canonical")
            payload = cached_payload
        else:
            cached.write_bytes(payload)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(payload)
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("provenance", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cache-dir", type=Path)
    args = parser.parse_args()
    export(args.provenance, args.output, args.cache_dir)


if __name__ == "__main__":
    main()
