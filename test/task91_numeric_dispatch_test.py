import importlib.util
import struct
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task91_numeric_dispatch", ROOT / "scripts/task91_numeric_dispatch.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeImage:
    image_base = 0x400000

    def __init__(self):
        self.data = bytearray(64)
        self.data[0:7] = b"\xff\x24\x85" + struct.pack("<I", 0x400020)
        struct.pack_into("<II", self.data, 32, 0x400030, 0x400034)

    def offset_from_rva(self, rva):
        return rva

    def is_code_va(self, value):
        return 0x400030 <= value < 0x400040


class NumericDispatchTest(unittest.TestCase):
    def test_validates_and_reads_indexed_jump_table(self):
        image = FakeImage()
        MODULE.validate_jump(image, 0, 0x20)
        self.assertEqual(MODULE.read_table(image, 0x20, 2), [0x30, 0x34])

    def test_rejects_non_code_table_target(self):
        image = FakeImage()
        struct.pack_into("<I", image.data, 36, 0x500000)
        with self.assertRaisesRegex(ValueError, "non-code target"):
            MODULE.read_table(image, 0x20, 2)


if __name__ == "__main__":
    unittest.main()
