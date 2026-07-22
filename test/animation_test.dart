import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses and samples an uncompressed skeletal animation', () {
    final animation = parseRwAnimation(_animation());

    expect(animation.nodeCount, 1);
    expect(animation.duration, 1);
    expect(animation.frames, hasLength(2));
    final matrix = animation.sample(0.5).single;
    expect(matrix[12], closeTo(1, 0.0001));
    expect(matrix[13], closeTo(2, 0.0001));
    expect(matrix[14], closeTo(3, 0.0001));
  });

  test('rejects an unsupported animation scheme', () {
    final bytes = _animation(scheme: 99);
    expect(
      () => parseRwAnimation(bytes, path: 'invalid.animation'),
      throwsA(
        isA<ImportException>().having(
          (error) => error.code,
          'code',
          ImportErrorCode.invalidValue,
        ),
      ),
    );
  });

  test('extracts animation dictionaries and normalizes empty slots', () {
    final bytes = BytesBuilder(copy: false)
      ..add(_u32Bytes(3))
      ..add(_u32Bytes(2))
      ..add(_u32Bytes(0xFFFFFFFF))
      ..add(_u32Bytes(0));
    final data = bytes.takeBytes();
    final dictionaries = extractXxl1AnimationDictionaries(
      data,
      Xxl1LevelScan(
        levelNumber: 1,
        sectorCount: 5,
        headerOffset: 0,
        payloadOffset: 0,
        objects: [
          KwnObjectSlice(
            category: 9,
            classId: 1,
            objectIndex: 7,
            objectId: 7,
            payloadOffset: 0,
            endOffset: data.length,
          ),
        ],
      ),
      animationCount: 3,
    );

    expect(dictionaries, hasLength(1));
    expect(dictionaries.single.objectId, 7);
    expect(dictionaries.single.animationIndices, [2, null, 0]);
  });

  test('rejects an out-of-range animation dictionary index', () {
    final data = Uint8List.fromList([..._u32Bytes(1), ..._u32Bytes(3)]);
    final scan = Xxl1LevelScan(
      levelNumber: 1,
      sectorCount: 5,
      headerOffset: 0,
      payloadOffset: 0,
      objects: [
        KwnObjectSlice(
          category: 9,
          classId: 1,
          objectIndex: 0,
          objectId: 0,
          payloadOffset: 0,
          endOffset: data.length,
        ),
      ],
    );
    expect(
      () => extractXxl1AnimationDictionaries(data, scan, animationCount: 3),
      throwsA(isA<ImportException>()),
    );
  });

  test('rejects an animation dictionary slot count beyond its payload', () {
    final data = Uint8List.fromList(_u32Bytes(0xFFFFFFFF));
    final scan = Xxl1LevelScan(
      levelNumber: 1,
      sectorCount: 5,
      headerOffset: 0,
      payloadOffset: 0,
      objects: [
        KwnObjectSlice(
          category: 9,
          classId: 1,
          objectIndex: 0,
          objectId: 0,
          payloadOffset: 0,
          endOffset: data.length,
        ),
      ],
    );

    expect(
      () => extractXxl1AnimationDictionaries(data, scan),
      throwsA(isA<ImportException>()),
    );
  });

  test('finds serialized animation dictionary object references', () {
    const encodedDictionaryOne = 9 | (1 << 6) | (1 << 17);
    final bytes = BytesBuilder(copy: false)
      ..add([0xAA])
      ..add(_u32Bytes(encodedDictionaryOne))
      ..add([0xBB]);
    final data = bytes.takeBytes();
    final scan = Xxl1LevelScan(
      levelNumber: 1,
      sectorCount: 5,
      headerOffset: 0,
      payloadOffset: 0,
      objects: [
        const KwnObjectSlice(
          category: 9,
          classId: 1,
          objectIndex: 0,
          objectId: 0,
          payloadOffset: 0,
          endOffset: 0,
        ),
        const KwnObjectSlice(
          category: 9,
          classId: 1,
          objectIndex: 1,
          objectId: 1,
          payloadOffset: 0,
          endOffset: 0,
        ),
        KwnObjectSlice(
          category: 2,
          classId: 28,
          objectIndex: 0,
          objectId: 0,
          payloadOffset: 0,
          endOffset: data.length,
        ),
      ],
    );

    final references = findXxl1AnimationDictionaryReferences(data, scan);

    expect(references, hasLength(1));
    expect(references.single.dictionaryObjectId, 1);
    expect(references.single.sourceCategory, 2);
    expect(references.single.sourceClassId, 28);
    expect(references.single.payloadByteOffset, 1);
  });

  test('keeps only references from declared dictionary owner classes', () {
    const encodedDictionaryZero = 9 | (1 << 6);
    final bytes = Uint8List.fromList([
      ..._u32Bytes(encodedDictionaryZero),
      ..._u32Bytes(encodedDictionaryZero),
    ]);
    final scan = Xxl1LevelScan(
      levelNumber: 1,
      sectorCount: 5,
      headerOffset: 0,
      payloadOffset: 0,
      objects: [
        const KwnObjectSlice(
          category: 9,
          classId: 1,
          objectIndex: 0,
          objectId: 0,
          payloadOffset: 0,
          endOffset: 0,
        ),
        const KwnObjectSlice(
          category: 2,
          classId: 28,
          objectIndex: 0,
          objectId: 0,
          payloadOffset: 0,
          endOffset: 4,
        ),
        const KwnObjectSlice(
          category: 10,
          classId: 2,
          objectIndex: 0,
          objectId: 0,
          payloadOffset: 4,
          endOffset: 8,
        ),
      ],
    );

    final owners = findXxl1AnimationDictionaryOwnerReferences(bytes, scan);

    expect(owners, hasLength(1));
    expect(owners.single.ownerClass, 'CKHkAsterix');
    expect(owners.single.field, 'heroAnimDict');
    expect(owners.single.referenceKind, 'typed-field');
  });
}

Uint8List _animation({int scheme = 1}) {
  final body = BytesBuilder(copy: false);
  _u32(body, 0x100);
  _u32(body, scheme);
  _u32(body, 2);
  _u32(body, 0);
  _f32(body, 1);
  for (final frame in [
    (time: 0.0, translation: [0.0, 0.0, 0.0], previous: 0),
    (time: 1.0, translation: [2.0, 4.0, 6.0], previous: 0),
  ]) {
    _f32(body, frame.time);
    for (final value in [0.0, 0.0, 0.0, 1.0]) {
      _f32(body, value);
    }
    for (final value in frame.translation) {
      _f32(body, value);
    }
    _u32(body, frame.previous);
  }
  final payload = body.takeBytes();
  final chunk = BytesBuilder(copy: false);
  _u32(chunk, 0x1B);
  _u32(chunk, payload.length);
  _u32(chunk, 0x1803FFFF);
  chunk.add(payload);
  return chunk.takeBytes();
}

void _u32(BytesBuilder builder, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}

Uint8List _u32Bytes(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

void _f32(BytesBuilder builder, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}
