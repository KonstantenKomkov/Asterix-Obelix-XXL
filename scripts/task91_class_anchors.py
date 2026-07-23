#!/usr/bin/env python3
"""Export class/function anchors without publishing original code or bytes."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


class PeImage:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if self.data[:2] != b"MZ":
            raise ValueError("module is not a PE image")
        pe = u32(self.data, 0x3C)
        if self.data[pe : pe + 4] != b"PE\0\0":
            raise ValueError("module has no PE signature")
        coff = pe + 4
        count = u16(self.data, coff + 2)
        optional_size = u16(self.data, coff + 16)
        optional = coff + 20
        if u16(self.data, optional) != 0x10B:
            raise ValueError("task 91 anchors require PE32")
        self.image_base = u32(self.data, optional + 28)
        section_table = optional + optional_size
        self.sections = []
        for index in range(count):
            cursor = section_table + index * 40
            name = self.data[cursor : cursor + 8].split(b"\0", 1)[0].decode()
            self.sections.append(
                {
                    "name": name,
                    "virtual_size": u32(self.data, cursor + 8),
                    "rva": u32(self.data, cursor + 12),
                    "raw_size": u32(self.data, cursor + 16),
                    "raw": u32(self.data, cursor + 20),
                    "flags": u32(self.data, cursor + 36),
                }
            )

    def rva_from_offset(self, offset: int) -> int:
        for section in self.sections:
            start = section["raw"]
            if start <= offset < start + section["raw_size"]:
                return section["rva"] + offset - start
        raise ValueError(f"file offset 0x{offset:x} is outside sections")

    def offset_from_rva(self, rva: int) -> int:
        for section in self.sections:
            start = section["rva"]
            extent = max(section["virtual_size"], section["raw_size"])
            if start <= rva < start + extent:
                return section["raw"] + rva - start
        raise ValueError(f"RVA 0x{rva:x} is outside sections")

    def is_code_va(self, value: int) -> bool:
        rva = value - self.image_base
        return any(
            section["flags"] & 0x20000000
            and section["rva"] <= rva < section["rva"] + section["virtual_size"]
            for section in self.sections
        )

    def is_readonly_va(self, value: int) -> bool:
        rva = value - self.image_base
        return any(
            not section["flags"] & 0x80000000
            and section["rva"] <= rva < section["rva"] + section["virtual_size"]
            for section in self.sections
        )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def decode_push(data: bytes, cursor: int) -> tuple[int, int]:
    if data[cursor] == 0x6A:
        return data[cursor + 1], cursor + 2
    if data[cursor] == 0x68:
        return u32(data, cursor + 1), cursor + 5
    raise ValueError(f"expected push at file offset 0x{cursor:x}")


def find_vtable(image: PeImage, factory_rva: int) -> tuple[int, int]:
    """Follow a small factory wrapper and find its constructor vptr store."""
    pending = [factory_rva]
    visited = set()
    while pending:
        function_rva = pending.pop(0)
        if function_rva in visited:
            continue
        visited.add(function_rva)
        start = image.offset_from_rva(function_rva)
        block = image.data[start : start + 256]
        for index in range(len(block) - 6):
            # mov dword ptr [eax/ecx/esi/edi], imm32
            if block[index] == 0xC7 and block[index + 1] in (0x00, 0x01, 0x06, 0x07):
                value = u32(block, index + 2)
                if image.is_readonly_va(value):
                    return image.rva_from_offset(start + index), value - image.image_base
            if block[index] == 0xE9:
                origin = image.rva_from_offset(start + index)
                target = origin + 5 + struct.unpack_from("<i", block, index + 1)[0]
                if image.is_code_va(image.image_base + target):
                    pending.append(target)
    raise ValueError(f"factory RVA 0x{factory_rva:08x} has no vtable store")


def vtable_method_prefix(image: PeImage, vtable_rva: int) -> list[dict]:
    cursor = image.offset_from_rva(vtable_rva)
    methods = []
    # MSVC places adjacent vtables without a portable terminator. Export only
    # the common, independently addressable prefix; do not invent a boundary.
    for slot in range(15):
        value = u32(image.data, cursor)
        if not image.is_code_va(value):
            break
        methods.append({"slot": slot, "methodRva": f"0x{value - image.image_base:08x}"})
        cursor += 4
    if len(methods) < 4:
        raise ValueError(f"vtable RVA 0x{vtable_rva:08x} is implausibly short")
    return methods


def parse_registration(image: PeImage, class_name: str) -> dict:
    marker = class_name.encode("ascii") + b"\0"
    offsets = []
    cursor = 0
    while True:
        cursor = image.data.find(marker, cursor)
        if cursor < 0:
            break
        offsets.append(cursor)
        cursor += len(marker)
    if len(offsets) != 1:
        raise ValueError(f"{class_name}: expected one class string, found {len(offsets)}")
    string_rva = image.rva_from_offset(offsets[0])
    reference = struct.pack("<I", image.image_base + string_rva)
    refs = []
    cursor = 0
    while True:
        cursor = image.data.find(reference, cursor)
        if cursor < 0:
            break
        if cursor > 0 and image.data[cursor - 1] == 0x68:
            refs.append(cursor - 1)
        cursor += 4
    if len(refs) != 1:
        raise ValueError(f"{class_name}: expected one registration xref, found {len(refs)}")

    cursor = refs[0]
    pushes = []
    for _ in range(8):
        value, cursor = decode_push(image.data, cursor)
        pushes.append(value)
    registration_rva = image.rva_from_offset(refs[0])
    factory_rva = pushes[4] - image.image_base
    array_factory_rva = pushes[2] - image.image_base
    vptr_store_rva, vtable_rva = find_vtable(image, factory_rva)
    return {
        "class": class_name,
        "registrationRva": f"0x{registration_rva:08x}",
        "classStringRva": f"0x{string_rva:08x}",
        "factoryRva": f"0x{factory_rva:08x}",
        "arrayFactoryRva": f"0x{array_factory_rva:08x}",
        "vptrStoreRva": f"0x{vptr_store_rva:08x}",
        "vtableRva": f"0x{vtable_rva:08x}",
        "vtableMethodPrefix": vtable_method_prefix(image, vtable_rva),
        "classId": pushes[6],
        "category": pushes[7],
        "serializedMemberCount": pushes[5],
    }


def source_layouts(root: Path, owners: list[dict]) -> dict[str, dict]:
    headers = list(root.rglob("*.h"))
    result = {}
    for owner in owners:
        fields = []
        layouts = [
            {
                "declaredBy": owner.get("declaredBy", owner["class"]),
                "fields": owner["fields"],
            },
            *owner.get("additionalLayouts", []),
        ]
        for layout in layouts:
            declared_by = layout["declaredBy"]
            candidates = []
            for path in headers:
                text = path.read_text(encoding="utf-8", errors="replace")
                for match in re.finditer(
                    rf"struct\s+{re.escape(declared_by)}\s*:[^{{]+{{(.*?)\n\s*}};",
                    text,
                    re.DOTALL,
                ):
                    body = match.group(1)
                    if all(
                        re.search(rf"\b{re.escape(field)}\b", body)
                        for field in layout["fields"]
                    ):
                        candidates.append((path, body))
            if not candidates:
                raise ValueError(f"XXL-Editor has no layout for {declared_by}")
            x1_candidates = [
                candidate
                for candidate in candidates
                if candidate[0].as_posix().endswith("GameClasses/CKGameX1.h")
            ]
            if x1_candidates:
                candidates = x1_candidates
            if len(candidates) != 1:
                raise ValueError(f"XXL-Editor layout for {declared_by} is ambiguous")
            source_path, body = candidates[0]
            for field in layout["fields"]:
                declaration = re.search(
                    rf"^[^\n;]*\b{re.escape(field)}\b[^;]*;", body, re.MULTILINE
                )
                if not declaration:
                    raise ValueError(f"XXL-Editor {declared_by} has no field {field}")
                fields.append(
                    {
                        "name": field,
                        "declaredBy": declared_by,
                        "declarationOrdinal": len(
                            re.findall(r";", body[: declaration.start()])
                        ),
                        "source": source_path.relative_to(root).as_posix(),
                    }
                )
        result[owner["class"]] = {"fields": fields}
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("xxl_editor", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).parents[1] / "tools/task91/class_anchors.v1.json",
    )
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    toolchain = json.loads(
        (Path(__file__).parents[1] / "tools/task91/toolchain.v1.json").read_text()
    )
    module = args.game_dir / config["module"]
    if sha256(module) != toolchain["expectedModules"][config["module"]]:
        raise SystemExit("module identity does not match task 91.1 corpus")
    revision = subprocess.run(
        ["git", "-C", str(args.xxl_editor), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if revision != config["xxlEditorRevision"]:
        raise SystemExit("XXL-Editor revision does not match class anchor config")
    if subprocess.run(
        ["git", "-C", str(args.xxl_editor), "status", "--porcelain"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout:
        raise SystemExit("XXL-Editor checkout must be clean")

    image = PeImage(module)
    layouts = source_layouts(args.xxl_editor, config["owners"])
    anchors = []
    for owner in config["owners"]:
        anchor = parse_registration(image, owner["class"])
        anchor["group"] = owner["group"]
        anchor.update(layouts[owner["class"]])
        anchors.append(anchor)
    report = {
        "schemaVersion": 1,
        "module": {
            "name": module.name,
            "sha256": sha256(module),
            "imageBase": f"0x{image.image_base:08x}",
        },
        "xxlEditor": {"revision": revision},
        "summary": {
            "ownerCount": len(anchors),
            "fieldCount": sum(len(item["fields"]) for item in anchors),
            "unresolvedCount": 0,
        },
        "anchors": anchors,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
