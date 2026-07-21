import 'dart:convert';
import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes an indexed texture and preserves palette alpha', () {
    final texture = parseXxl1TextureDictionaryPayload(
      _indexedTextureDictionary(),
    ).single;

    expect(texture.name, 'fixture');
    expect(texture.width, 2);
    expect(texture.height, 1);
    expect(texture.bitsPerPixel, 4);
    expect(texture.paletteEntries, 16);
    expect(texture.rgba, [255, 0, 0, 255, 0, 255, 0, 64]);

    final png = encodeRgbaPng(texture);
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(ascii.decode(png.sublist(12, 16)), 'IHDR');
  });

  test('rejects a truncated palette', () {
    final bytes = _indexedTextureDictionary();
    expect(
      () => parseXxl1TextureDictionaryPayload(
        Uint8List.sublistView(bytes, 0, bytes.length - 1),
        path: 'truncated.fixture',
      ),
      throwsA(
        isA<ImportException>().having(
          (error) => error.code,
          'code',
          anyOf(ImportErrorCode.truncatedInput, ImportErrorCode.invalidValue),
        ),
      ),
    );
  });
}

Uint8List _indexedTextureDictionary() {
  final imageStruct = BytesBuilder(copy: false);
  for (final value in [2, 1, 4, 2]) {
    _u32(imageStruct, value);
  }
  final palette = Uint8List(16 * 4);
  palette.setRange(0, 4, [255, 0, 0, 255]);
  palette.setRange(4, 8, [0, 255, 0, 64]);
  final image = _chunk(0x18, [
    _chunk(1, [imageStruct.takeBytes()]),
    Uint8List.fromList([0, 1]),
    palette,
  ]);

  final dictionary = BytesBuilder(copy: false);
  _u32(dictionary, 1);
  final name = Uint8List(32)..setRange(0, 7, ascii.encode('fixture'));
  dictionary.add(name);
  _u32(dictionary, 2);
  _u32(dictionary, 1);
  _u32(dictionary, 1);
  dictionary.add(image);
  return dictionary.takeBytes();
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

void _u32(BytesBuilder builder, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}
