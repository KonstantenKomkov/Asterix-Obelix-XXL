import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an XXL1 CNode transform and hierarchy references', () {
    final payload = BytesBuilder(copy: false);
    for (var index = 0; index < 16; index++) {
      _f32(payload, index.toDouble());
    }
    _u32(payload, _ref(11, 1, 4));
    _u16(payload, 0);
    payload.addByte(0xFF);
    _u32(payload, _ref(11, 3, 6));
    _u32(payload, _ref(11, 8, 7));
    _u32(payload, _ref(10, 2, 12));

    final node = parseXxl1SceneNode(
      payload.takeBytes(),
      classId: 3,
      objectId: 5,
    );

    expect(
      node.transform,
      List<double>.generate(16, (index) => index.toDouble()),
    );
    expect(node.parent.category, 11);
    expect(node.parent.classId, 1);
    expect(node.parent.objectId, 4);
    expect(node.child?.classId, 8);
    expect(node.geometry?.category, 10);
    expect(node.geometry?.classId, 2);
    expect(node.geometry?.objectId, 12);
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
