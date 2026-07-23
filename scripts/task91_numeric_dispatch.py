#!/usr/bin/env python3
"""Export metadata-only numeric state/event dispatch observations."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from task91_class_anchors import PeImage, sha256


def read_table(image: PeImage, rva: int, count: int) -> list[int]:
    offset = image.offset_from_rva(rva)
    values = struct.unpack_from(f"<{count}I", image.data, offset)
    targets = []
    for value in values:
        if not image.is_code_va(value):
            raise ValueError(f"jump table at 0x{rva:08x} contains a non-code target")
        targets.append(value - image.image_base)
    return targets


def validate_jump(image: PeImage, jump_rva: int, table_rva: int) -> None:
    offset = image.offset_from_rva(jump_rva)
    instruction = image.data[offset : offset + 7]
    table_va = image.image_base + table_rva
    if (
        len(instruction) < 7
        or instruction[:2] != b"\xff\x24"
        or instruction[2] & 0xC7 != 0x85
    ):
        raise ValueError(f"0x{jump_rva:08x} is not the configured indexed jump")
    if struct.unpack_from("<I", instruction, 3)[0] != table_va:
        raise ValueError(f"0x{jump_rva:08x} references another jump table")


def report(
    module: Path,
    anchors_path: Path,
    primitives_path: Path,
    config_path: Path,
    expected_hash: str,
) -> dict:
    if sha256(module) != expected_hash:
        raise ValueError("module identity does not match task 91.1 corpus")
    anchors = json.loads(anchors_path.read_text(encoding="utf-8"))
    primitives = json.loads(primitives_path.read_text(encoding="utf-8"))
    config = json.loads(config_path.read_text(encoding="utf-8"))
    for name, data in (("anchors", anchors), ("primitives", primitives)):
        if data["module"]["sha256"] != expected_hash:
            raise ValueError(f"{name} belong to another module")

    image = PeImage(module)
    handler_slot = config["ownerHandlerVtableSlot"]
    owners = []
    for anchor in anchors["anchors"]:
        methods = anchor["vtableMethodPrefix"]
        if len(methods) <= handler_slot:
            raise ValueError(f"{anchor['class']}: handler vtable slot is absent")
        owners.append(
            {
                "owner": anchor["class"],
                "group": anchor["group"],
                "handlerSource": f"vtablePrefix[{handler_slot}]",
                "handlerRva": methods[handler_slot]["methodRva"],
                "inputKind": "numericStateOrEvent",
                "semanticLabel": None,
            }
        )

    tables = []
    for item in config["jumpTables"]:
        jump_rva = int(item["jumpRva"], 16)
        table_rva = int(item["tableRva"], 16)
        validate_jump(image, jump_rva, table_rva)
        targets = read_table(image, table_rva, item["entryCount"])
        row = {
            "id": item["id"],
            "dispatcherRva": item["dispatcherRva"],
            "jumpRva": item["jumpRva"],
            "tableRva": item["tableRva"],
            "inputEncoding": item["inputEncoding"],
            "entries": [
                {"numericIndex": index, "branchTargetRva": f"0x{target:08x}"}
                for index, target in enumerate(targets)
            ],
            "semanticLabelsAssigned": False,
        }
        if "lookupRva" in item:
            lookup_offset = image.offset_from_rva(int(item["lookupRva"], 16))
            lookup = image.data[
                lookup_offset : lookup_offset + item["lookupEntryCount"]
            ]
            if any(value >= item["entryCount"] for value in lookup):
                raise ValueError(f"{item['id']}: lookup selects an invalid branch")
            row["numericLookup"] = [
                {"numericInput": index, "branchIndex": value}
                for index, value in enumerate(lookup)
            ]
        tables.append(row)

    known_handlers = {row["handlerRva"] for row in owners}
    primitive_indirect = {
        path["owner"]
        for path in primitives["ownerPaths"]
        if path["pathKind"] == "dataOwnerOrIndirectDispatch"
    }
    if not known_handlers or not primitive_indirect:
        raise ValueError("primitive owner dispatch evidence is incomplete")
    return {
        "schemaVersion": 1,
        "module": {
            "name": module.name,
            "sha256": expected_hash,
            "imageBase": f"0x{image.image_base:08x}",
        },
        "summary": {
            "ownerCount": len(owners),
            "jumpTableCount": len(tables),
            "jumpTableEntryCount": sum(len(row["entries"]) for row in tables),
            "semanticLabelCount": 0,
            "unresolvedOwnerCount": 0,
        },
        "owners": owners,
        "jumpTables": tables,
        "primitiveIndirectOwners": sorted(primitive_indirect),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("anchors", type=Path)
    parser.add_argument("primitives", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).parents[1] / "tools/task91/numeric_dispatch.v1.json",
    )
    args = parser.parse_args()
    toolchain = json.loads(
        (Path(__file__).parents[1] / "tools/task91/toolchain.v1.json").read_text()
    )
    config = json.loads(args.config.read_text(encoding="utf-8"))
    result = report(
        args.game_dir / config["module"],
        args.anchors,
        args.primitives,
        args.config,
        toolchain["expectedModules"][config["module"]],
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
