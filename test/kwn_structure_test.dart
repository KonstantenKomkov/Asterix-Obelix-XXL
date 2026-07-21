import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probes a synthetic GAME object pack', () {
    final bytes = _words32([1, 51, 12, 59, 24, 0xAABBCCDD]);

    final result = probeKwnStructure(bytes, path: 'GAME.KWN');

    expect(result.family, KwnFamily.game);
    expect(result.fields['managerId'], 51);
    expect(result.fields['objectCount'], 1);
    final objects = result.fields['objects']! as List<Map<String, Object>>;
    expect(objects.single, containsPair('endOffset', 24));
  });

  test('probes a synthetic locale object pack', () {
    final bytes = _words32([1, 4, 12, 20, 0x01020304]);

    final result = probeKwnStructure(bytes, path: '00GLOC.KWN');

    expect(result.family, KwnFamily.globalLocale);
    expect(result.fields['objectCount'], 1);
  });

  test('validates a synthetic empty sector envelope', () {
    final builder = BytesBuilder(copy: false);
    for (var category = 0; category < 15; category++) {
      _addUint16(builder, 0);
    }
    for (var category = 0; category < 15; category++) {
      _addUint16(builder, 0);
      _addUint32(builder, builder.length + 4);
    }

    final result = probeKwnStructure(builder.takeBytes(), path: 'STR01_00.KWN');

    expect(result.family, KwnFamily.sector);
    expect(result.fields['directoryEnd'], 30);
    expect(result.fields['objectCount'], 0);
    expect(result.fields['size'], 120);
  });

  test('rejects an object end offset outside the file', () {
    final bytes = _words32([1, 51, 12, 59, 200]);

    expect(
      () => probeKwnStructure(bytes, path: 'GAME.KWN'),
      throwsA(
        isA<ImportException>().having(
          (error) => error.code,
          'code',
          ImportErrorCode.invalidValue,
        ),
      ),
    );
  });

  test('marks original PC level layout as protected', () {
    final result = probeKwnStructure(
      _words32([0x1234, 0x5678]),
      path: 'LVL01.KWN',
    );

    expect(result.family, KwnFamily.level);
    expect(result.fields['protectedLayout'], isTrue);
    expect(result.fields['parseStatus'], 'headerRequiresDrmExtraction');
  });
}

Uint8List _words32(List<int> words) {
  final builder = BytesBuilder(copy: false);
  for (final word in words) {
    _addUint32(builder, word);
  }
  return builder.takeBytes();
}

void _addUint16(BytesBuilder builder, int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}

void _addUint32(BytesBuilder builder, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  builder.add(data.buffer.asUint8List());
}
