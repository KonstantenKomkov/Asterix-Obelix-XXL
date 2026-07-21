import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an XXL1 ground collision mesh', () {
    final mesh = parseXxl1CollisionMesh(_ground(), objectId: 7, classId: 18);

    expect(mesh.kind, CollisionMeshKind.ground);
    expect(mesh.vertices, hasLength(3));
    expect(mesh.triangles.single, [0, 1, 2]);
    expect(mesh.highCorner, [1, 1, 1]);
    expect(mesh.lowCorner, [0, 0, 0]);
  });

  test('rejects a collision index outside the vertex array', () {
    expect(
      () => parseXxl1CollisionMesh(
        _ground(lastIndex: 3),
        objectId: 7,
        classId: 18,
      ),
      throwsA(isA<ImportException>()),
    );
  });
}

Uint8List _ground({int lastIndex = 2}) {
  final bytes = BytesBuilder(copy: false);
  _u32(bytes, 44);
  _u16(bytes, 1);
  _u16(bytes, 3);
  for (final index in [0, 1, lastIndex]) {
    _u16(bytes, index);
  }
  for (final value in [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]) {
    _f32(bytes, value);
  }
  for (final value in [1.0, 1.0, 1.0, 0.0, 0.0, 0.0]) {
    _f32(bytes, value);
  }
  _u16(bytes, 0);
  _u16(bytes, 1);
  _u16(bytes, 0);
  _u16(bytes, 0);
  _f32(bytes, 0);
  _f32(bytes, 0);
  return bytes.takeBytes();
}

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
