#!/usr/bin/env python3
"""Build and strictly validate versioned provenance for all task 91 bindings."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


EXPECTED_MODULE = "GameModule.elb"
EXPECTED_HASH = "35e780a40e4ee625430cb37982deebd085960c37091f3a60465c5aa207ab58a0"
EXPECTED_BINDINGS = 408
RVA = re.compile(r"^0x[0-9a-f]{8}$")
CLIP = re.compile(r"^clip-[0-9]{4}$")


def _runtime_keys(bindings: dict) -> set[str]:
    keys: set[str] = set()
    for profile in bindings.get("runtimeProfiles", []):
        if not profile.get("complete"):
            continue
        for binding in profile.get("states", {}):
            key = f"{profile['id']}:{binding}"
            if key in keys:
                raise ValueError(f"duplicate runtime binding: {key}")
            keys.add(key)
    return keys


def _event_value(container: dict, binding: str, row: dict) -> tuple[str, str | int]:
    if "runtimeState" in row:
        return "runtimeState", row["runtimeState"]
    value = row.get("numericStateOrEvent")
    if not isinstance(value, int):
        raise ValueError(f"{container['profile']}:{binding}: state/event is absent")
    return "numericStateOrEvent", value


def _evidence(module: dict, container: dict, row: dict) -> dict:
    profile = container["profile"]
    binding = row["binding"]
    binding_key = f"{profile}:{binding}"
    state_kind, state_value = _event_value(container, binding, row)
    dictionary = row.get("dictionary")
    slot = row.get("slot")
    clip = row.get("clip")
    field = container.get("dictionaryField")
    if not field:
        raise ValueError(f"{binding_key}: dictionary field is absent")
    identity = "|".join(
        [module["sha256"], profile, binding, str(dictionary), str(slot), str(clip)]
    )
    return {
        "evidenceId": "task91:v1:" + hashlib.sha256(identity.encode()).hexdigest(),
        "bindingKey": binding_key,
        "profile": profile,
        "binding": binding,
        "owner": container["owner"],
        "source": {
            "module": module["name"],
            "sha256": module["sha256"],
            "ownerVtableRva": container["ownerVtableRva"],
            "dispatchRva": container["numericDispatchRva"],
        },
        "stateOrEvent": {"kind": state_kind, "value": state_value},
        "dictionaryAccess": {"field": field, "dictionary": dictionary},
        "slotSelection": {"kind": row.get("slotSelection"), "slot": slot},
        "assetJoin": {"dictionary": dictionary, "slot": slot, "clip": clip},
        "confidence": row.get("confidence"),
        "evidenceKinds": [
            "staticDataFlow",
            "runtimeBinding",
            "authoredAssetJoin",
        ],
    }


def _containers(reports: list[dict]) -> list[dict]:
    asterix, controlled, enemies, world = reports
    result = [
        {
            "owner": asterix["owner"],
            "profile": "asterix-player",
            "ownerVtableRva": asterix["ownerVtableRva"],
            "numericDispatchRva": asterix["numericDispatchRva"],
            "dictionaryField": asterix["dictionaryAccess"]["field"],
            "bindings": asterix["bindings"],
        }
    ]
    for row in controlled["profiles"]:
        result.append(
            {
                **row,
                "dictionaryField": controlled["dictionaryAccess"]["field"],
            }
        )
    result.extend(enemies["enemyProfiles"])
    result.extend(
        {**row, "bindings": [row["binding"]]}
        for row in enemies["scriptedProfiles"]
    )
    result.extend(world["worldProfiles"])
    result.extend(world["cinematicTimelines"])
    return result


def build(reports: list[dict], runtime_bindings: dict) -> dict:
    if len(reports) != 4:
        raise ValueError("exactly four profile reports are required")
    modules = [report.get("module") for report in reports]
    if any(module != modules[0] for module in modules[1:]):
        raise ValueError("cross-version evidence is forbidden")
    module = modules[0]
    if (
        not isinstance(module, dict)
        or module.get("name") != EXPECTED_MODULE
        or module.get("sha256") != EXPECTED_HASH
    ):
        raise ValueError("module identity does not match task 91.1 corpus")
    rows = [
        _evidence(module, container, row)
        for container in _containers(reports)
        for row in container["bindings"]
    ]
    dataset = {
        "schemaVersion": 1,
        "module": module,
        "summary": {
            "runtimeBindingCount": len(_runtime_keys(runtime_bindings)),
            "confirmedBindingCount": len(rows),
            "unresolvedBindingCount": 0,
            "ambiguousBindingCount": 0,
            "visualOnlyBindingCount": 0,
            "membershipOnlyBindingCount": 0,
        },
        "evidence": sorted(rows, key=lambda row: row["bindingKey"]),
    }
    validate(dataset, runtime_bindings)
    return dataset


def validate(dataset: dict, runtime_bindings: dict) -> None:
    if dataset.get("schemaVersion") != 1:
        raise ValueError("unsupported provenance schema version")
    module = dataset.get("module", {})
    if (
        module.get("name") != EXPECTED_MODULE
        or module.get("sha256") != EXPECTED_HASH
        or not RVA.fullmatch(str(module.get("imageBase", "")))
    ):
        raise ValueError("cross-version evidence is forbidden")
    runtime_keys = _runtime_keys(runtime_bindings)
    rows = dataset.get("evidence")
    if not isinstance(rows, list):
        raise ValueError("evidence array is absent")
    if len(runtime_keys) != EXPECTED_BINDINGS or len(rows) != EXPECTED_BINDINGS:
        raise ValueError(
            f"binding total changed: runtime={len(runtime_keys)}, evidence={len(rows)}"
        )
    binding_keys: set[str] = set()
    evidence_ids: set[str] = set()
    source_tuples: set[tuple] = set()
    for row in rows:
        key = row.get("bindingKey")
        if key != f"{row.get('profile')}:{row.get('binding')}":
            raise ValueError(f"{key}: binding identity is inconsistent")
        if key in binding_keys:
            raise ValueError(f"duplicate evidence for runtime binding: {key}")
        binding_keys.add(key)
        evidence_id = row.get("evidenceId")
        if evidence_id in evidence_ids:
            raise ValueError(f"duplicate evidence id: {evidence_id}")
        evidence_ids.add(evidence_id)
        required = ("profile", "binding", "owner", "source", "stateOrEvent",
                    "dictionaryAccess", "slotSelection", "assetJoin")
        if any(name not in row for name in required):
            raise ValueError(f"{key}: incomplete provenance chain")
        source = row["source"]
        if source.get("module") != EXPECTED_MODULE or source.get("sha256") != EXPECTED_HASH:
            raise ValueError(f"{key}: cross-version source")
        if not RVA.fullmatch(str(source.get("ownerVtableRva", ""))) or not RVA.fullmatch(
            str(source.get("dispatchRva", ""))
        ):
            raise ValueError(f"{key}: function identity is incomplete")
        state = row["stateOrEvent"]
        if state.get("kind") not in {"runtimeState", "numericStateOrEvent"}:
            raise ValueError(f"{key}: state/event evidence is incomplete")
        dictionary = row["dictionaryAccess"]
        selector = row["slotSelection"]
        asset = row["assetJoin"]
        if not dictionary.get("field") or not isinstance(dictionary.get("dictionary"), int):
            raise ValueError(f"{key}: dictionary membership-only evidence")
        if selector.get("kind") != "numericRuntimeBinding" or not isinstance(
            selector.get("slot"), int
        ):
            raise ValueError(f"{key}: slot selection is incomplete")
        if (
            asset.get("dictionary") != dictionary["dictionary"]
            or asset.get("slot") != selector["slot"]
            or not CLIP.fullmatch(str(asset.get("clip", "")))
        ):
            raise ValueError(f"{key}: dictionary/slot/clip join is incomplete")
        if row.get("confidence") != "confirmed":
            raise ValueError(f"{key}: visual-only or ambiguous evidence")
        if row.get("evidenceKinds") != [
            "staticDataFlow",
            "runtimeBinding",
            "authoredAssetJoin",
        ]:
            raise ValueError(f"{key}: visual-only or membership-only evidence")
        source_tuple = (
            key,
            source["sha256"],
            source["dispatchRva"],
            state["kind"],
            state.get("value"),
            dictionary["dictionary"],
            selector["slot"],
            asset["clip"],
        )
        if source_tuple in source_tuples:
            raise ValueError(f"{key}: ambiguous duplicate provenance")
        source_tuples.add(source_tuple)
    missing = runtime_keys - binding_keys
    extra = binding_keys - runtime_keys
    if missing or extra:
        raise ValueError(
            f"runtime/evidence bijection failed: missing={len(missing)}, extra={len(extra)}"
        )
    summary = dataset.get("summary", {})
    expected_summary = {
        "runtimeBindingCount": EXPECTED_BINDINGS,
        "confirmedBindingCount": EXPECTED_BINDINGS,
        "unresolvedBindingCount": 0,
        "ambiguousBindingCount": 0,
        "visualOnlyBindingCount": 0,
        "membershipOnlyBindingCount": 0,
    }
    if summary != expected_summary:
        raise ValueError("provenance summary is not strict")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("asterix", type=Path)
    parser.add_argument("controlled_heroes", type=Path)
    parser.add_argument("enemies_scripted", type=Path)
    parser.add_argument("world_cinematics", type=Path)
    parser.add_argument("runtime_bindings", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    reports = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in (
            args.asterix,
            args.controlled_heroes,
            args.enemies_scripted,
            args.world_cinematics,
        )
    ]
    runtime_bindings = json.loads(args.runtime_bindings.read_text(encoding="utf-8"))
    result = build(reports, runtime_bindings)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
