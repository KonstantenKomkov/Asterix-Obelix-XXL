import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int asterixPackageContainerVersion = 1;
const int asterixPackageSchemaMajor = 1;
const int asterixPackageSchemaMinor = 0;
const int asterixPackageHeaderSize = 48;
const int asterixPackagePayloadAlignment = 16;

const _packageMagic = <int>[0x41, 0x53, 0x54, 0x50, 0x41, 0x4b, 0x0d, 0x0a];
final _kindPattern = RegExp(r'^[a-z][a-z0-9-]{0,31}$');
final _idPattern = RegExp(r'^astx:[a-z][a-z0-9-]{0,31}:[0-9a-f]{32}$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

enum AssetPackageErrorCode {
  invalidInput,
  truncatedInput,
  invalidMagic,
  unsupportedVersion,
  invalidManifest,
  invalidReference,
  checksumMismatch,
}

final class AssetPackageException implements Exception {
  const AssetPackageException(
    this.code,
    this.message, {
    this.details = const {},
  });

  final AssetPackageErrorCode code;
  final String message;
  final Map<String, Object> details;

  @override
  String toString() => jsonEncode({
    'error': code.name,
    'message': message,
    if (details.isNotEmpty) 'details': details,
  });
}

abstract final class StableAssetId {
  static String fromSource({
    required String kind,
    required String sourcePath,
    required String sourceKey,
  }) {
    final normalizedKind = _normalizeKind(kind);
    final normalizedPath = _normalizeSourcePath(sourcePath);
    final normalizedKey = sourceKey.trim();
    if (normalizedKey.isEmpty) {
      throw const AssetPackageException(
        AssetPackageErrorCode.invalidInput,
        'Stable ID source key must not be empty.',
      );
    }
    final digest = sha256.convert(
      utf8.encode(
        'asterix-stable-id-v1\u0000$normalizedKind\u0000$normalizedPath\u0000$normalizedKey',
      ),
    );
    return 'astx:$normalizedKind:${digest.toString().substring(0, 32)}';
  }
}

final class AssetPayloadInput {
  AssetPayloadInput({
    required this.kind,
    required this.sourcePath,
    required this.sourceKey,
    required Uint8List bytes,
    this.metadata = const {},
  }) : id = StableAssetId.fromSource(
         kind: kind,
         sourcePath: sourcePath,
         sourceKey: sourceKey,
       ),
       bytes = Uint8List.fromList(bytes);

  final String id;
  final String kind;
  final String sourcePath;
  final String sourceKey;
  final Uint8List bytes;
  final Map<String, Object?> metadata;
}

final class RuntimeObjectInput {
  RuntimeObjectInput({
    required this.kind,
    required this.sourcePath,
    required this.sourceKey,
    this.payloadIds = const [],
    this.dependencies = const [],
    this.metadata = const {},
  }) : id = StableAssetId.fromSource(
         kind: kind,
         sourcePath: sourcePath,
         sourceKey: sourceKey,
       );

  final String id;
  final String kind;
  final String sourcePath;
  final String sourceKey;
  final List<String> payloadIds;
  final List<String> dependencies;
  final Map<String, Object?> metadata;
}

final class AsterixAssetPackageBuilder {
  const AsterixAssetPackageBuilder();

  Uint8List build({
    required String bundleId,
    required List<RuntimeObjectInput> objects,
    required List<AssetPayloadInput> payloads,
    String? entryObjectId,
  }) {
    if (bundleId.trim().isEmpty) {
      throw const AssetPackageException(
        AssetPackageErrorCode.invalidInput,
        'Bundle ID must not be empty.',
      );
    }
    final sortedObjects = [...objects]..sort((a, b) => a.id.compareTo(b.id));
    final sortedPayloads = [...payloads]..sort((a, b) => a.id.compareTo(b.id));
    final objectIds = _uniqueIds(
      sortedObjects.map((value) => value.id),
      'object',
    );
    final payloadIds = _uniqueIds(
      sortedPayloads.map((value) => value.id),
      'payload',
    );
    final sharedIds = objectIds.intersection(payloadIds);
    if (sharedIds.isNotEmpty) {
      throw AssetPackageException(
        AssetPackageErrorCode.invalidInput,
        'Stable IDs must be unique across objects and payloads.',
        details: {'id': sharedIds.first},
      );
    }
    if (entryObjectId != null && !objectIds.contains(entryObjectId)) {
      throw AssetPackageException(
        AssetPackageErrorCode.invalidReference,
        'Entry object does not exist.',
        details: {'entryObjectId': entryObjectId},
      );
    }
    for (final object in sortedObjects) {
      _uniqueIds(object.payloadIds, 'payload reference');
      _uniqueIds(object.dependencies, 'dependency');
      for (final payloadId in object.payloadIds) {
        if (!payloadIds.contains(payloadId)) {
          throw AssetPackageException(
            AssetPackageErrorCode.invalidReference,
            'Object references an unknown payload.',
            details: {'objectId': object.id, 'payloadId': payloadId},
          );
        }
      }
      for (final dependency in object.dependencies) {
        if (!objectIds.contains(dependency)) {
          throw AssetPackageException(
            AssetPackageErrorCode.invalidReference,
            'Object references an unknown dependency.',
            details: {'objectId': object.id, 'dependency': dependency},
          );
        }
      }
    }

    var payloadLength = 0;
    final resourceEntries = <Map<String, Object?>>[];
    for (final payload in sortedPayloads) {
      payloadLength = _align(payloadLength, asterixPackagePayloadAlignment);
      resourceEntries.add({
        'id': payload.id,
        'kind': _normalizeKind(payload.kind),
        'source': {
          'path': _normalizeSourcePath(payload.sourcePath),
          'key': payload.sourceKey.trim(),
        },
        'offset': payloadLength,
        'length': payload.bytes.length,
        'sha256': sha256.convert(payload.bytes).toString(),
        if (payload.metadata.isNotEmpty) 'metadata': payload.metadata,
      });
      payloadLength += payload.bytes.length;
    }

    final manifest = <String, Object?>{
      'format': 'asterix-runtime-package',
      'schema': {
        'major': asterixPackageSchemaMajor,
        'minor': asterixPackageSchemaMinor,
      },
      'bundleId': bundleId.trim(),
      if (entryObjectId != null) 'entryObjectId': entryObjectId,
      'objects': [
        for (final object in sortedObjects)
          {
            'id': object.id,
            'kind': _normalizeKind(object.kind),
            'source': {
              'path': _normalizeSourcePath(object.sourcePath),
              'key': object.sourceKey.trim(),
            },
            'payloadIds': [...object.payloadIds]..sort(),
            'dependencies': [...object.dependencies]..sort(),
            if (object.metadata.isNotEmpty) 'metadata': object.metadata,
          },
      ],
      'resources': resourceEntries,
    };
    final manifestBytes = Uint8List.fromList(
      utf8.encode(_canonicalJson(manifest)),
    );
    final payloadOffset = _align(
      asterixPackageHeaderSize + manifestBytes.length,
      asterixPackagePayloadAlignment,
    );
    final output = Uint8List(payloadOffset + payloadLength);
    output.setRange(0, _packageMagic.length, _packageMagic);
    final header = ByteData.sublistView(output);
    header
      ..setUint32(8, asterixPackageContainerVersion, Endian.little)
      ..setUint32(12, asterixPackageHeaderSize, Endian.little)
      ..setUint32(16, asterixPackageSchemaMajor, Endian.little)
      ..setUint32(20, asterixPackageSchemaMinor, Endian.little)
      ..setUint64(24, manifestBytes.length, Endian.little)
      ..setUint64(32, payloadOffset, Endian.little)
      ..setUint64(40, payloadLength, Endian.little);
    output.setRange(
      asterixPackageHeaderSize,
      asterixPackageHeaderSize + manifestBytes.length,
      manifestBytes,
    );
    for (var index = 0; index < sortedPayloads.length; index++) {
      final entry = resourceEntries[index];
      final offset = entry['offset']! as int;
      final bytes = sortedPayloads[index].bytes;
      output.setRange(
        payloadOffset + offset,
        payloadOffset + offset + bytes.length,
        bytes,
      );
    }
    return output;
  }
}

final class AsterixAssetPackage {
  AsterixAssetPackage._(this.manifest, this._bytes, this.payloadOffset);

  final Map<String, Object?> manifest;
  final Uint8List _bytes;
  final int payloadOffset;

  static AsterixAssetPackage parse(Uint8List bytes) {
    if (bytes.length < asterixPackageHeaderSize) {
      throw const AssetPackageException(
        AssetPackageErrorCode.truncatedInput,
        'Package is shorter than its fixed header.',
      );
    }
    if (!_listEquals(bytes.sublist(0, 8), _packageMagic)) {
      throw const AssetPackageException(
        AssetPackageErrorCode.invalidMagic,
        'Package magic does not match ASTPAK.',
      );
    }
    final header = ByteData.sublistView(bytes);
    final containerVersion = header.getUint32(8, Endian.little);
    final headerSize = header.getUint32(12, Endian.little);
    final schemaMajor = header.getUint32(16, Endian.little);
    final schemaMinor = header.getUint32(20, Endian.little);
    if (containerVersion != asterixPackageContainerVersion ||
        schemaMajor != asterixPackageSchemaMajor ||
        schemaMinor > asterixPackageSchemaMinor) {
      throw AssetPackageException(
        AssetPackageErrorCode.unsupportedVersion,
        'Package version is not supported.',
        details: {
          'container': containerVersion,
          'schemaMajor': schemaMajor,
          'schemaMinor': schemaMinor,
        },
      );
    }
    if (headerSize != asterixPackageHeaderSize) {
      throw AssetPackageException(
        AssetPackageErrorCode.invalidManifest,
        'Package header size is invalid.',
        details: {'headerSize': headerSize},
      );
    }
    final manifestLength = header.getUint64(24, Endian.little);
    final payloadOffset = header.getUint64(32, Endian.little);
    final payloadLength = header.getUint64(40, Endian.little);
    if (manifestLength > bytes.length - asterixPackageHeaderSize ||
        payloadOffset < asterixPackageHeaderSize + manifestLength ||
        payloadOffset % asterixPackagePayloadAlignment != 0 ||
        payloadLength > bytes.length - payloadOffset ||
        payloadOffset + payloadLength != bytes.length) {
      throw const AssetPackageException(
        AssetPackageErrorCode.truncatedInput,
        'Package manifest or payload range is invalid.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(
          bytes.sublist(
            asterixPackageHeaderSize,
            asterixPackageHeaderSize + manifestLength,
          ),
        ),
      );
    } on FormatException {
      throw const AssetPackageException(
        AssetPackageErrorCode.invalidManifest,
        'Package manifest is not valid UTF-8 JSON.',
      );
    }
    if (decoded is! Map<String, Object?> ||
        decoded['format'] != 'asterix-runtime-package') {
      throw const AssetPackageException(
        AssetPackageErrorCode.invalidManifest,
        'Package manifest root is invalid.',
      );
    }
    final package = AsterixAssetPackage._(
      _freezeJson(decoded) as Map<String, Object?>,
      Uint8List.fromList(bytes),
      payloadOffset,
    );
    package._validateManifestAndPayloads();
    return package;
  }

  Uint8List payload(String id) {
    final resources = manifest['resources']! as List<Object?>;
    final entry = resources.cast<Map<String, Object?>>().where(
      (value) => value['id'] == id,
    );
    if (entry.isEmpty) {
      throw AssetPackageException(
        AssetPackageErrorCode.invalidReference,
        'Payload ID does not exist.',
        details: {'id': id},
      );
    }
    final resource = entry.single;
    final offset = resource['offset']! as int;
    final length = resource['length']! as int;
    return Uint8List.fromList(
      _bytes.sublist(payloadOffset + offset, payloadOffset + offset + length),
    );
  }

  void _validateManifestAndPayloads() {
    final schema = manifest['schema'];
    final objects = manifest['objects'];
    final resources = manifest['resources'];
    if (schema is! Map<String, Object?> ||
        schema['major'] != asterixPackageSchemaMajor ||
        schema['minor'] != asterixPackageSchemaMinor ||
        objects is! List<Object?> ||
        resources is! List<Object?> ||
        manifest['bundleId'] is! String ||
        (manifest['bundleId']! as String).trim().isEmpty) {
      throw const AssetPackageException(
        AssetPackageErrorCode.invalidManifest,
        'Package manifest is missing required v1 fields.',
      );
    }
    final resourceIds = <String>{};
    for (final value in resources) {
      if (value is! Map<String, Object?> ||
          value['id'] is! String ||
          !_idPattern.hasMatch(value['id']! as String) ||
          value['offset'] is! int ||
          value['length'] is! int ||
          value['sha256'] is! String ||
          !_sha256Pattern.hasMatch(value['sha256']! as String)) {
        throw const AssetPackageException(
          AssetPackageErrorCode.invalidManifest,
          'Resource entry is invalid.',
        );
      }
      final id = value['id']! as String;
      _validateEntryIdentity(value, id);
      if (!resourceIds.add(id)) {
        throw AssetPackageException(
          AssetPackageErrorCode.invalidManifest,
          'Resource ID is duplicated.',
          details: {'id': id},
        );
      }
      final offset = value['offset']! as int;
      final length = value['length']! as int;
      if (offset < 0 ||
          length < 0 ||
          offset % asterixPackagePayloadAlignment != 0 ||
          offset + length > _bytes.length - payloadOffset) {
        throw AssetPackageException(
          AssetPackageErrorCode.invalidManifest,
          'Resource payload range is invalid.',
          details: {'id': id},
        );
      }
      final actual = sha256
          .convert(
            _bytes.sublist(
              payloadOffset + offset,
              payloadOffset + offset + length,
            ),
          )
          .toString();
      if (actual != value['sha256']) {
        throw AssetPackageException(
          AssetPackageErrorCode.checksumMismatch,
          'Resource checksum does not match its manifest.',
          details: {'id': id},
        );
      }
    }
    final objectIds = <String>{};
    for (final value in objects) {
      if (value is! Map<String, Object?> ||
          value['id'] is! String ||
          !_idPattern.hasMatch(value['id']! as String) ||
          value['payloadIds'] is! List<Object?> ||
          value['dependencies'] is! List<Object?>) {
        throw const AssetPackageException(
          AssetPackageErrorCode.invalidManifest,
          'Object entry is invalid.',
        );
      }
      final id = value['id']! as String;
      _validateEntryIdentity(value, id);
      if (!objectIds.add(id) || resourceIds.contains(id)) {
        throw AssetPackageException(
          AssetPackageErrorCode.invalidManifest,
          'Object ID is duplicated.',
          details: {'id': id},
        );
      }
    }
    for (final value in objects.cast<Map<String, Object?>>()) {
      final payloadReferences = value['payloadIds']! as List<Object?>;
      final dependencyReferences = value['dependencies']! as List<Object?>;
      if (payloadReferences.toSet().length != payloadReferences.length ||
          dependencyReferences.toSet().length != dependencyReferences.length) {
        throw AssetPackageException(
          AssetPackageErrorCode.invalidManifest,
          'Object references must be unique.',
          details: {'objectId': value['id']! as String},
        );
      }
      for (final payloadId in payloadReferences) {
        if (payloadId is! String || !resourceIds.contains(payloadId)) {
          throw AssetPackageException(
            AssetPackageErrorCode.invalidReference,
            'Object payload reference is invalid.',
            details: {'objectId': value['id']! as String},
          );
        }
      }
      for (final dependency in dependencyReferences) {
        if (dependency is! String || !objectIds.contains(dependency)) {
          throw AssetPackageException(
            AssetPackageErrorCode.invalidReference,
            'Object dependency is invalid.',
            details: {'objectId': value['id']! as String},
          );
        }
      }
    }
    final entryObjectId = manifest['entryObjectId'];
    if (entryObjectId != null &&
        (entryObjectId is! String || !objectIds.contains(entryObjectId))) {
      throw const AssetPackageException(
        AssetPackageErrorCode.invalidReference,
        'Entry object reference is invalid.',
      );
    }
  }
}

void _validateEntryIdentity(Map<String, Object?> entry, String id) {
  final kind = entry['kind'];
  final source = entry['source'];
  if (kind is! String ||
      source is! Map<String, Object?> ||
      source['path'] is! String ||
      source['key'] is! String) {
    throw AssetPackageException(
      AssetPackageErrorCode.invalidManifest,
      'Asset source identity is invalid.',
      details: {'id': id},
    );
  }
  String expected;
  try {
    final normalizedKind = _normalizeKind(kind);
    final normalizedPath = _normalizeSourcePath(source['path']! as String);
    final normalizedKey = (source['key']! as String).trim();
    if (kind != normalizedKind ||
        source['path'] != normalizedPath ||
        source['key'] != normalizedKey) {
      throw const AssetPackageException(
        AssetPackageErrorCode.invalidInput,
        'Source identity is not canonical.',
      );
    }
    expected = StableAssetId.fromSource(
      kind: kind,
      sourcePath: source['path']! as String,
      sourceKey: source['key']! as String,
    );
  } on AssetPackageException {
    throw AssetPackageException(
      AssetPackageErrorCode.invalidManifest,
      'Asset source identity is invalid.',
      details: {'id': id},
    );
  }
  if (id != expected) {
    throw AssetPackageException(
      AssetPackageErrorCode.invalidManifest,
      'Stable asset ID does not match its source identity.',
      details: {'id': id, 'expected': expected},
    );
  }
}

Set<String> _uniqueIds(Iterable<String> ids, String label) {
  final unique = <String>{};
  for (final id in ids) {
    if (!unique.add(id)) {
      throw AssetPackageException(
        AssetPackageErrorCode.invalidInput,
        'Stable $label ID is duplicated.',
        details: {'id': id},
      );
    }
  }
  return unique;
}

String _normalizeKind(String value) {
  final kind = value.trim().toLowerCase();
  if (!_kindPattern.hasMatch(kind)) {
    throw AssetPackageException(
      AssetPackageErrorCode.invalidInput,
      'Asset kind is invalid.',
      details: {'kind': value},
    );
  }
  return kind;
}

String _normalizeSourcePath(String value) {
  final path = value.trim().replaceAll('\\', '/').toLowerCase();
  final segments = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (path.startsWith('/') ||
      RegExp(r'^[a-z]:/').hasMatch(path) ||
      segments.isEmpty ||
      segments.any((segment) => segment == '.' || segment == '..')) {
    throw AssetPackageException(
      AssetPackageErrorCode.invalidInput,
      'Source path must be a normalized relative path.',
      details: {'path': value},
    );
  }
  return segments.join('/');
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const AssetPackageException(
          AssetPackageErrorCode.invalidInput,
          'Manifest metadata keys must be strings.',
        );
      }
      sorted[entry.key as String] = _canonicalize(entry.value);
    }
    return sorted;
  }
  if (value is List) return value.map(_canonicalize).toList(growable: false);
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  throw AssetPackageException(
    AssetPackageErrorCode.invalidInput,
    'Manifest metadata contains an unsupported value.',
    details: {'type': value.runtimeType.toString()},
  );
}

Object? _freezeJson(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key: _freezeJson(entry.value),
    });
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  return value;
}

int _align(int value, int alignment) =>
    (value + alignment - 1) & ~(alignment - 1);

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
