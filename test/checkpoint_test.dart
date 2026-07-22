import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads authored checkpoint node and checkpoint parameters', () {
    final bytes = BytesBuilder(copy: false);
    for (final value in [0, 7, 0, _ref(11, 2, 4)]) {
      _u32(bytes, value);
    }
    for (final value in [
      _ref(11, 3, 23),
      _ref(9, 1, 29),
      _ref(9, 4, 33),
      _ref(11, 14, 18),
      _ref(11, 14, 17),
      _ref(11, 14, 16),
      _ref(11, 19, 60),
      _ref(11, 19, 61),
      _ref(4, 75, 0),
    ]) {
      _u32(bytes, value);
    }
    for (final value in [1.0, 0.5, 1.0]) {
      _f32(bytes, value);
    }

    final checkpoint = parseXxl1AsterixCheckpoint(
      bytes.takeBytes(),
      objectId: 0,
    );
    expect(checkpoint.node.objectId, 23);
    expect(checkpoint.references, hasLength(9));
    expect(checkpoint.references.last.classId, 75);
    expect(checkpoint.authoredPosition, [1, 0.5, 1]);
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
