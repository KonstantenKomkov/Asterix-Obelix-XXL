import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses and decodes a synthetic mono Xbox ADPCM stream', () {
    final stream = parseRws(_syntheticRws(), path: 'synthetic.rws');

    expect(stream.name, 'Stream0');
    expect(stream.sampleRate, 22050);
    expect(stream.channels, 1);
    expect(stream.bitsPerSample, 4);
    expect(stream.isXboxAdpcm, isTrue);
    expect(stream.segments.single.name, 'Segment0');
    expect(stream.segments.single.markerCount, 0);

    final wav = stream.decodeFirstSegmentToWav();
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 22050);
    expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 128);
    expect(ByteData.sublistView(wav).getInt16(44, Endian.little), 1000);
  });

  test('rejects a chunk that exceeds its container', () {
    final bytes = _syntheticRws();
    ByteData.sublistView(bytes).setUint32(16, 0xffffffff, Endian.little);

    expect(
      () => parseRws(bytes),
      throwsA(
        isA<ImportException>().having(
          (error) => error.code,
          'code',
          ImportErrorCode.truncatedInput,
        ),
      ),
    );
  });
}

Uint8List _syntheticRws() {
  final info = BytesBuilder();
  void u8(int value) => info.add([value]);
  void u16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    info.add(data.buffer.asUint8List());
  }

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    info.add(data.buffer.asUint8List());
  }

  void fixed(String value) {
    info.add([...value.codeUnits, ...List<int>.filled(16 - value.length, 0)]);
  }

  u32(0);
  for (final value in [0x14, 0x10, 0x24, 7]) {
    u32(value);
  }
  for (final value in [
    0xffffffff,
    0xffffffff,
    0,
    1,
    0xffffffff,
    1,
    0xffffffff,
    36,
    36,
    36,
    0,
  ]) {
    u32(value);
  }
  info.add(List<int>.filled(16, 0));
  fixed('Stream0');
  for (final value in [0xffffffff, 0xffffffff, 0, 0xffffffff, 0, 0, 36, 0]) {
    u32(value);
  }
  u32(36);
  info.add(List<int>.filled(16, 0));
  fixed('Segment0');
  for (final value in [0xffffffff, 0xffffffff, 0, 7, 36, 0xffffffff]) {
    u32(value);
  }
  u16(4);
  u16(4);
  u16(9);
  u8(0);
  u8(0);
  u32(36);
  u32(0);
  u32(22050);
  u32(0xffffffff);
  u32(0);
  u8(4);
  u8(1);
  u8(0);
  u8(0);
  u32(0);
  u32(0);
  info.add(List<int>.filled(4, 0));
  info.add(const [
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
  ]);
  u32(0);
  info.add(List<int>.filled(16, 0));
  fixed('SubStream0');

  final adpcm = Uint8List(36);
  ByteData.sublistView(adpcm).setInt16(0, 1000, Endian.little);
  final infoChunk = _chunk(0x80e, info.takeBytes());
  final dataChunk = _chunk(0x80f, adpcm);
  return _chunk(0x80d, Uint8List.fromList([...infoChunk, ...dataChunk]));
}

Uint8List _chunk(int tag, Uint8List payload) {
  final output = ByteData(12 + payload.length);
  output.setUint32(0, tag, Endian.little);
  output.setUint32(4, payload.length, Endian.little);
  output.setUint32(8, 0x1803ffff, Endian.little);
  output.buffer.asUint8List().setRange(12, 12 + payload.length, payload);
  return output.buffer.asUint8List();
}
