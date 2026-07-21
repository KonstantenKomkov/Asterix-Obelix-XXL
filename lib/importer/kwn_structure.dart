import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';

enum KwnFamily { game, globalLocale, levelLocale, level, sector }

final class KwnStructure {
  const KwnStructure(this.family, this.fields);

  final KwnFamily family;
  final Map<String, Object> fields;

  Map<String, Object> toJson() => {
    'format': 'kwn',
    'family': family.name,
    ...fields,
  };
}

final class KwnObjectSlice {
  const KwnObjectSlice({
    required this.category,
    required this.classId,
    required this.objectIndex,
    required this.objectId,
    required this.payloadOffset,
    required this.endOffset,
  });

  final int category;
  final int classId;
  final int objectIndex;
  final int objectId;
  final int payloadOffset;
  final int endOffset;
}

List<KwnObjectSlice> scanXxl1SectorObjects(
  Uint8List bytes, {
  required String path,
}) => _scanSector(BinaryReader(bytes, path: path)).objects;

KwnStructure probeKwnStructure(Uint8List bytes, {required String path}) {
  final family = _familyFromPath(path);
  final reader = BinaryReader(bytes, path: path);
  return switch (family) {
    KwnFamily.game => _probeObjectPack(reader, family, hasManagerId: true),
    KwnFamily.globalLocale || KwnFamily.levelLocale => _probeObjectPack(
      reader,
      family,
      hasManagerId: false,
    ),
    KwnFamily.sector => _probeSector(reader),
    KwnFamily.level => _probeProtectedLevel(reader),
  };
}

KwnFamily _familyFromPath(String path) {
  final name = path.replaceAll('\\', '/').split('/').last.toUpperCase();
  if (name == 'GAME.KWN') return KwnFamily.game;
  if (RegExp(r'^\d{2}GLOC\.KWN$').hasMatch(name)) {
    return KwnFamily.globalLocale;
  }
  if (RegExp(r'^\d{2}LLOC\d{2}\.KWN$').hasMatch(name)) {
    return KwnFamily.levelLocale;
  }
  if (RegExp(r'^LVL\d{2}\.KWN$').hasMatch(name)) return KwnFamily.level;
  if (RegExp(r'^STR\d{2}_\d{2}\.KWN$').hasMatch(name)) {
    return KwnFamily.sector;
  }
  throw ImportException(
    code: ImportErrorCode.invalidArguments,
    message: 'Cannot infer KWN family from the file name.',
    path: path,
  );
}

KwnStructure _probeObjectPack(
  BinaryReader reader,
  KwnFamily family, {
  required bool hasManagerId,
}) {
  final objectCount = reader.readUint32();
  final managerId = hasManagerId ? reader.readUint32() : null;
  final objects = <Map<String, Object>>[];
  for (var index = 0; index < objectCount; index++) {
    final headerOffset = reader.offset;
    final category = reader.readUint32();
    final classId = reader.readUint32();
    final endOffset = reader.readUint32();
    _validateForwardOffset(reader, endOffset, 'object');
    objects.add({
      'index': index,
      'category': category,
      'classId': classId,
      'headerOffset': headerOffset,
      'payloadOffset': reader.offset,
      'endOffset': endOffset,
    });
    reader.seek(endOffset);
  }
  _requireEnd(reader);
  return KwnStructure(family, {
    'size': reader.length,
    'objectCount': objectCount,
    if (managerId != null) 'managerId': managerId,
    'objects': objects,
  });
}

KwnStructure _probeSector(BinaryReader reader) {
  final scan = _scanSector(reader);
  return KwnStructure(KwnFamily.sector, {
    'size': reader.length,
    'categoryCount': 15,
    'directoryEnd': scan.directoryEnd,
    'classCounts': scan.counts.map((classes) => classes.length).toList(),
    'objectCount': scan.objects.length,
  });
}

_SectorScan _scanSector(BinaryReader reader) {
  final counts = <List<int>>[];
  for (var category = 0; category < 15; category++) {
    final classCount = reader.readUint16();
    final categoryCounts = <int>[];
    for (var classId = 0; classId < classCount; classId++) {
      final count = reader.readUint16();
      categoryCounts.add(count);
    }
    counts.add(categoryCounts);
  }
  final directoryEnd = reader.offset;
  final objects = <KwnObjectSlice>[];

  const order = [0, 9, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14];
  for (final category in order) {
    final activeClasses = reader.readUint16();
    final categoryEnd = reader.readUint32();
    final expectedActive = counts[category].where((count) => count > 0).length;
    if (activeClasses != expectedActive) {
      _invalid(
        reader,
        'Active class count does not match the sector directory.',
        {
          'category': category,
          'expected': expectedActive,
          'actual': activeClasses,
        },
      );
    }
    for (var classId = 0; classId < counts[category].length; classId++) {
      final count = counts[category][classId];
      if (count == 0) continue;
      final classEnd = reader.readUint32();
      final startObjectId = reader.readUint16();
      for (var object = 0; object < count; object++) {
        final objectEnd = reader.readUint32();
        _validateForwardOffset(reader, objectEnd, 'object');
        objects.add(
          KwnObjectSlice(
            category: category,
            classId: classId,
            objectIndex: object,
            objectId: startObjectId + object,
            payloadOffset: reader.offset,
            endOffset: objectEnd,
          ),
        );
        reader.seek(objectEnd);
      }
      _requireOffset(reader, classEnd, 'class');
    }
    _requireOffset(reader, categoryEnd, 'category');
  }
  _requireEnd(reader);
  return _SectorScan(
    counts: counts,
    directoryEnd: directoryEnd,
    objects: objects,
  );
}

final class _SectorScan {
  const _SectorScan({
    required this.counts,
    required this.directoryEnd,
    required this.objects,
  });

  final List<List<int>> counts;
  final int directoryEnd;
  final List<KwnObjectSlice> objects;
}

KwnStructure _probeProtectedLevel(BinaryReader reader) {
  final firstWord = reader.readUint32();
  final secondWord = reader.readUint32();
  return KwnStructure(KwnFamily.level, {
    'size': reader.length,
    'protectedLayout': true,
    'prefixWords': [firstWord, secondWord],
    'parseStatus': 'headerRequiresDrmExtraction',
  });
}

void _validateForwardOffset(BinaryReader reader, int target, String kind) {
  if (target < reader.offset || target > reader.length) {
    _invalid(reader, 'Invalid $kind end offset.', {
      'target': target,
      'length': reader.length,
    });
  }
}

void _requireOffset(BinaryReader reader, int expected, String kind) {
  if (reader.offset != expected) {
    _invalid(reader, '$kind end offset does not match parsed data.', {
      'expected': expected,
      'actual': reader.offset,
    });
  }
}

void _requireEnd(BinaryReader reader) =>
    _requireOffset(reader, reader.length, 'file');

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
