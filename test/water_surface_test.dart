import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads water surface branch and authored UV multipliers', () {
    final bytes = BytesBuilder(copy: false);
    for (final value in [
      _ref(2, 185, 1),
      1,
      _ref(3, 125, 0),
      _ref(11, 9, 107),
      _ref(11, 9, 108),
    ]) {
      _u32(bytes, value);
    }
    _f32(bytes, 0.3);
    _f32(bytes, 0.6);

    final binding = parseXxl1WaterSurfaceBinding(
      bytes.takeBytes(),
      objectId: 0,
    );
    expect(binding.node.objectId, 107);
    expect(binding.surfaceBranch.classId, 9);
    expect(binding.surfaceBranch.objectId, 108);
    expect(binding.uMultiplier, closeTo(0.3, 0.000001));
    expect(binding.vMultiplier, closeTo(0.6, 0.000001));
  });
}

int _ref(int category, int classId, int objectId) =>
    category | (classId << 6) | (objectId << 17);

void _u32(BytesBuilder builder, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}

void _f32(BytesBuilder builder, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}
