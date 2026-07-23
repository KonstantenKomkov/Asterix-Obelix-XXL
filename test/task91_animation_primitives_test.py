import importlib.util
import struct
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "task91_animation_primitives", ROOT / "scripts/task91_animation_primitives.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeImage:
    image_base = 0x400000
    sections = [{"raw": 0, "raw_size": 32, "rva": 0x1000, "flags": 0x20000000}]

    def __init__(self):
        self.data = bytearray(32)
        self.data[0] = 0xE8
        struct.pack_into("<i", self.data, 1, 0x1010 - 0x1005)
        self.data[16] = 0xC3

    def rva_from_offset(self, offset):
        return 0x1000 + offset

    def is_code_va(self, value):
        return 0x401000 <= value < 0x401020


class AnimationPrimitiveTest(unittest.TestCase):
    def test_direct_calls_only_returns_in_image_targets(self):
        self.assertEqual(MODULE.direct_calls(FakeImage()), [(0x1000, 0x1010)])

    def test_shortest_path_is_deterministic(self):
        graph = {1: {3, 2}, 2: {4}, 3: {5}}
        self.assertEqual(MODULE.shortest_path(graph, [1], {4, 5}), [1, 2, 4])
        self.assertIsNone(MODULE.shortest_path(graph, [7], {4}))


if __name__ == "__main__":
    unittest.main()
