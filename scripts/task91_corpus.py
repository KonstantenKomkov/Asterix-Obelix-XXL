#!/usr/bin/env python3
"""Build a deterministic, metadata-only corpus manifest for task 91.

The tool deliberately does not copy binary contents or emit disassembly.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path


def _u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def _u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def _cstring(data: bytes, offset: int) -> str:
    end = data.find(b"\0", offset)
    if end < 0:
        end = len(data)
    return data[offset:end].decode("ascii", errors="replace")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_pe(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise ValueError(f"{path}: missing DOS MZ header")
    pe_offset = _u32(data, 0x3C)
    if pe_offset + 24 > len(data) or data[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise ValueError(f"{path}: missing PE signature")

    coff = pe_offset + 4
    machine = _u16(data, coff)
    section_count = _u16(data, coff + 2)
    timestamp = _u32(data, coff + 4)
    optional_size = _u16(data, coff + 16)
    characteristics = _u16(data, coff + 18)
    optional = coff + 20
    magic = _u16(data, optional)
    if magic not in (0x10B, 0x20B):
        raise ValueError(f"{path}: unsupported optional header magic 0x{magic:04x}")
    pe32_plus = magic == 0x20B
    image_base = (
        struct.unpack_from("<Q", data, optional + 24)[0]
        if pe32_plus
        else _u32(data, optional + 28)
    )
    directory_offset = optional + (112 if pe32_plus else 96)
    number_of_directories = _u32(data, optional + (108 if pe32_plus else 92))
    section_offset = optional + optional_size
    sections = []
    for index in range(section_count):
        cursor = section_offset + index * 40
        if cursor + 40 > len(data):
            raise ValueError(f"{path}: truncated section table")
        name = data[cursor : cursor + 8].split(b"\0", 1)[0].decode(
            "ascii", errors="replace"
        )
        sections.append(
            {
                "name": name,
                "virtualSize": _u32(data, cursor + 8),
                "virtualAddress": f"0x{_u32(data, cursor + 12):08x}",
                "rawSize": _u32(data, cursor + 16),
                "rawOffset": _u32(data, cursor + 20),
                "characteristics": f"0x{_u32(data, cursor + 36):08x}",
            }
        )

    def rva_offset(rva: int) -> int | None:
        for section in sections:
            start = int(section["virtualAddress"], 16)
            extent = max(section["virtualSize"], section["rawSize"])
            if start <= rva < start + extent:
                offset = section["rawOffset"] + rva - start
                return offset if offset < len(data) else None
        return rva if rva < len(data) else None

    def directory(index: int) -> tuple[int, int]:
        if index >= number_of_directories:
            return (0, 0)
        cursor = directory_offset + index * 8
        if cursor + 8 > section_offset:
            return (0, 0)
        return (_u32(data, cursor), _u32(data, cursor + 4))

    import_rva, _ = directory(1)
    imports = []
    cursor = rva_offset(import_rva) if import_rva else None
    while cursor is not None and cursor + 20 <= len(data):
        descriptor = struct.unpack_from("<IIIII", data, cursor)
        if not any(descriptor):
            break
        name_offset = rva_offset(descriptor[3])
        if name_offset is None:
            raise ValueError(f"{path}: invalid import name RVA")
        imports.append(_cstring(data, name_offset))
        cursor += 20

    debug_rva, debug_size = directory(6)
    debug_entries = []
    cursor = rva_offset(debug_rva) if debug_rva else None
    if cursor is not None:
        for _ in range(debug_size // 28):
            if cursor + 28 > len(data):
                raise ValueError(f"{path}: truncated debug directory")
            _, debug_timestamp, major, minor, kind, size, _, raw = struct.unpack_from(
                "<IIHHIIII", data, cursor
            )
            entry = {
                "type": kind,
                "timestamp": debug_timestamp,
                "version": f"{major}.{minor}",
                "size": size,
            }
            if kind == 2 and raw + size <= len(data):
                payload = data[raw : raw + size]
                if payload.startswith(b"RSDS") and len(payload) > 24:
                    entry["pdbPath"] = _cstring(payload, 24)
                elif payload.startswith(b"NB10") and len(payload) > 16:
                    entry["pdbPath"] = _cstring(payload, 16)
            debug_entries.append(entry)
            cursor += 28

    rtti_names = set()
    for marker in (b".?AV", b".?AU"):
        start = 0
        while True:
            start = data.find(marker, start)
            if start < 0:
                break
            name = _cstring(data, start)
            if name.endswith("@@") and len(name) <= 512:
                rtti_names.add(name)
            start += len(marker)

    machine_names = {0x14C: "x86", 0x8664: "x86_64", 0x1C0: "arm"}
    return {
        "sha256": _sha256(path),
        "size": len(data),
        "format": "PE32+" if pe32_plus else "PE32",
        "machine": machine_names.get(machine, f"0x{machine:04x}"),
        "coffTimestamp": timestamp,
        "imageBase": f"0x{image_base:08x}",
        "characteristics": f"0x{characteristics:04x}",
        "sections": sections,
        "imports": sorted(set(imports), key=str.lower),
        "rtti": {
            "msvcTypeDescriptorCount": len(rtti_names),
            "present": bool(rtti_names),
        },
        "debug": {
            "directoryPresent": bool(debug_entries),
            "entries": debug_entries,
            "pdbPresent": any("pdbPath" in item for item in debug_entries),
        },
    }


def build_manifest(game_dir: Path) -> dict:
    symbol_files = sorted(
        (
            path.relative_to(game_dir).as_posix()
            for path in game_dir.rglob("*")
            if path.is_file() and path.suffix.lower() in {".pdb", ".map"}
        ),
        key=str.lower,
    )
    modules = []
    for name in ("Asterix.exe", "GameModule.elb"):
        path = game_dir / name
        if not path.is_file():
            raise ValueError(f"required module is missing: {path}")
        modules.append({"path": name, **inspect_pe(path)})
    data_files = []
    kwn_paths = (
        path
        for path in game_dir.rglob("*")
        if path.is_file() and path.suffix.lower() == ".kwn"
    )
    for path in sorted(kwn_paths, key=lambda item: item.as_posix().lower()):
        data_files.append(
            {
                "path": path.relative_to(game_dir).as_posix(),
                "size": path.stat().st_size,
                "sha256": _sha256(path),
            }
        )
    if not data_files:
        raise ValueError(f"no KWN files found below {game_dir}")
    return {
        "schemaVersion": 1,
        "corpus": "Asterix & Obelix XXL PC",
        "modules": modules,
        "externalSymbolFiles": symbol_files,
        "dataFiles": data_files,
        "summary": {
            "moduleCount": len(modules),
            "dataFileCount": len(data_files),
            "dataBytes": sum(item["size"] for item in data_files),
            "externalSymbolFileCount": len(symbol_files),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = build_manifest(args.game_dir.resolve())
    encoded = json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(encoded, encoding="utf-8")
    print(
        f"Wrote {args.output}: {manifest['summary']['moduleCount']} PE modules, "
        f"{manifest['summary']['dataFileCount']} KWN files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
