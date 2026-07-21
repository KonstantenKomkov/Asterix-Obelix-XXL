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

void _f32(BytesBuilder builder, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}
