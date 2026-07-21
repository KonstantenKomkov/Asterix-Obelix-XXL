import 'dart:convert';
import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';

const syntheticContainerHeaderSize = 12;
const syntheticContainerVersion = 1;
const _magic = 'ASTX';

final class SyntheticContainerHeader {
  const SyntheticContainerHeader({
    required this.version,
    required this.sectionCount,
    required this.declaredSize,
  });

  final int version;
  final int sectionCount;
  final int declaredSize;

  Map<String, Object> toJson() => {
    'format': 'synthetic-container',
    'version': version,
    'sectionCount': sectionCount,
    'declaredSize': declaredSize,
  };
}

SyntheticContainerHeader parseSyntheticContainer(
  Uint8List bytes, {
  String? path,
}) {
  final reader = BinaryReader(bytes, path: path);
  final magicOffset = reader.offset;
  final magic = ascii.decode(reader.readBytes(4), allowInvalid: true);
  if (magic != _magic) {
    throw ImportException(
      code: ImportErrorCode.invalidMagic,
      message: 'Not a synthetic importer fixture.',
      path: path,
      offset: magicOffset,
      details: {'expected': _magic, 'actual': magic},
    );
  }

  final versionOffset = reader.offset;
  final version = reader.readUint16();
  if (version != syntheticContainerVersion) {
    throw ImportException(
      code: ImportErrorCode.unsupportedVersion,
      message: 'Unsupported synthetic container version.',
      path: path,
      offset: versionOffset,
      details: {'expected': syntheticContainerVersion, 'actual': version},
    );
  }

  final sectionCount = reader.readUint16();
  final declaredSizeOffset = reader.offset;
  final declaredSize = reader.readUint32();
  if (declaredSize != bytes.length) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Declared container size does not match the file size.',
      path: path,
      offset: declaredSizeOffset,
      details: {'declared': declaredSize, 'actual': bytes.length},
    );
  }

  return SyntheticContainerHeader(
    version: version,
    sectionCount: sectionCount,
    declaredSize: declaredSize,
  );
}
