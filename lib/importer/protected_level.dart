import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';
import 'kwn_structure.dart';

const _xxl1HeaderSignature = <int>[
  0x05,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  0x0F,
  0,
];

final class Xxl1LevelScan {
  const Xxl1LevelScan({
    required this.levelNumber,
    required this.sectorCount,
    required this.headerOffset,
    required this.payloadOffset,
    required this.objects,
  });

  final int levelNumber;
  final int sectorCount;
  final int headerOffset;
  final int payloadOffset;
  final List<KwnObjectSlice> objects;
}

/// Reads an original protected XXL1 PC level without modifying either source.
///
/// The encrypted header's clear copy is selected from the local GameModule in
/// the same way as XXL-Editor's patcher. Object payload remains in LVLnn.KWN.
Xxl1LevelScan scanProtectedXxl1Level(
  Uint8List levelBytes,
  Uint8List gameModuleBytes, {
  required int levelNumber,
  String? levelPath,
  String? gameModulePath,
}) {
  if (levelNumber < 1 || levelNumber > 8) {
    throw ImportException(
      code: ImportErrorCode.invalidArguments,
      message: 'Protected XXL1 level number must be between 1 and 8.',
      path: levelPath,
      details: {'levelNumber': levelNumber},
    );
  }
  final matches = _findAll(gameModuleBytes, _xxl1HeaderSignature);
  if (matches.length < levelNumber) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'GameModule does not contain the requested level header.',
      path: gameModulePath,
      details: {'levelNumber': levelNumber, 'headersFound': matches.length},
    );
  }
  final headerOffset = matches[levelNumber - 1] - 5;
  if (headerOffset < 0) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Decoded level header starts before GameModule.',
      path: gameModulePath,
    );
  }
  final level = BinaryReader(levelBytes, path: levelPath);
  level.readUint32(); // level-specific unknown
  final protectedHeaderSize = level.readUint32();
  final payloadOffset = 8 + protectedHeaderSize + 8;
  if (payloadOffset > level.length) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Protected header size is outside the level file.',
      path: levelPath,
      details: {'protectedHeaderSize': protectedHeaderSize},
    );
  }

  final header = BinaryReader(gameModuleBytes, path: gameModulePath)
    ..seek(headerOffset);
  final sectorCount = header.readUint8();
  header.readUint32(); // level-specific unknown
  final classes = <List<_LevelClass>>[];
  for (var category = 0; category < 15; category++) {
    final classCount = header.readUint16();
    final categoryClasses = <_LevelClass>[];
    for (var classId = 0; classId < classCount; classId++) {
      categoryClasses.add(
        _LevelClass(
          totalCount: header.readUint16(),
          levelCount: header.readUint16(),
          instantiation: header.readUint8(),
        ),
      );
    }
    classes.add(categoryClasses);
  }
  if (header.offset - headerOffset > protectedHeaderSize) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Decoded header exceeds the protected header boundary.',
      path: gameModulePath,
    );
  }

  level.seek(payloadOffset);
  final objects = <KwnObjectSlice>[];
  const order = [0, 9, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14];
  for (final category in order) {
    final activeClassCount = level.readUint16();
    final categoryEnd = level.readUint32();
    final active = classes[category]
        .asMap()
        .entries
        .where((entry) => entry.value.levelCount > 0)
        .toList();
    if (activeClassCount != active.length) {
      _invalid(level, 'Level category class count does not match its header.', {
        'category': category,
        'expected': active.length,
        'actual': activeClassCount,
      });
    }
    for (final entry in active) {
      final classId = entry.key;
      final descriptor = entry.value;
      final classEnd = level.readUint32();
      if (descriptor.instantiation != 0) {
        final startId = level.readUint16();
        if (startId != 0) {
          _invalid(level, 'Level object class does not start at ID zero.', {
            'category': category,
            'classId': classId,
            'startId': startId,
          });
        }
      }
      for (var index = 0; index < descriptor.levelCount; index++) {
        final objectEnd = level.readUint32();
        if (objectEnd < level.offset || objectEnd > level.length) {
          _invalid(level, 'Invalid level object end offset.', {
            'category': category,
            'classId': classId,
            'target': objectEnd,
          });
        }
        objects.add(
          KwnObjectSlice(
            category: category,
            classId: classId,
            objectIndex: index,
            objectId: index,
            payloadOffset: level.offset,
            endOffset: objectEnd,
          ),
        );
        level.seek(objectEnd);
      }
      _requireOffset(level, classEnd, 'level class');
    }
    _requireOffset(level, categoryEnd, 'level category');
  }
  _requireOffset(level, level.length, 'level file');
  return Xxl1LevelScan(
    levelNumber: levelNumber,
    sectorCount: sectorCount,
    headerOffset: headerOffset,
    payloadOffset: payloadOffset,
    objects: objects,
  );
}

List<int> _findAll(Uint8List haystack, List<int> needle) {
  final matches = <int>[];
  for (var offset = 0; offset <= haystack.length - needle.length; offset++) {
    var matchesNeedle = true;
    for (var index = 0; index < needle.length; index++) {
      if (haystack[offset + index] != needle[index]) {
        matchesNeedle = false;
        break;
      }
    }
    if (matchesNeedle) matches.add(offset);
  }
  return matches;
}

void _requireOffset(BinaryReader reader, int expected, String kind) {
  if (reader.offset != expected) {
    _invalid(reader, '$kind end offset does not match parsed data.', {
      'expected': expected,
      'actual': reader.offset,
    });
  }
}

Never _invalid(
  BinaryReader reader,
  String message,
  Map<String, Object> details,
) {
  throw ImportException(
    code: ImportErrorCode.invalidValue,
    message: message,
    path: reader.path,
    offset: reader.offset,
    details: details,
  );
}

final class _LevelClass {
  const _LevelClass({
    required this.totalCount,
    required this.levelCount,
    required this.instantiation,
  });

  final int totalCount;
  final int levelCount;
  final int instantiation;
}
