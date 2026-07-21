import 'dart:typed_data';

import 'package:asterix_xxl/runtime/asset_package.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a deterministic v1 package and reads payloads', () {
    final mesh = AssetPayloadInput(
      kind: 'mesh',
      sourcePath: r'LVL001\STR01_00.KWN',
      sourceKey: 'geometry:17',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      metadata: const {'vertexCount': 3},
    );
    final texture = AssetPayloadInput(
      kind: 'texture',
      sourcePath: 'LVL001/STR01_00.KWN',
      sourceKey: 'texture:test',
      bytes: Uint8List.fromList([9, 8]),
    );
    final node = RuntimeObjectInput(
      kind: 'scene-node',
      sourcePath: 'LVL001/STR01_00.KWN',
      sourceKey: 'node:4',
      payloadIds: [mesh.id, texture.id],
      metadata: const {'name': 'synthetic-root'},
    );
    const builder = AsterixAssetPackageBuilder();

    final first = builder.build(
      bundleId: 'synthetic-test',
      objects: [node],
      payloads: [texture, mesh],
      entryObjectId: node.id,
    );
    final second = builder.build(
      bundleId: 'synthetic-test',
      objects: [node],
      payloads: [mesh, texture],
      entryObjectId: node.id,
    );
    final package = AsterixAssetPackage.parse(first);

    expect(first, second);
    expect(package.manifest['bundleId'], 'synthetic-test');
    expect(package.manifest['entryObjectId'], node.id);
    expect(package.payload(mesh.id), [1, 2, 3, 4]);
    expect(package.payload(texture.id), [9, 8]);
    expect(package.payloadOffset % asterixPackagePayloadAlignment, 0);
    expect(
      () => (package.manifest['schema']! as Map<String, Object?>)['minor'] = 2,
      throwsUnsupportedError,
    );
  });

  test('stable IDs depend on logical source identity, not payload bytes', () {
    final first = AssetPayloadInput(
      kind: 'mesh',
      sourcePath: r'LVL001\STR01_00.KWN',
      sourceKey: 'geometry:17',
      bytes: Uint8List.fromList([1]),
    );
    final changedContent = AssetPayloadInput(
      kind: 'MESH',
      sourcePath: 'lvl001/str01_00.kwn',
      sourceKey: 'geometry:17',
      bytes: Uint8List.fromList([2, 3]),
    );
    final otherObject = AssetPayloadInput(
      kind: 'mesh',
      sourcePath: 'LVL001/STR01_00.KWN',
      sourceKey: 'geometry:18',
      bytes: Uint8List.fromList([1]),
    );

    expect(first.id, changedContent.id);
    expect(first.id, isNot(otherObject.id));
    expect(first.id, matches(r'^astx:mesh:[0-9a-f]{32}$'));
  });

  test('rejects missing references before writing', () {
    final node = RuntimeObjectInput(
      kind: 'scene-node',
      sourcePath: 'fixture/scene.json',
      sourceKey: 'root',
      payloadIds: const ['astx:mesh:00000000000000000000000000000000'],
    );

    expect(
      () => const AsterixAssetPackageBuilder().build(
        bundleId: 'broken',
        objects: [node],
        payloads: const [],
      ),
      throwsA(
        isA<AssetPackageException>().having(
          (error) => error.code,
          'code',
          AssetPackageErrorCode.invalidReference,
        ),
      ),
    );
  });

  test('rejects duplicate references before writing', () {
    final payload = AssetPayloadInput(
      kind: 'mesh',
      sourcePath: 'fixture/scene.json',
      sourceKey: 'mesh:0',
      bytes: Uint8List(0),
    );
    final node = RuntimeObjectInput(
      kind: 'scene-node',
      sourcePath: 'fixture/scene.json',
      sourceKey: 'root',
      payloadIds: [payload.id, payload.id],
    );

    expect(
      () => const AsterixAssetPackageBuilder().build(
        bundleId: 'duplicate-reference',
        objects: [node],
        payloads: [payload],
      ),
      throwsA(
        isA<AssetPackageException>().having(
          (error) => error.code,
          'code',
          AssetPackageErrorCode.invalidInput,
        ),
      ),
    );
  });

  test('rejects an ID shared by an object and payload', () {
    final payload = AssetPayloadInput(
      kind: 'mesh',
      sourcePath: 'fixture/scene.json',
      sourceKey: 'mesh:0',
      bytes: Uint8List(0),
    );
    final object = RuntimeObjectInput(
      kind: 'mesh',
      sourcePath: 'fixture/scene.json',
      sourceKey: 'mesh:0',
    );

    expect(
      () => const AsterixAssetPackageBuilder().build(
        bundleId: 'shared-id',
        objects: [object],
        payloads: [payload],
      ),
      throwsA(
        isA<AssetPackageException>().having(
          (error) => error.code,
          'code',
          AssetPackageErrorCode.invalidInput,
        ),
      ),
    );
  });

  test('rejects unsupported versions and payload corruption', () {
    final payload = AssetPayloadInput(
      kind: 'audio',
      sourcePath: 'fixture/audio.wav',
      sourceKey: 'stream:0',
      bytes: Uint8List.fromList([4, 5, 6]),
    );
    final bytes = const AsterixAssetPackageBuilder().build(
      bundleId: 'validation',
      objects: const [],
      payloads: [payload],
    );
    final unsupported = Uint8List.fromList(bytes);
    ByteData.sublistView(unsupported).setUint32(8, 99, Endian.little);
    expect(
      () => AsterixAssetPackage.parse(unsupported),
      throwsA(
        isA<AssetPackageException>().having(
          (error) => error.code,
          'code',
          AssetPackageErrorCode.unsupportedVersion,
        ),
      ),
    );

    final corrupted = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 0xff;
    expect(
      () => AsterixAssetPackage.parse(corrupted),
      throwsA(
        isA<AssetPackageException>().having(
          (error) => error.code,
          'code',
          AssetPackageErrorCode.checksumMismatch,
        ),
      ),
    );
  });
}
