import 'dart:io';
import 'dart:typed_data';

import 'package:asterix_xxl/importer/importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('synthetic importer container', () {
    test('parses the checked-in synthetic fixture', () {
      final bytes = _readHexFixture('test/fixtures/synthetic_container.hex');

      final header = parseSyntheticContainer(bytes, path: 'fixture.hex');

      expect(header.version, 1);
      expect(header.sectionCount, 2);
      expect(header.declaredSize, 12);
    });

    test('reports a structured truncation error with an offset', () {
      expect(
        () => parseSyntheticContainer(
          Uint8List.fromList([0x41, 0x53]),
          path: 'short.bin',
        ),
        throwsA(
          isA<ImportException>()
              .having(
                (error) => error.code,
                'code',
                ImportErrorCode.truncatedInput,
              )
              .having((error) => error.path, 'path', 'short.bin')
              .having((error) => error.offset, 'offset', 0),
        ),
      );
    });

    test('rejects a mismatched declared size', () {
      final bytes = _readHexFixture('test/fixtures/synthetic_container.hex');
      bytes[8] = 13;

      expect(
        () => parseSyntheticContainer(bytes),
        throwsA(
          isA<ImportException>().having(
            (error) => error.code,
            'code',
            ImportErrorCode.invalidValue,
          ),
        ),
      );
    });

    test('reports unsupported versions at the version field', () {
      final bytes = _readHexFixture('test/fixtures/synthetic_container.hex');
      bytes[4] = 2;

      expect(
        () => parseSyntheticContainer(bytes, path: 'future.bin'),
        throwsA(
          isA<ImportException>()
              .having(
                (error) => error.code,
                'code',
                ImportErrorCode.unsupportedVersion,
              )
              .having((error) => error.offset, 'offset', 4),
        ),
      );
    });
  });

  test('binary reader rejects negative byte counts', () {
    final reader = BinaryReader(Uint8List(0));
    expect(
      () => reader.readBytes(-1),
      throwsA(
        isA<ImportException>().having(
          (error) => error.code,
          'code',
          ImportErrorCode.invalidValue,
        ),
      ),
    );
  });

  test('structured errors serialize stable machine-readable fields', () {
    const error = ImportException(
      code: ImportErrorCode.truncatedInput,
      message: 'short',
      path: 'fixture.bin',
      offset: 7,
      details: {'remaining': 0},
    );

    expect(error.toJson(), {
      'error': 'truncatedInput',
      'message': 'short',
      'path': 'fixture.bin',
      'offset': 7,
      'details': {'remaining': 0},
    });
  });
}

Uint8List _readHexFixture(String path) {
  final source = File(path)
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('#'))
      .join(' ');
  final values = RegExp(r'[0-9a-fA-F]{2}')
      .allMatches(source)
      .map((match) => int.parse(match.group(0)!, radix: 16))
      .toList();
  return Uint8List.fromList(values);
}
