import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';

const _streamTag = 0x80d;
const _streamInfoTag = 0x80e;
const _streamDataTag = 0x80f;
const _xboxAdpcmUuid = <int>[
  0x93,
  0x65,
  0x38,
  0xef,
  0x11,
  0xb6,
  0x2d,
  0x43,
  0x95,
  0x7f,
  0xa7,
  0x1a,
  0xde,
  0x44,
  0x22,
  0x7a,
];

final class RwsSegment {
  const RwsSegment({
    required this.name,
    required this.dataOffset,
    required this.dataSize,
    required this.alignedSize,
    required this.markerCount,
  });

  final String name;
  final int dataOffset;
  final int dataSize;
  final int alignedSize;
  final int markerCount;

  Map<String, Object> toJson() => {
    'name': name,
    'dataOffset': dataOffset,
    'dataSize': dataSize,
    'alignedSize': alignedSize,
    'markerCount': markerCount,
  };
}

final class RwsAudioStream {
  const RwsAudioStream({
    required this.renderWareVersion,
    required this.name,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.streamSectorSize,
    required this.usedSectorSize,
    required this.substreamName,
    required this.codecUuid,
    required this.segments,
    required this.data,
  });

  final int renderWareVersion;
  final String name;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int streamSectorSize;
  final int usedSectorSize;
  final String substreamName;
  final String codecUuid;
  final List<RwsSegment> segments;
  final Uint8List data;

  bool get isXboxAdpcm => codecUuid == _uuidString(_xboxAdpcmUuid);

  Map<String, Object> toJson() => {
    'format': 'renderware-audio-stream',
    'renderWareVersion': '0x${renderWareVersion.toRadixString(16)}',
    'name': name,
    'codec': isXboxAdpcm ? 'xbox-ima-adpcm' : 'unknown',
    'codecUuid': codecUuid,
    'sampleRate': sampleRate,
    'channels': channels,
    'bitsPerSample': bitsPerSample,
    'streamSectorSize': streamSectorSize,
    'usedSectorSize': usedSectorSize,
    'substreamName': substreamName,
    'segments': segments.map((segment) => segment.toJson()).toList(),
    'loopPoints': const <Object>[],
  };

  Uint8List decodeFirstSegmentToWav() {
    if (!isXboxAdpcm || bitsPerSample != 4) {
      throw ImportException(
        code: ImportErrorCode.unsupportedVersion,
        message: 'Only 4-bit Xbox IMA ADPCM RWS streams are supported.',
        details: {'codecUuid': codecUuid, 'bitsPerSample': bitsPerSample},
      );
    }
    if (segments.isEmpty) {
      throw const ImportException(
        code: ImportErrorCode.invalidValue,
        message: 'RWS stream has no segments.',
      );
    }
    final segment = segments.first;
    final blockSize = 36 * channels;
    final pcm = BytesBuilder(copy: false);
    var remaining = segment.dataSize;
    var sectorOffset = segment.dataOffset;
    while (remaining > 0) {
      final used = remaining < usedSectorSize ? remaining : usedSectorSize;
      if (sectorOffset < 0 || sectorOffset + used > data.length) {
        throw ImportException(
          code: ImportErrorCode.truncatedInput,
          message: 'RWS sector data exceeds the data chunk.',
          offset: sectorOffset,
          details: {'used': used, 'dataLength': data.length},
        );
      }
      if (used % blockSize != 0) {
        throw ImportException(
          code: ImportErrorCode.invalidValue,
          message: 'RWS used sector size is not ADPCM-block aligned.',
          offset: sectorOffset,
          details: {'used': used, 'blockSize': blockSize},
        );
      }
      for (var block = 0; block < used; block += blockSize) {
        pcm.add(_decodeXboxAdpcmBlock(data, sectorOffset + block, channels));
      }
      remaining -= used;
      sectorOffset += streamSectorSize;
    }
    return _pcm16Wav(pcm.takeBytes(), channels, sampleRate);
  }
}

RwsAudioStream parseRws(Uint8List bytes, {String? path}) {
  final reader = BinaryReader(bytes, path: path);
  final outer = _readChunk(reader, expectedTag: _streamTag);
  final outerEnd = reader.offset + outer.size;
  final info = _readChunk(reader, expectedTag: _streamInfoTag);
  final infoEnd = reader.offset + info.size;
  if (infoEnd > outerEnd) _invalidChunk(reader, infoEnd, outerEnd);

  reader.readUint32();
  for (var index = 0; index < 4; index++) {
    reader.readUint32();
  }
  reader.readUint32();
  reader.readUint32();
  reader.readUint32();
  final segmentCount = reader.readUint32();
  reader.readUint32();
  final substreamCount = reader.readUint32();
  reader.readUint32();
  reader.readUint32();
  final streamSectorSize = reader.readUint32();
  reader.readUint32();
  reader.readUint32();
  reader.readBytes(16);
  final streamName = _fixedString(reader.readBytes(16));
  if (segmentCount > 100000 || substreamCount != 1) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Unsupported RWS segment or substream count.',
      path: path,
      offset: reader.offset,
      details: {'segments': segmentCount, 'substreams': substreamCount},
    );
  }
  final segmentFields = <List<int>>[];
  for (var index = 0; index < segmentCount; index++) {
    reader.readUint32();
    reader.readUint32();
    reader.readUint32();
    reader.readUint32();
    final markers = reader.readUint32();
    reader.readUint32();
    final alignedSize = reader.readUint32();
    final dataOffset = reader.readUint32();
    segmentFields.add([markers, alignedSize, dataOffset]);
  }
  final sizes = [
    for (var index = 0; index < segmentCount; index++) reader.readUint32(),
  ];
  for (var index = 0; index < segmentCount; index++) {
    reader.readBytes(16);
  }
  final names = [
    for (var index = 0; index < segmentCount; index++)
      _fixedString(reader.readBytes(16)),
  ];
  final segments = [
    for (var index = 0; index < segmentCount; index++)
      RwsSegment(
        name: names[index],
        markerCount: segmentFields[index][0],
        alignedSize: segmentFields[index][1],
        dataOffset: segmentFields[index][2],
        dataSize: sizes[index],
      ),
  ];

  for (var index = 0; index < 4; index++) {
    reader.readUint32();
  }
  reader.readUint32();
  reader.readUint32();
  reader.readUint16();
  reader.readUint16();
  reader.readUint16();
  reader.readUint8();
  reader.readUint8();
  final usedSectorSize = reader.readUint32();
  reader.readUint32();
  final sampleRate = reader.readUint32();
  reader.readUint32();
  reader.readUint32();
  final bitsPerSample = reader.readUint8();
  final channels = reader.readUint8();
  reader.readUint8();
  reader.readUint8();
  reader.readUint32();
  reader.readUint32();
  reader.readBytes(4);
  final codecBytes = reader.readBytes(16);
  reader.readUint32();
  reader.readBytes(16);
  final substreamName = _fixedString(reader.readBytes(16));
  if (reader.offset > infoEnd) _invalidChunk(reader, reader.offset, infoEnd);
  reader.seek(infoEnd);
  final audio = _readChunk(reader, expectedTag: _streamDataTag);
  if (reader.offset + audio.size > outerEnd) {
    _invalidChunk(reader, reader.offset + audio.size, outerEnd);
  }
  final data = reader.readBytes(audio.size);
  if (streamSectorSize <= 0 ||
      usedSectorSize <= 0 ||
      channels < 1 ||
      channels > 2 ||
      sampleRate <= 0) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'RWS audio parameters are invalid.',
      path: path,
      details: {
        'sectorSize': streamSectorSize,
        'usedSectorSize': usedSectorSize,
        'channels': channels,
        'sampleRate': sampleRate,
      },
    );
  }
  return RwsAudioStream(
    renderWareVersion: outer.version,
    name: streamName,
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
    streamSectorSize: streamSectorSize,
    usedSectorSize: usedSectorSize,
    substreamName: substreamName,
    codecUuid: _uuidString(codecBytes),
    segments: segments,
    data: data,
  );
}

({int size, int version}) _readChunk(
  BinaryReader reader, {
  required int expectedTag,
}) {
  final start = reader.offset;
  final tag = reader.readUint32();
  final size = reader.readUint32();
  final version = reader.readUint32();
  if (tag != expectedTag) {
    throw ImportException(
      code: ImportErrorCode.invalidMagic,
      message: 'Unexpected RenderWare chunk tag.',
      path: reader.path,
      offset: start,
      details: {'expected': expectedTag, 'actual': tag},
    );
  }
  if (reader.offset + size > reader.length) {
    _invalidChunk(reader, reader.offset + size, reader.length);
  }
  return (size: size, version: version);
}

Never _invalidChunk(BinaryReader reader, int end, int limit) {
  throw ImportException(
    code: ImportErrorCode.truncatedInput,
    message: 'RenderWare chunk exceeds its container.',
    path: reader.path,
    offset: reader.offset,
    details: {'chunkEnd': end, 'containerEnd': limit},
  );
}

String _fixedString(Uint8List bytes) {
  final end = bytes.indexOf(0);
  return String.fromCharCodes(bytes.sublist(0, end < 0 ? bytes.length : end));
}

String _uuidString(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

const _stepTable = <int>[
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  16,
  17,
  19,
  21,
  23,
  25,
  28,
  31,
  34,
  37,
  41,
  45,
  50,
  55,
  60,
  66,
  73,
  80,
  88,
  97,
  107,
  118,
  130,
  143,
  157,
  173,
  190,
  209,
  230,
  253,
  279,
  307,
  337,
  371,
  408,
  449,
  494,
  544,
  598,
  658,
  724,
  796,
  876,
  963,
  1060,
  1166,
  1282,
  1411,
  1552,
  1707,
  1878,
  2066,
  2272,
  2499,
  2749,
  3024,
  3327,
  3660,
  4026,
  4428,
  4871,
  5358,
  5894,
  6484,
  7132,
  7845,
  8630,
  9493,
  10442,
  11487,
  12635,
  13899,
  15289,
  16818,
  18500,
  20350,
  22385,
  24623,
  27086,
  29794,
  32767,
];
const _indexTable = <int>[-1, -1, -1, -1, 2, 4, 6, 8];

Uint8List _decodeXboxAdpcmBlock(Uint8List input, int offset, int channels) {
  final output = ByteData(64 * channels * 2);
  final predictors = List<int>.filled(channels, 0);
  final indexes = List<int>.filled(channels, 0);
  var cursor = offset;
  for (var channel = 0; channel < channels; channel++) {
    predictors[channel] = ByteData.sublistView(
      input,
      cursor,
      cursor + 2,
    ).getInt16(0, Endian.little);
    indexes[channel] = input[cursor + 2];
    if (indexes[channel] > 88 || input[cursor + 3] != 0) {
      throw ImportException(
        code: ImportErrorCode.invalidValue,
        message: 'Invalid Xbox ADPCM block header.',
        offset: cursor,
      );
    }
    output.setInt16(channel * 2, predictors[channel], Endian.little);
    cursor += 4;
  }
  for (var chunk = 0; chunk < 8; chunk++) {
    for (var channel = 0; channel < channels; channel++) {
      for (var byteIndex = 0; byteIndex < 4; byteIndex++) {
        final packed = input[cursor++];
        for (var half = 0; half < 2; half++) {
          final nibble = half == 0 ? packed & 15 : packed >> 4;
          final step = _stepTable[indexes[channel]];
          var delta = step >> 3;
          if (nibble & 1 != 0) delta += step >> 2;
          if (nibble & 2 != 0) delta += step >> 1;
          if (nibble & 4 != 0) delta += step;
          predictors[channel] += nibble & 8 != 0 ? -delta : delta;
          predictors[channel] = predictors[channel].clamp(-32768, 32767);
          indexes[channel] = (indexes[channel] + _indexTable[nibble & 7]).clamp(
            0,
            88,
          );
          final frame = 1 + chunk * 8 + byteIndex * 2 + half;
          if (frame < 64) {
            output.setInt16(
              (frame * channels + channel) * 2,
              predictors[channel],
              Endian.little,
            );
          }
        }
      }
    }
  }
  return output.buffer.asUint8List();
}

Uint8List _pcm16Wav(Uint8List pcm, int channels, int sampleRate) {
  final wav = ByteData(44 + pcm.length);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      wav.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  wav.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  wav.setUint32(16, 16, Endian.little);
  wav.setUint16(20, 1, Endian.little);
  wav.setUint16(22, channels, Endian.little);
  wav.setUint32(24, sampleRate, Endian.little);
  wav.setUint32(28, sampleRate * channels * 2, Endian.little);
  wav.setUint16(32, channels * 2, Endian.little);
  wav.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  wav.setUint32(40, pcm.length, Endian.little);
  wav.buffer.asUint8List().setRange(44, 44 + pcm.length, pcm);
  return wav.buffer.asUint8List();
}
