import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts vertices, indices, UV and frame hierarchy', () {
    final mesh = parseXxl1StaticGeometry(_staticGeometryPayload());

    expect(mesh.frames, hasLength(1));
    expect(mesh.frames.single.parentIndex, -1);
    expect(mesh.frames.single.matrix, hasLength(12));
    expect(mesh.vertices, [
      [0.0, 0.0, 0.0],
      [1.0, 0.0, 0.0],
      [0.0, 1.0, 0.0],
    ]);
    expect(mesh.uvSets.single, [
      [0.0, 0.0],
      [1.0, 0.0],
      [0.0, 1.0],
    ]);
    expect(mesh.triangles.single.a, 0);
    expect(mesh.triangles.single.b, 1);
    expect(mesh.triangles.single.c, 2);
    expect(mesh.materials, hasLength(1));
    expect(mesh.materials.single.textureName, 'fixture_tex');
    expect(mesh.materials.single.color, 0x80402010);
    expect(mesh.materials.single.usesMipmaps, isTrue);
    expect(mesh.materialSlots, [0, 0]);
    expect(mesh.triangles.single.material, 0);
  });

  test('resolves reused RenderWare material slots for triangles', () {
    final mesh = parseXxl1StaticGeometry(
      _staticGeometryPayload(triangleMaterial: 1),
    );

    expect(mesh.materials, hasLength(1));
    expect(mesh.materialSlots, [0, 0]);
    expect(mesh.triangles.single.material, 0);
  });

  test('rejects triangle indices outside the vertex array', () {
    expect(
      () => parseXxl1StaticGeometry(_staticGeometryPayload(lastIndex: 3)),
      throwsA(
        isA<ImportException>().having(
          (error) => error.code,
          'code',
          ImportErrorCode.invalidValue,
        ),
      ),
    );
  });
}

Uint8List _staticGeometryPayload({
  int lastIndex = 2,
  int triangleMaterial = 0,
}) {
  final frameStruct = BytesBuilder(copy: false);
  _u32(frameStruct, 1);
  for (final value in <double>[1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]) {
    _f32(frameStruct, value);
  }
  _i32(frameStruct, -1);
  _u32(frameStruct, 0);
  final frameList = _chunk(0xE, [
    _chunk(1, [frameStruct.takeBytes()]),
    _chunk(3, const []),
  ]);

  final geometryStruct = BytesBuilder(copy: false);
  _u32(geometryStruct, 0x06); // positions + one UV set
  _u32(geometryStruct, 1);
  _u32(geometryStruct, 3);
  _u32(geometryStruct, 1);
  for (final value in <double>[0, 0, 1, 0, 0, 1]) {
    _f32(geometryStruct, value);
  }
  _u16(geometryStruct, 0);
  _u16(geometryStruct, 1);
  _u16(geometryStruct, triangleMaterial);
  _u16(geometryStruct, lastIndex);
  for (final value in <double>[0, 0, 0, 1]) {
    _f32(geometryStruct, value);
  }
  _u32(geometryStruct, 1);
  _u32(geometryStruct, 0);
  for (final value in <double>[0, 0, 0, 1, 0, 0, 0, 1, 0]) {
    _f32(geometryStruct, value);
  }
  final materialStruct = BytesBuilder(copy: false);
  _u32(materialStruct, 0);
  _u32(materialStruct, 0x80402010);
  _u32(materialStruct, 0);
  _u32(materialStruct, 1);
  _f32(materialStruct, 1);
  _f32(materialStruct, 0);
  _f32(materialStruct, 1);
  final textureStruct = BytesBuilder(copy: false)
    ..addByte(2)
    ..addByte(0x11);
  _u16(textureStruct, 1);
  final texture = _chunk(6, [
    _chunk(1, [textureStruct.takeBytes()]),
    _rwString('fixture_tex'),
    _rwString(''),
    _chunk(3, const []),
  ]);
  final material = _chunk(7, [
    _chunk(1, [materialStruct.takeBytes()]),
    texture,
    _chunk(3, const []),
  ]);
  final materialSlots = BytesBuilder(copy: false);
  _u32(materialSlots, 2);
  _u32(materialSlots, 0xFFFFFFFF);
  _u32(materialSlots, 0);

  final geometry = _chunk(0xF, [
    _chunk(1, [geometryStruct.takeBytes()]),
    _chunk(8, [
      _chunk(1, [materialSlots.takeBytes()]),
      material,
    ]),
    _chunk(3, const []),
  ]);

  final atomicStruct = BytesBuilder(copy: false);
  for (final value in [0, 0, 5, 0]) {
    _u32(atomicStruct, value);
  }
  final atomic = _chunk(0x14, [
    _chunk(1, [atomicStruct.takeBytes()]),
    geometry,
    _chunk(3, const []),
  ]);

  final payload = BytesBuilder(copy: false);
  _u32(payload, 0xFFFFFFFF);
  _u32(payload, 1);
  payload.add(frameList);
  payload.add(atomic);
  _u32(payload, 0); // same geometry reference
  _u32(payload, 6);
  return payload.takeBytes();
}

Uint8List _rwString(String value) {
  final bytes = [...value.codeUnits, 0];
  while (bytes.length % 4 != 0) {
    bytes.add(0);
  }
  return _chunk(2, [Uint8List.fromList(bytes)]);
}

Uint8List _chunk(int type, List<Uint8List> parts) {
  final body = BytesBuilder(copy: false);
  for (final part in parts) {
    body.add(part);
  }
  final bytes = body.takeBytes();
  final chunk = BytesBuilder(copy: false);
  _u32(chunk, type);
  _u32(chunk, bytes.length);
  _u32(chunk, 0x1803FFFF);
  chunk.add(bytes);
  return chunk.takeBytes();
}

void _u16(BytesBuilder builder, int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}

void _u32(BytesBuilder builder, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}

void _i32(BytesBuilder builder, int value) {
  final data = ByteData(4)..setInt32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}

void _f32(BytesBuilder builder, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}
