import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';
import 'kwn_structure.dart';

final class DecodedTexture {
  const DecodedTexture({
    required this.name,
    required this.width,
    required this.height,
    required this.bitsPerPixel,
    required this.pitch,
    required this.filtering,
    required this.uAddressing,
    required this.vAddressing,
    required this.rgba,
    required this.paletteEntries,
  });

  final String name;
  final int width;
  final int height;
  final int bitsPerPixel;
  final int pitch;
  final int filtering;
  final int uAddressing;
  final int vAddressing;
  final Uint8List rgba;
  final int paletteEntries;

  Map<String, Object> summary() => {
    'name': name,
    'width': width,
    'height': height,
    'bitsPerPixel': bitsPerPixel,
    'pitch': pitch,
    'filtering': filtering,
    'uAddressing': uAddressing,
    'vAddressing': vAddressing,
    'paletteEntries': paletteEntries,
  };
}

List<DecodedTexture> extractXxl1SectorTextures(
  Uint8List bytes, {
  required String path,
}) {
  final dictionaries = scanXxl1SectorObjects(
    bytes,
    path: path,
  ).where((object) => object.category == 9 && object.classId == 2).toList();
  if (dictionaries.length != 1) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Expected exactly one sector texture dictionary.',
      path: path,
      details: {'actual': dictionaries.length},
    );
  }
  final object = dictionaries.single;
  return parseXxl1TextureDictionaryPayload(
    Uint8List.sublistView(bytes, object.payloadOffset, object.endOffset),
    path: '$path#9:2:${object.objectId}',
  );
}

List<DecodedTexture> parseXxl1TextureDictionaryPayload(
  Uint8List payload, {
  String? path,
}) {
  final reader = BinaryReader(payload, path: path);
  final textureCount = reader.readUint32();
  final textures = <DecodedTexture>[];
  for (var index = 0; index < textureCount; index++) {
    final nameBytes = reader.readBytes(32);
    final zero = nameBytes.indexOf(0);
    final name = latin1.decode(
      zero < 0 ? nameBytes : nameBytes.sublist(0, zero),
    );
    final filtering = reader.readUint32();
    final uAddressing = reader.readUint32();
    final vAddressing = reader.readUint32();
    final imageChunk = _expectChunk(reader, 0x18);
    final structure = _expectChunk(reader, 1);
    final width = reader.readUint32();
    final height = reader.readUint32();
    final bpp = reader.readUint32();
    final pitch = reader.readUint32();
    _requireAt(reader, structure.end, 'image struct');
    final pixels = reader.readBytes(pitch * height);
    final paletteEntries = bpp <= 8 ? 1 << bpp : 0;
    final palette = paletteEntries == 0
        ? Uint8List(0)
        : reader.readBytes(paletteEntries * 4);
    _requireAt(reader, imageChunk.end, 'image');
    textures.add(
      DecodedTexture(
        name: name,
        width: width,
        height: height,
        bitsPerPixel: bpp,
        pitch: pitch,
        filtering: filtering,
        uAddressing: uAddressing,
        vAddressing: vAddressing,
        rgba: _decodeRgba(
          reader,
          width: width,
          height: height,
          bpp: bpp,
          pitch: pitch,
          pixels: pixels,
          palette: palette,
        ),
        paletteEntries: paletteEntries,
      ),
    );
  }
  _requireAt(reader, reader.length, 'texture dictionary');
  return textures;
}

Uint8List encodeRgbaPng(DecodedTexture texture) {
  final scanlines = BytesBuilder(copy: false);
  for (var y = 0; y < texture.height; y++) {
    scanlines.addByte(0);
    final start = y * texture.width * 4;
    scanlines.add(texture.rgba.sublist(start, start + texture.width * 4));
  }
  final output = BytesBuilder(copy: false)
    ..add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  final ihdr = BytesBuilder(copy: false)
    ..add(_bigEndian32(texture.width))
    ..add(_bigEndian32(texture.height))
    ..add(const [8, 6, 0, 0, 0]);
  _addPngChunk(output, 'IHDR', ihdr.takeBytes());
  _addPngChunk(
    output,
    'IDAT',
    Uint8List.fromList(ZLibEncoder().convert(scanlines.takeBytes())),
  );
  _addPngChunk(output, 'IEND', Uint8List(0));
  return output.takeBytes();
}

Uint8List _decodeRgba(
  BinaryReader reader, {
  required int width,
  required int height,
  required int bpp,
  required int pitch,
  required Uint8List pixels,
  required Uint8List palette,
}) {
  final rgba = Uint8List(width * height * 4);
  if (bpp == 32) {
    if (pitch < width * 4) _unsupportedImage(reader, bpp, pitch);
    for (var y = 0; y < height; y++) {
      rgba.setRange(y * width * 4, (y + 1) * width * 4, pixels, y * pitch);
    }
    return rgba;
  }
  if (bpp <= 8) {
    if (pitch < width) _unsupportedImage(reader, bpp, pitch);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final paletteIndex = pixels[y * pitch + x];
        if (paletteIndex >= 1 << bpp) {
          throw ImportException(
            code: ImportErrorCode.invalidValue,
            message: 'Palette index is outside the palette.',
            path: reader.path,
            offset: reader.offset,
            details: {'index': paletteIndex, 'bitsPerPixel': bpp},
          );
        }
        rgba.setRange(
          (y * width + x) * 4,
          (y * width + x + 1) * 4,
          palette,
          paletteIndex * 4,
        );
      }
    }
    return rgba;
  }
  _unsupportedImage(reader, bpp, pitch);
}

Never _unsupportedImage(BinaryReader reader, int bpp, int pitch) {
  throw ImportException(
    code: ImportErrorCode.unsupportedVersion,
    message: 'Unsupported XXL1 PC image layout.',
    path: reader.path,
    offset: reader.offset,
    details: {'bitsPerPixel': bpp, 'pitch': pitch},
  );
}

_ImageChunk _expectChunk(BinaryReader reader, int expectedType) {
  final type = reader.readUint32();
  final length = reader.readUint32();
  reader.readUint32(); // RenderWare version
  final end = reader.offset + length;
  if (type != expectedType || end < reader.offset || end > reader.length) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Invalid RenderWare image chunk.',
      path: reader.path,
      offset: reader.offset,
      details: {'expectedType': expectedType, 'actualType': type, 'end': end},
    );
  }
  return _ImageChunk(end);
}

void _requireAt(BinaryReader reader, int expected, String kind) {
  if (reader.offset != expected) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Parsed $kind length does not match its boundary.',
      path: reader.path,
      offset: reader.offset,
      details: {'expected': expected, 'actual': reader.offset},
    );
  }
}

void _addPngChunk(BytesBuilder output, String name, Uint8List data) {
  final type = ascii.encode(name);
  output.add(_bigEndian32(data.length));
  output.add(type);
  output.add(data);
  output.add(_bigEndian32(_crc32([...type, ...data])));
}

Uint8List _bigEndian32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final class _ImageChunk {
  const _ImageChunk(this.end);

  final int end;
}
