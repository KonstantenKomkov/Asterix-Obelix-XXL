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

  test('preserves particle FX playback parameters and attachment', () {
    final payload = BytesBuilder(copy: false);
    for (var index = 0; index < 16; index++) {
      _f32(
        payload,
        index == 12
            ? 4.5
            : index == 15
            ? 1
            : 0,
      );
    }
    _u32(payload, _ref(11, 2, 1));
    _u16(payload, 0);
    payload.addByte(0xFF);
    _u32(payload, 0xFFFFFFFF);
    _u32(payload, 0xFFFFFFFF);
    _u32(payload, _ref(10, 1, 151));
    payload.add([2, 1]);
    _f32(payload, 1.25);
    _u32(payload, 0xDEADC0DE);

    final node = parseXxl1SceneNode(
      payload.takeBytes(),
      classId: 19,
      objectId: 136,
    );

    expect(node.transform[12], 4.5);
    expect(node.geometry?.objectId, 151);
    expect(node.particle?.enabled, 2);
    expect(node.particle?.mode, 1);
    expect(node.particle?.rate, 1.25);
    expect(node.particle?.seed, 0xDEADC0DE);
    expect(node.sourcePayload.byteLength, 93);
    expect(node.sourcePayload.consumedByteLength, 93);
    expect(node.sourcePayload.trailingByteLength, 0);
    expect(node.sourcePayload.hex, hasLength(186));
    expect(node.sourcePayload.sha256, hasLength(64));
  });

  test('decodes and consumes the complete XXL1 fog-volume payload', () {
    final payload = BytesBuilder(copy: false);
    for (var index = 0; index < 16; index++) {
      _f32(payload, index == 15 ? 1 : 0);
    }
    _u32(payload, 0xFFFFFFFF);
    _u16(payload, 0);
    payload.addByte(0xFF);
    _u32(payload, 0xFFFFFFFF);
    _u32(payload, 0xFFFFFFFF);
    _u32(payload, _ref(10, 2, 42));
    _u32(payload, 7); // flags
    _u32(payload, 1); // matrices
    for (var index = 0; index < 16; index++) {
      _f32(payload, index % 5 == 0 ? 1 : 0);
    }
    _u16(payload, 3);
    payload.add('fog'.codeUnits);
    payload.add([1, 2, 3, 4, 5]);
    _u32(payload, 6);
    _u32(payload, 2);
    _u32(payload, 8);
    for (final value in [1.0, 2.0, 3.0, 0.5]) {
      _f32(payload, value);
    }
    _u32(payload, 1);
    _f32(payload, 0.25);
    _f32(payload, 0.75);
    payload.add([9, 10]);
    _u32(payload, 11);
    _u32(payload, 1);
    _f32(payload, 0.0);
    _f32(payload, 0.6);
    _u32(payload, 0xFF112233);
    _u32(payload, 0xFF445566);
    // type 1: two arrays sized by fogUnk09 (2).
    for (var index = 0; index < 4; index++) {
      _f32(payload, index / 10);
    }
    for (var index = 0; index < 2 + 4 + 3 + 2 + 1; index++) {
      _f32(payload, index.toDouble());
    }

    final node = parseXxl1SceneNode(
      payload.takeBytes(),
      classId: 26,
      objectId: 7,
    );

    expect(
      node.sourcePayload.consumedByteLength,
      node.sourcePayload.byteLength,
    );
    expect(node.sourcePayload.trailingByteLength, 0);
    expect(node.fog?.effectName, 'fog');
    expect(node.fog?.matrices, hasLength(1));
    expect(node.fog?.coordinates.single, [0.25, 0.75]);
    expect(node.fog?.colorStops.single.innerColor, 0xFF112233);
    expect(node.fog?.profile, hasLength(16));
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
