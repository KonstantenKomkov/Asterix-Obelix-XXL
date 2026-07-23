import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "task91_corpus", Path(__file__).parents[1] / "scripts" / "task91_corpus.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def synthetic_pe() -> bytes:
    data = bytearray(0x400)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", data, 0x84, 0x14C, 1, 1234, 0, 0, 0xE0, 0x102)
    optional = 0x98
    struct.pack_into("<H", data, optional, 0x10B)
    struct.pack_into("<I", data, optional + 28, 0x400000)
    struct.pack_into("<I", data, optional + 92, 16)
    section = optional + 0xE0
    data[section:section + 8] = b".rdata\0\0"
    struct.pack_into("<IIII", data, section + 8, 0x200, 0x1000, 0x200, 0x200)
    struct.pack_into("<I", data, section + 36, 0x40000040)
    data[0x240:0x24F] = b".?AVTestClass@@\0"
    return bytes(data)


class Task91CorpusTest(unittest.TestCase):
    def test_extracts_pe_identity_and_rtti_without_debug(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.exe"
            path.write_bytes(synthetic_pe())
            report = MODULE.inspect_pe(path)
        self.assertEqual(report["format"], "PE32")
        self.assertEqual(report["machine"], "x86")
        self.assertEqual(report["imageBase"], "0x00400000")
        self.assertEqual(report["coffTimestamp"], 1234)
        self.assertTrue(report["rtti"]["present"])
        self.assertFalse(report["debug"]["directoryPresent"])

    def test_rejects_non_pe_input(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.exe"
            path.write_bytes(b"not a PE")
            with self.assertRaisesRegex(ValueError, "MZ"):
                MODULE.inspect_pe(path)


if __name__ == "__main__":
    unittest.main()
