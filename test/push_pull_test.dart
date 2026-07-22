import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads authored push block node, origin and movement axis', () {
    final bytes = BytesBuilder(copy: false);
    for (final value in [0, 7, 0, _ref(11, 3, 99)]) {
      _u32(bytes, value);
    }
    _u16(bytes, 4);
    for (final vector in const [
      [10.0, 2.0, -4.0],
      [0.0, 0.0, -2.0],
      [1.0, 2.0, 3.0],
      [4.0, 5.0, 6.0],
    ]) {
      for (final value in vector) {
        _f32(bytes, value);
      }
    }
    for (final value in const [-1.5, 6.0, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0]) {
      _f32(bytes, value);
    }
    _u32(bytes, _ref(12, 2, 3));
    _u32(bytes, _ref(12, 4, 5));

    final binding = parseXxl1PushPullBinding(bytes.takeBytes(), objectId: 1);
    expect(binding.node.objectId, 99);
    expect(binding.origin, [10, 2, -4]);
    expect(binding.axis[0], closeTo(0, 0.0001));
    expect(binding.axis[2], closeTo(-1, 0.0001));
    expect(binding.parameters, [-1.5, 6, 0.5, 1, 2, 3, 4, 5]);
    expect(binding.flaggedPath.objectId, 3);
  });
}

int _ref(int category, int classId, int objectId) =>
    category | (classId << 6) | (objectId << 17);

void _u16(BytesBuilder builder, int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}

void _u32(BytesBuilder builder, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}

void _f32(BytesBuilder builder, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}
