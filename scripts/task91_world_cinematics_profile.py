#!/usr/bin/env python3
"""Export metadata-only authored profiles for world/UI/FX and cinematics."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from task91_class_anchors import PeImage, parse_registration, sha256


def _dictionary_slot(binding: str) -> int:
    prefix = "dictionary_slot_"
    if not binding.startswith(prefix) or not binding.removeprefix(prefix).isdigit():
        raise ValueError(f"invalid numeric dictionary binding: {binding}")
    return int(binding.removeprefix(prefix))


def _selector(variant: str) -> tuple[int, int]:
    parts = variant.split("-")
    if (
        len(parts) != 4
        or parts[0] != "dictionary"
        or not parts[1].isdigit()
        or parts[2] != "slot"
        or not parts[3].isdigit()
    ):
        raise ValueError(f"invalid dictionary selector: {variant}")
    return int(parts[1]), int(parts[3])


def _clip_id(binding: dict) -> str:
    stem = binding.get("clip", "").removesuffix(".animation.json")
    if len(stem) != 4 or not stem.isdigit():
        raise ValueError(f"invalid authored clip: {binding.get('clip', '')}")
    return f"clip-{stem}"


def _anchor(anchors: dict, owner: str, field: str) -> dict:
    row = next((item for item in anchors["anchors"] if item["class"] == owner), None)
    if row is None or not any(item["name"] == field for item in row["fields"]):
        raise ValueError(f"{owner}.{field} anchor is absent")
    return row


def _dispatch(dispatch: dict, owner: str) -> dict:
    row = next((item for item in dispatch["owners"] if item["owner"] == owner), None)
    if row is None or row["inputKind"] != "numericStateOrEvent":
        raise ValueError(f"{owner} numeric dispatch is absent")
    return row


def _direct_owner(image: PeImage, owner: str, handler_slot: int) -> tuple[str, str]:
    registration = parse_registration(image, owner)
    methods = registration["vtableMethodPrefix"]
    if len(methods) <= handler_slot:
        raise ValueError(f"{owner}: handler vtable slot is absent")
    return registration["vtableRva"], methods[handler_slot]["methodRva"]


def _binding_index(bindings: dict) -> dict[tuple, dict]:
    result = {}
    for row in bindings["bindings"]:
        key = (
            row["actor"],
            row["skin"],
            row["costume"],
            row["context"],
            row["variant"],
        )
        if key in result:
            raise ValueError(f"duplicate concrete binding: {key}")
        result[key] = row
    return result


def _runtime_profile(bindings: dict, profile_id: str) -> dict:
    rows = [row for row in bindings["runtimeProfiles"] if row["id"] == profile_id]
    if len(rows) != 1 or not rows[0].get("complete"):
        raise ValueError(f"complete runtime profile is absent: {profile_id}")
    return rows[0]


def _authored(concrete: dict, profile: dict, variant: str) -> dict:
    key = (
        profile["actor"],
        profile["skin"],
        profile["costume"],
        profile["context"],
        variant,
    )
    row = concrete.get(key)
    if row is None:
        raise ValueError(f"concrete binding is absent: {profile['id']}:{variant}")
    return row


def _profile_rows(profile: dict, concrete: dict) -> list[dict]:
    rows = []
    for binding, state in profile["states"].items():
        numeric = _dictionary_slot(binding)
        dictionary, slot = _selector(state["variant"])
        if numeric != slot or dictionary != profile["skin"]:
            raise ValueError(f"runtime/selector mismatch: {profile['id']}:{binding}")
        authored = _authored(concrete, profile, state["variant"])
        if (authored.get("dictionaryId"), authored.get("slot")) != (dictionary, slot):
            raise ValueError(f"concrete selector mismatch: {profile['id']}:{binding}")
        rows.append(
            {
                "binding": binding,
                "numericStateOrEvent": numeric,
                "dictionary": dictionary,
                "slot": slot,
                "clip": _clip_id(authored),
                "runtimeVariant": state["variant"],
                "slotSelection": "numericRuntimeBinding",
                "confidence": "confirmed",
            }
        )
    return sorted(rows, key=lambda row: row["slot"])


def report(
    module: Path,
    anchors_path: Path,
    dispatch_path: Path,
    bindings_path: Path,
    config_path: Path,
    expected_hash: str,
) -> dict:
    if sha256(module) != expected_hash:
        raise ValueError("module identity does not match task 91.1 corpus")
    anchors = json.loads(anchors_path.read_text(encoding="utf-8"))
    dispatch = json.loads(dispatch_path.read_text(encoding="utf-8"))
    bindings = json.loads(bindings_path.read_text(encoding="utf-8"))
    config = json.loads(config_path.read_text(encoding="utf-8"))
    for name, data in (("anchors", anchors), ("dispatch", dispatch)):
        if data["module"]["sha256"] != expected_hash:
            raise ValueError(f"{name} belong to another module")

    image = PeImage(module)
    concrete = _binding_index(bindings)
    world_profiles = []
    for item in config["worldProfiles"]:
        profile = _runtime_profile(bindings, item["profile"])
        rows = _profile_rows(profile, concrete)
        anchor_owner = item.get("anchorOwner")
        if anchor_owner:
            anchor = _anchor(
                anchors, anchor_owner, item.get("anchorField", item["dictionaryField"])
            )
            owner_dispatch = _dispatch(dispatch, anchor_owner)
            vtable_rva = anchor["vtableRva"]
            dispatch_rva = owner_dispatch["handlerRva"]
            reference_kind = item.get("referenceKind", "typed-field")
        else:
            vtable_rva, dispatch_rva = _direct_owner(
                image, item["owner"], config["handlerVtableSlot"]
            )
            reference_kind = item["referenceKind"]
        event_states = profile.get("eventStates")
        if not event_states:
            raise ValueError(f"world event dispatch is absent: {profile['id']}")
        selected = [state for states in event_states.values() for state in states]
        if sorted(selected) != sorted(profile["states"]):
            raise ValueError(f"world event dispatch is not bijective: {profile['id']}")
        world_profiles.append(
            {
                "owner": item["owner"],
                "profile": profile["id"],
                "instance": profile["instance"],
                "ownerVtableRva": vtable_rva,
                "numericDispatchRva": dispatch_rva,
                "dictionaryField": item["dictionaryField"],
                "dictionaryReferenceKind": reference_kind,
                "eventStates": event_states,
                "bindings": rows,
            }
        )

    scene_anchor = _anchor(
        anchors, config["cinematicOwner"], config["cinematicDictionaryField"]
    )
    scene_dispatch = _dispatch(dispatch, config["cinematicOwner"])
    selector_anchor = _anchor(
        anchors,
        config["cinematicSelectorOwner"],
        config["cinematicSelectorField"],
    )
    selector_dispatch = _dispatch(dispatch, config["cinematicSelectorOwner"])
    cinematic_profiles = []
    source = [
        row
        for row in bindings["runtimeProfiles"]
        if row["id"].startswith(config["cinematicProfilePrefix"])
    ]
    for profile in source:
        rows = _profile_rows(profile, concrete)
        cue_states = profile.get("cueStates")
        if not cue_states:
            raise ValueError(f"cinematic cue dispatch is absent: {profile['id']}")
        selected = [state for states in cue_states.values() for state in states]
        if sorted(selected) != sorted(profile["states"]):
            raise ValueError(f"cinematic cue dispatch is not bijective: {profile['id']}")
        cinematic_profiles.append(
            {
                "owner": config["cinematicOwner"],
                "selectorOwner": config["cinematicSelectorOwner"],
                "profile": profile["id"],
                "instance": profile["instance"],
                "scriptEvent": profile["scriptEvent"],
                "ownerVtableRva": scene_anchor["vtableRva"],
                "numericDispatchRva": scene_dispatch["handlerRva"],
                "selectorVtableRva": selector_anchor["vtableRva"],
                "selectorDispatchRva": selector_dispatch["handlerRva"],
                "dictionaryField": config["cinematicDictionaryField"],
                "slotIndexField": config["cinematicSelectorField"],
                "cueStates": cue_states,
                "bindings": rows,
            }
        )
    cinematic_profiles.sort(key=lambda row: int(row["profile"].rsplit("-", 1)[1]))

    world_count = sum(len(row["bindings"]) for row in world_profiles)
    cinematic_count = sum(len(row["bindings"]) for row in cinematic_profiles)
    expected = (
        (len(world_profiles), config["expectedWorldProfileCount"], "world profile"),
        (world_count, config["expectedWorldBindingCount"], "world binding"),
        (
            len(cinematic_profiles),
            config["expectedCinematicTimelineCount"],
            "cinematic timeline",
        ),
        (cinematic_count, config["expectedCinematicCueCount"], "cinematic cue"),
    )
    for actual, wanted, label in expected:
        if actual != wanted:
            raise ValueError(f"{label} total changed: {actual} != {wanted}")

    return {
        "schemaVersion": 1,
        "module": {
            "name": module.name,
            "sha256": expected_hash,
            "imageBase": f"0x{image.image_base:08x}",
        },
        "summary": {
            "worldProfileCount": len(world_profiles),
            "worldBindingCount": world_count,
            "cinematicTimelineCount": len(cinematic_profiles),
            "cinematicCueCount": cinematic_count,
            "confirmedBindingCount": world_count + cinematic_count,
            "unresolvedBindingCount": 0,
        },
        "worldProfiles": world_profiles,
        "cinematicTimelines": cinematic_profiles,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("anchors", type=Path)
    parser.add_argument("dispatch", type=Path)
    parser.add_argument("bindings", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).parents[1]
        / "tools/task91/world_cinematics_profile.v1.json",
    )
    args = parser.parse_args()
    toolchain = json.loads(
        (Path(__file__).parents[1] / "tools/task91/toolchain.v1.json").read_text()
    )
    config = json.loads(args.config.read_text(encoding="utf-8"))
    result = report(
        args.game_dir / config["module"],
        args.anchors,
        args.dispatch,
        args.bindings,
        args.config,
        toolchain["expectedModules"][config["module"]],
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
