#!/usr/bin/env python3
"""Export the metadata-only authored animation profile for CKHkAsterix."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from task91_class_anchors import PeImage, sha256


def _rva(value: str) -> int:
    return int(value, 16)


def _validate_relative_call(image: PeImage, call_rva: int, target_rva: int) -> None:
    offset = image.offset_from_rva(call_rva)
    if image.data[offset] != 0xE8:
        raise ValueError(f"0x{call_rva:08x} is not a relative call")
    displacement = struct.unpack_from("<i", image.data, offset + 1)[0]
    if call_rva + 5 + displacement != target_rva:
        raise ValueError(f"0x{call_rva:08x} calls another primitive")


def _profile_slots(profile: dict, named_slots: dict[str, int]) -> list[dict]:
    rows = []
    for binding, value in profile["states"].items():
        if binding.startswith("hero_slot_"):
            slot = int(binding.removeprefix("hero_slot_"))
        elif binding in named_slots:
            slot = named_slots[binding]
        else:
            raise ValueError(f"unmapped named Asterix binding: {binding}")
        rows.append(
            {
                "binding": binding,
                "runtimeState": value["action"],
                "dictionary": 0,
                "slot": slot,
                "clip": value["variant"],
                "slotSelection": "numericRuntimeBinding",
                "confidence": "confirmed",
            }
        )
    return sorted(rows, key=lambda item: (item["slot"], item["binding"]))


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

    anchor = next(
        (row for row in anchors["anchors"] if row["class"] == config["owner"]), None
    )
    if anchor is None or not any(
        row["name"] == "heroAnimDict" for row in anchor["fields"]
    ):
        raise ValueError("CKHkAsterix heroAnimDict anchor is absent")
    owner_dispatch = next(
        (row for row in dispatch["owners"] if row["owner"] == config["owner"]), None
    )
    if owner_dispatch is None:
        raise ValueError("CKHkAsterix numeric dispatch is absent")
    profile = next(
        (
            row
            for row in bindings["runtimeProfiles"]
            if row["id"] == config["profile"]
        ),
        None,
    )
    if profile is None or not profile.get("complete"):
        raise ValueError("complete Asterix runtime profile is absent")

    rows = _profile_slots(profile, config["namedStateSlots"])
    if len(rows) != config["expectedBindingCount"]:
        raise ValueError("Asterix binding count changed")
    if len({row["binding"] for row in rows}) != len(rows):
        raise ValueError("duplicate Asterix binding")
    if len({row["clip"] for row in rows}) != len(rows):
        raise ValueError("Asterix bindings are not bijective with authored clips")

    image = PeImage(module)
    primitive_rva = _rva(config["slotReadPrimitiveRva"])
    chains = []
    for chain in config["jumpChains"]:
        call_rva = _rva(chain["slotReadCallRva"])
        _validate_relative_call(image, call_rva, primitive_rva)
        binding = next((row for row in rows if row["binding"] == chain["binding"]), None)
        if binding is None or binding["slot"] != chain["slot"]:
            raise ValueError(f"{chain['semantic']}: profile slot does not match trace")
        chains.append(
            {
                **chain,
                "dictionary": config["dictionary"],
                "clip": binding["clip"],
                "confidence": "confirmed",
            }
        )
    if len(chains) != 2 or len({row["slot"] for row in chains}) != 2:
        raise ValueError("single/double jump require two distinct slot chains")
    if len({tuple(row["inputTrace"]) for row in chains}) != 2:
        raise ValueError("single/double jump require distinct input traces")

    return {
        "schemaVersion": 1,
        "module": {
            "name": module.name,
            "sha256": expected_hash,
            "imageBase": f"0x{image.image_base:08x}",
        },
        "owner": config["owner"],
        "ownerVtableRva": anchor["vtableRva"],
        "numericDispatchRva": owner_dispatch["handlerRva"],
        "dictionaryAccess": {
            "field": config["dictionaryField"],
            "dictionary": config["dictionary"],
            "slotReadPrimitiveRva": config["slotReadPrimitiveRva"],
        },
        "summary": {
            "bindingCount": len(rows),
            "confirmedBindingCount": len(rows),
            "unresolvedBindingCount": 0,
            "jumpChainCount": len(chains),
        },
        "bindings": rows,
        "jumpChains": chains,
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
        default=Path(__file__).parents[1] / "tools/task91/asterix_profile.v1.json",
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
