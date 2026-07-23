#!/usr/bin/env python3
"""Export metadata-only authored profiles for CKHkObelix and CKHkIdefix."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from task91_class_anchors import PeImage, sha256


def _slot(binding: str, named_slots: dict[str, int]) -> int:
    if binding.startswith("hero_slot_"):
        return int(binding.removeprefix("hero_slot_"))
    if binding in named_slots:
        return named_slots[binding]
    raise ValueError(f"unmapped named controlled-hero binding: {binding}")


def _authored_clip(variant: str) -> str:
    parts = variant.split("-")
    if len(parts) < 2 or parts[0] != "clip" or not parts[1].isdigit():
        raise ValueError(f"invalid authored clip variant: {variant}")
    return "-".join(parts[:2])


def _profile_rows(profile: dict, profile_config: dict) -> list[dict]:
    rows = []
    for binding, value in profile["states"].items():
        rows.append(
            {
                "binding": binding,
                "runtimeState": value["action"],
                "dictionary": 0,
                "slot": _slot(binding, profile_config["namedStateSlots"]),
                "clip": _authored_clip(value["variant"]),
                "runtimeVariant": value["variant"],
                "slotSelection": "numericRuntimeBinding",
                "confidence": "confirmed",
            }
        )
    return sorted(rows, key=lambda item: (item["slot"], item["binding"]))


def _validate_reuse(rows: list[dict], expected: dict[str, list[int]]) -> list[dict]:
    actual: dict[str, list[int]] = {}
    for row in rows:
        actual.setdefault(row["clip"], []).append(row["slot"])
    actual = {
        clip: sorted(slots)
        for clip, slots in actual.items()
        if len(slots) > 1
    }
    normalized_expected = {
        clip: sorted(slots) for clip, slots in expected.items()
    }
    if actual != normalized_expected:
        raise ValueError("reused authored clips changed")
    return [
        {
            "clip": clip,
            "slots": slots,
            "bindingCount": len(slots),
            "separateRuntimeBindings": True,
        }
        for clip, slots in sorted(actual.items())
    ]


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
    results = []
    for profile_config in config["profiles"]:
        owner = profile_config["owner"]
        anchor = next(
            (row for row in anchors["anchors"] if row["class"] == owner), None
        )
        if anchor is None or not any(
            row["name"] == "heroAnimDict" for row in anchor["fields"]
        ):
            raise ValueError(f"{owner} heroAnimDict anchor is absent")
        owner_dispatch = next(
            (row for row in dispatch["owners"] if row["owner"] == owner), None
        )
        if owner_dispatch is None:
            raise ValueError(f"{owner} numeric dispatch is absent")
        profile = next(
            (
                row
                for row in bindings["runtimeProfiles"]
                if row["id"] == profile_config["profile"]
            ),
            None,
        )
        if profile is None or not profile.get("complete"):
            raise ValueError(f"complete {owner} runtime profile is absent")

        rows = _profile_rows(profile, profile_config)
        if len(rows) != profile_config["expectedBindingCount"]:
            raise ValueError(f"{owner} binding count changed")
        if len({row["binding"] for row in rows}) != len(rows):
            raise ValueError(f"duplicate {owner} binding")
        reuse = _validate_reuse(rows, profile_config["reusedClips"])
        results.append(
            {
                "owner": owner,
                "profile": profile_config["profile"],
                "ownerVtableRva": anchor["vtableRva"],
                "numericDispatchRva": owner_dispatch["handlerRva"],
                "summary": {
                    "bindingCount": len(rows),
                    "confirmedBindingCount": len(rows),
                    "unresolvedBindingCount": 0,
                    "reusedClipCount": len(reuse),
                },
                "bindings": rows,
                "reusedClips": reuse,
            }
        )

    return {
        "schemaVersion": 1,
        "module": {
            "name": module.name,
            "sha256": expected_hash,
            "imageBase": f"0x{image.image_base:08x}",
        },
        "dictionaryAccess": {
            "field": config["dictionaryField"],
            "dictionary": config["dictionary"],
        },
        "summary": {
            "ownerCount": len(results),
            "bindingCount": sum(row["summary"]["bindingCount"] for row in results),
            "confirmedBindingCount": sum(
                row["summary"]["confirmedBindingCount"] for row in results
            ),
            "unresolvedBindingCount": 0,
            "reusedClipCount": sum(
                row["summary"]["reusedClipCount"] for row in results
            ),
        },
        "profiles": results,
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
        / "tools/task91/controlled_heroes_profile.v1.json",
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
