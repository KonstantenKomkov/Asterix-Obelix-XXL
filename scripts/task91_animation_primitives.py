#!/usr/bin/env python3
"""Export metadata-only animation primitive xrefs and owner call paths."""

from __future__ import annotations

import argparse
import bisect
import json
import struct
from collections import defaultdict, deque
from pathlib import Path

from task91_class_anchors import PeImage, sha256


def direct_calls(image: PeImage) -> list[tuple[int, int]]:
    """Return validated near-call edges from executable PE sections."""
    edges = []
    code_ranges = [
        section for section in image.sections if section["flags"] & 0x20000000
    ]
    for section in code_ranges:
        start = section["raw"]
        end = start + section["raw_size"] - 4
        for offset in range(start, end):
            if image.data[offset] != 0xE8:
                continue
            source = image.rva_from_offset(offset)
            displacement = struct.unpack_from("<i", image.data, offset + 1)[0]
            target = (source + 5 + displacement) & 0xFFFFFFFF
            if image.is_code_va(image.image_base + target):
                edges.append((source, target))
    return edges


def function_graph(
    edges: list[tuple[int, int]], entrypoints: set[int]
) -> dict[int, set[int]]:
    """Assign call sites to the nearest known entrypoint."""
    starts = sorted(entrypoints | {target for _, target in edges})
    graph: dict[int, set[int]] = defaultdict(set)
    for source, target in edges:
        index = bisect.bisect_right(starts, source) - 1
        if index >= 0:
            graph[starts[index]].add(target)
    return graph


def shortest_path(
    graph: dict[int, set[int]], roots: list[int], targets: set[int]
) -> list[int] | None:
    queue = deque((root, [root]) for root in roots)
    seen = set(roots)
    while queue:
        node, path = queue.popleft()
        if node in targets:
            return path
        if len(path) >= 10:
            continue
        for child in sorted(graph.get(node, ())):
            if child not in seen:
                seen.add(child)
                queue.append((child, path + [child]))
    return None


def report(
    module: Path, anchors_path: Path, config_path: Path, expected_hash: str
) -> dict:
    if sha256(module) != expected_hash:
        raise ValueError("module identity does not match task 91.1 corpus")
    anchors = json.loads(anchors_path.read_text(encoding="utf-8"))
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if anchors["module"]["sha256"] != expected_hash:
        raise ValueError("class anchors belong to another module")
    image = PeImage(module)
    edges = direct_calls(image)
    primitives = {item["id"]: int(item["rva"], 16) for item in config["primitives"]}
    primitive_rvas = set(primitives.values())
    selector_rvas = {
        int(item["rva"], 16) for item in config["dictionarySelectors"]
    }
    roots = {
        anchor["class"]: [
            int(method["methodRva"], 16) for method in anchor["vtableMethodPrefix"]
        ]
        for anchor in anchors["anchors"]
    }
    entrypoints = primitive_rvas | selector_rvas | {
        method for methods in roots.values() for method in methods
    }
    graph = function_graph(edges, entrypoints)

    primitive_rows = []
    for item in config["primitives"]:
        target = int(item["rva"], 16)
        xrefs = sorted(source for source, destination in edges if destination == target)
        if len(xrefs) != item["expectedDirectXrefs"]:
            raise ValueError(
                f"{item['id']}: expected {item['expectedDirectXrefs']} direct xrefs, "
                f"found {len(xrefs)}"
            )
        primitive_rows.append(
            {
                "id": item["id"],
                "kind": item["kind"],
                "rva": item["rva"],
                "signature": {
                    "callingConvention": "thiscall",
                    "evidence": "staticCallAndDataFlow",
                },
                "directXrefCount": len(xrefs),
                "directXrefRvas": [f"0x{rva:08x}" for rva in xrefs],
            }
        )

    owner_paths = []
    for class_name, methods in roots.items():
        path = shortest_path(graph, methods, primitive_rvas)
        owner_paths.append(
            {
                "owner": class_name,
                "pathKind": "directCallGraph" if path else "dataOwnerOrIndirectDispatch",
                "rvas": [f"0x{rva:08x}" for rva in (path or [])],
            }
        )
    selectors = []
    for selector in config["dictionarySelectors"]:
        selector_rva = int(selector["rva"], 16)
        target_rva = primitives[selector["calls"]]
        if not shortest_path(graph, [selector_rva], {target_rva}):
            raise ValueError(f"{selector['id']}: selector does not reach configured primitive")
        selectors.append(
            {
                **selector,
                "evidence": "indexedDictionarySlotRead",
            }
        )

    return {
        "schemaVersion": 1,
        "module": {
            "name": module.name,
            "sha256": expected_hash,
            "imageBase": f"0x{image.image_base:08x}",
        },
        "summary": {
            "primitiveCount": len(primitive_rows),
            "directXrefCount": sum(row["directXrefCount"] for row in primitive_rows),
            "selectorCount": len(selectors),
            "ownerCount": len(owner_paths),
            "unresolvedPrimitiveCount": 0,
        },
        "primitives": primitive_rows,
        "dictionarySelectors": selectors,
        "ownerPaths": owner_paths,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("anchors", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).parents[1]
        / "tools/task91/animation_primitives.v1.json",
    )
    args = parser.parse_args()
    toolchain = json.loads(
        (Path(__file__).parents[1] / "tools/task91/toolchain.v1.json").read_text()
    )
    config = json.loads(args.config.read_text(encoding="utf-8"))
    module = args.game_dir / config["module"]
    result = report(
        module,
        args.anchors,
        args.config,
        toolchain["expectedModules"][config["module"]],
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
