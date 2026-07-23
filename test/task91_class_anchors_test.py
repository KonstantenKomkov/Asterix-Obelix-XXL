import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "task91_class_anchors",
    Path(__file__).parents[1] / "scripts" / "task91_class_anchors.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def synthetic_anchor_pe() -> bytes:
    data = bytearray(0x800)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", data, 0x84, 0x14C, 2, 0, 0, 0, 0xE0, 0x102)
    optional = 0x98
    struct.pack_into("<H", data, optional, 0x10B)
    struct.pack_into("<I", data, optional + 28, 0x400000)
    section = optional + 0xE0
    data[section : section + 8] = b".text\0\0\0"
    struct.pack_into("<IIII", data, section + 8, 0x200, 0x1000, 0x200, 0x200)
    struct.pack_into("<I", data, section + 36, 0x60000020)
    section += 40
    data[section : section + 8] = b".rdata\0\0"
    struct.pack_into("<IIII", data, section + 8, 0x200, 0x2000, 0x200, 0x400)
    struct.pack_into("<I", data, section + 36, 0x40000040)

    # Registration at RVA 0x1000.
    cursor = 0x200
    for value in (0x402080, 0x401090, 0x401040, 0x401080, 0x401020):
        data[cursor] = 0x68
        struct.pack_into("<I", data, cursor + 1, value)
        cursor += 5
    for value in (7, 28, 2):
        data[cursor : cursor + 2] = bytes((0x6A, value))
        cursor += 2

    # Factory jumps to constructor; constructor stores vtable 0x402000.
    data[0x220] = 0xE9
    struct.pack_into("<i", data, 0x221, 0x1030 - 0x1025)
    data[0x230:0x236] = b"\xC7\x06" + struct.pack("<I", 0x402000)
    for index, rva in enumerate((0x1040, 0x1050, 0x1060, 0x1070)):
        struct.pack_into("<I", data, 0x400 + index * 4, 0x400000 + rva)
    struct.pack_into("<I", data, 0x410, 0)
    data[0x480 : 0x480 + len(b"CKHkAsterix\0")] = b"CKHkAsterix\0"
    return bytes(data)


class Task91ClassAnchorsTest(unittest.TestCase):
    def test_extracts_registration_factory_vtable_and_methods(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.exe"
            path.write_bytes(synthetic_anchor_pe())
            anchor = MODULE.parse_registration(MODULE.PeImage(path), "CKHkAsterix")
        self.assertEqual(anchor["registrationRva"], "0x00001000")
        self.assertEqual(anchor["factoryRva"], "0x00001020")
        self.assertEqual(anchor["vtableRva"], "0x00002000")
        self.assertEqual(anchor["classId"], 28)
        self.assertEqual(anchor["category"], 2)
        self.assertEqual(len(anchor["vtableMethodPrefix"]), 4)

    def test_validates_xxl_editor_field_layouts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "layout.h").write_text(
                "struct CKHkHero : CKBase {\n"
                "  float speed;\n"
                "  kobjref<CAnimationDictionary> heroAnimDict;\n"
                "};\n",
                encoding="utf-8",
            )
            layouts = MODULE.source_layouts(
                root,
                [
                    {
                        "class": "CKHkAsterix",
                        "declaredBy": "CKHkHero",
                        "fields": ["heroAnimDict"],
                    }
                ],
            )
        self.assertEqual(
            layouts["CKHkAsterix"]["fields"][0]["declarationOrdinal"], 1
        )

    def test_config_covers_all_owner_groups(self):
        config = json.loads(
            (
                Path(__file__).parents[1]
                / "tools/task91/class_anchors.v1.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(
            {item["group"] for item in config["owners"]},
            {"hero", "enemy", "scripted", "world", "cinematic"},
        )
        self.assertEqual(len(config["owners"]), len({x["class"] for x in config["owners"]}))


if __name__ == "__main__":
    unittest.main()
