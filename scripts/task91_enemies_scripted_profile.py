#!/usr/bin/env python3
"""Export metadata-only authored profiles for enemies and scripted actors."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from task91_class_anchors import PeImage, sha256


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
    clip = binding.get("clip", "")
    stem = clip.removesuffix(".animation.json")
    if len(stem) != 4 or not stem.isdigit():
        raise ValueError(f"invalid authored clip: {clip}")
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


def _binding_key(profile: dict, variant: str) -> tuple:
    return (
        profile["actor"],
        profile["skin"],
        profile["costume"],
        profile["context"],
        variant,
    )


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


def _profile(bindings: dict, profile_id: str) -> dict:
    row = next(
        (item for item in bindings["runtimeProfiles"] if item["id"] == profile_id),
        None,
    )
    if row is None or not row.get("complete"):
        raise ValueError(f"complete runtime profile is absent: {profile_id}")
    return row


def _enemy_rows(profile: dict, concrete: dict, dictionary: int) -> list[dict]:
    rows = []
    for binding, state in profile["states"].items():
        runtime_slot = _dictionary_slot(binding)
        selector_dictionary, selector_slot = _selector(state["variant"])
        if (selector_dictionary, selector_slot) != (dictionary, runtime_slot):
            raise ValueError(f"enemy runtime/selector mismatch: {profile['id']}:{binding}")
        authored = concrete.get(_binding_key(profile, state["variant"]))
        if authored is None:
            raise ValueError(f"concrete enemy binding is absent: {profile['id']}:{binding}")
        if (authored.get("dictionaryId"), authored.get("slot")) != (
            dictionary,
            runtime_slot,
        ):
            raise ValueError(f"enemy concrete selector mismatch: {profile['id']}:{binding}")
        rows.append(
            {
                "binding": binding,
                "numericStateOrEvent": runtime_slot,
                "dictionary": dictionary,
                "slot": runtime_slot,
                "clip": _clip_id(authored),
                "runtimeVariant": state["variant"],
                "slotSelection": "numericRuntimeBinding",
                "confidence": "confirmed",
            }
        )
    return sorted(rows, key=lambda item: item["slot"])


def _scripted_row(profile: dict, concrete: dict) -> dict:
    if set(profile["states"]) != {"script_event"}:
        raise ValueError(f"scripted owner is not a single exact event: {profile['id']}")
    state = profile["states"]["script_event"]
    dictionary, slot = _selector(state["variant"])
    if dictionary != profile["skin"]:
        raise ValueError(f"scripted dictionary/skin mismatch: {profile['id']}")
    authored = concrete.get(_binding_key(profile, state["variant"]))
    if authored is None:
        raise ValueError(f"concrete scripted binding is absent: {profile['id']}")
    if (authored.get("dictionaryId"), authored.get("slot")) != (dictionary, slot):
        raise ValueError(f"scripted concrete selector mismatch: {profile['id']}")
    return {
        "binding": "script_event",
        "scriptEvent": profile["scriptEvent"],
        "numericStateOrEvent": slot,
        "dictionary": dictionary,
        "slot": slot,
        "clip": _clip_id(authored),
        "runtimeVariant": state["variant"],
        "slotSelection": "numericRuntimeBinding",
        "confidence": "confirmed",
    }


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

    concrete = _binding_index(bindings)
    enemy_profiles = []
    for item in config["enemyProfiles"]:
        anchor = _anchor(anchors, item["owner"], item["dictionaryField"])
        owner_dispatch = _dispatch(dispatch, item["owner"])
        runtime_profile = _profile(bindings, item["profile"])
        rows = _enemy_rows(runtime_profile, concrete, item["dictionary"])
        if len(rows) != item["expectedBindingCount"]:
            raise ValueError(f"{item['profile']} binding count changed")
        enemy_profiles.append(
            {
                "owner": item["owner"],
                "profile": item["profile"],
                "ownerVtableRva": anchor["vtableRva"],
                "numericDispatchRva": owner_dispatch["handlerRva"],
                "dictionaryField": item["dictionaryField"],
                "dictionary": item["dictionary"],
                "bindings": rows,
            }
        )

    composite = config["compositeLeader"]
    equipment = next(
        row for row in enemy_profiles if row["profile"] == composite["equipmentProfile"]
    )
    body = next(
        row for row in enemy_profiles if row["profile"] == composite["bodyProfile"]
    )
    equipment_by_slot = {row["slot"]: row for row in equipment["bindings"]}
    body_by_slot = {row["slot"]: row for row in body["bindings"]}
    synchronized = []
    for slot in composite["synchronizedSlots"]:
        if slot not in equipment_by_slot or slot not in body_by_slot:
            raise ValueError(f"composite leader synchronized slot is absent: {slot}")
        synchronized.append(
            {
                "numericStateOrEvent": slot,
                "body": {
                    "dictionary": body["dictionary"],
                    "slot": slot,
                    "clip": body_by_slot[slot]["clip"],
                },
                "equipment": {
                    "dictionary": equipment["dictionary"],
                    "slot": slot,
                    "clip": equipment_by_slot[slot]["clip"],
                },
                "selection": "synchronous",
                "confidence": "confirmed",
            }
        )

    scripted_profiles = []
    scripted_source = [
        row
        for row in bindings["runtimeProfiles"]
        if row["id"].startswith(config["scriptedProfilePrefix"])
    ]
    if len(scripted_source) != config["expectedScriptedOwnerCount"]:
        raise ValueError("scripted owner count changed")
    seen_events = set()
    for runtime_profile in scripted_source:
        owner_kind = runtime_profile["actor"].split(":", 1)[0]
        owner_config = config["scriptedOwnerKinds"].get(owner_kind)
        if owner_config is None:
            raise ValueError(f"unknown scripted owner kind: {owner_kind}")
        anchor = _anchor(
            anchors, owner_config["owner"], owner_config["dictionaryField"]
        )
        owner_dispatch = _dispatch(dispatch, owner_config["owner"])
        row = _scripted_row(runtime_profile, concrete)
        if row["scriptEvent"] in seen_events:
            raise ValueError(f"duplicate scripted event: {row['scriptEvent']}")
        seen_events.add(row["scriptEvent"])
        scripted_profiles.append(
            {
                "owner": owner_config["owner"],
                "instance": runtime_profile["instance"],
                "profile": runtime_profile["id"],
                "ownerVtableRva": anchor["vtableRva"],
                "numericDispatchRva": owner_dispatch["handlerRva"],
                "dictionaryField": owner_config["dictionaryField"],
                "binding": row,
            }
        )
    scripted_profiles.sort(key=lambda item: item["binding"]["dictionary"])

    enemy_count = sum(len(row["bindings"]) for row in enemy_profiles)
    if enemy_count != config["expectedEnemyBindingCount"]:
        raise ValueError("enemy binding total changed")
    if len(scripted_profiles) != config["expectedScriptedBindingCount"]:
        raise ValueError("scripted binding total changed")

    image = PeImage(module)
    return {
        "schemaVersion": 1,
        "module": {
            "name": module.name,
            "sha256": expected_hash,
            "imageBase": f"0x{image.image_base:08x}",
        },
        "summary": {
            "enemyProfileCount": len(enemy_profiles),
            "enemyBindingCount": enemy_count,
            "scriptedOwnerCount": len(scripted_profiles),
            "scriptedBindingCount": len(scripted_profiles),
            "compositeSynchronizedSelectionCount": len(synchronized),
            "confirmedBindingCount": enemy_count + len(scripted_profiles),
            "unresolvedBindingCount": 0,
        },
        "enemyProfiles": enemy_profiles,
        "compositeLeader": {
            "owner": composite["owner"],
            "bodyProfile": composite["bodyProfile"],
            "equipmentProfile": composite["equipmentProfile"],
            "synchronizedSelections": synchronized,
        },
        "scriptedProfiles": scripted_profiles,
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
        / "tools/task91/enemies_scripted_profile.v1.json",
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
