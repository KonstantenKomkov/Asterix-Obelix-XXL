import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asterix_xxl/pipeline/slice_asset_pipeline.dart';
import 'package:asterix_xxl/runtime/asset_package.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'builds a deterministic package with all vertical-slice assets',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'asset-pipeline-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final first = Directory('${temporary.path}/first');
      final second = Directory('${temporary.path}/second');
      await _writeProof(first, reverseOrder: false);
      await _writeProof(second, reverseOrder: true);

      final pipeline = const SliceAssetPipeline();
      final firstBytes = await pipeline.buildFromProof(first);
      final secondBytes = await pipeline.buildFromProof(second);
      expect(firstBytes, orderedEquals(secondBytes));

      final package = AsterixAssetPackage.parse(firstBytes);
      final sceneNode = (package.manifest['objects']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((object) => object['kind'] == 'scene-node');
      expect(
        (sceneNode['metadata']! as Map<String, Object?>)['transform'],
        hasLength(16),
      );
      expect(
        (sceneNode['metadata']! as Map<String, Object?>)['section'],
        'LVL001/STR01_00.KWN',
      );
      final transform =
          (sceneNode['metadata']! as Map<String, Object?>)['transform']!
              as List<Object?>;
      expect(transform.sublist(12), [0.0, 0.0, 0.0, 1.0]);
      final resources = (package.manifest['resources']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        resources.map((resource) => resource['kind']).toSet(),
        containsAll(<String>{
          'mesh',
          'texture',
          'animation',
          'skin',
          'collision',
          'audio',
          'scene-manifest',
        }),
      );
      final texture = resources.singleWhere(
        (resource) => resource['kind'] == 'texture',
      );
      final textureBytes = package.payload(texture['id']! as String);
      expect(ascii.decode(textureBytes.sublist(0, 8)), 'ASTMTEX\n');
      final header = ByteData.sublistView(textureBytes);
      expect(header.getUint32(8, Endian.little), 1);
      expect(header.getUint32(12, Endian.little), 1);
      expect(header.getUint32(16, Endian.little), 2);
      expect(header.getUint32(24, Endian.little), 2);
      expect(header.getUint32(28, Endian.little), 2);
      expect(header.getUint32(40, Endian.little), 1);
      expect(header.getUint32(44, Endian.little), 1);
    },
  );

  test(
    'reuses unchanged cached transforms and rebuilds only changed input',
    () async {
      final temporary = await Directory.systemTemp.createTemp('asset-cache-');
      addTearDown(() => temporary.delete(recursive: true));
      final proof = Directory('${temporary.path}/proof');
      final cache = Directory('${temporary.path}/cache');
      await _writeProof(proof, reverseOrder: false);

      final pipeline = const SliceAssetPipeline();
      final first = await pipeline.buildIncremental(
        proof,
        cacheDirectory: cache,
      );
      expect(first.rebuiltInputs, hasLength(6));
      expect(first.cachedInputs, isEmpty);

      final second = await pipeline.buildIncremental(
        proof,
        cacheDirectory: cache,
      );
      expect(second.rebuiltInputs, isEmpty);
      expect(second.cachedInputs, hasLength(6));
      expect(second.bytes, orderedEquals(first.bytes));

      final cachedPayload = await cache
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.bin'))
          .cast<File>()
          .first;
      await cachedPayload.writeAsBytes([0], flush: true);
      final repaired = await pipeline.buildIncremental(
        proof,
        cacheDirectory: cache,
      );
      expect(repaired.rebuiltInputs, hasLength(1));
      expect(repaired.cachedInputs, hasLength(5));
      expect(repaired.bytes, orderedEquals(first.bytes));

      final animation = File('${proof.path}/animations/0000.animation.json');
      final decoded =
          jsonDecode(await animation.readAsString()) as Map<String, Object?>;
      decoded['duration'] = 2.0;
      await animation.writeAsString(jsonEncode(decoded));
      final third = await pipeline.buildIncremental(
        proof,
        cacheDirectory: cache,
      );
      expect(third.rebuiltInputs, hasLength(1));
      expect(third.cachedInputs, hasLength(5));
      expect(third.bytes, isNot(orderedEquals(first.bytes)));
    },
  );

  test(
    'packages sector-local IDs and collision from every slice sector',
    () async {
      final temporary = await Directory.systemTemp.createTemp('asset-sectors-');
      addTearDown(() => temporary.delete(recursive: true));
      final proof = Directory('${temporary.path}/proof');
      await _writeProof(proof, reverseOrder: false);
      for (final name in const ['STR01_00', 'STR01_01']) {
        final sector = Directory('${proof.path}/sectors/$name');
        await Directory('${sector.path}/textures').create(recursive: true);
        for (final relative in const [
          'scene.json',
          'collision.json',
          'textures/manifest.json',
          'textures/000_stone.png',
        ]) {
          await File(
            '${proof.path}/$relative',
          ).copy('${sector.path}/$relative');
        }
      }
      await File('${proof.path}/manifest.json').writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'slice': 'gaul-stage-1',
          'sectors': [
            {'source': 'LVL001/STR01_00.KWN', 'directory': 'sectors/STR01_00'},
            {'source': 'LVL001/STR01_01.KWN', 'directory': 'sectors/STR01_01'},
          ],
        }),
      );

      final package = AsterixAssetPackage.parse(
        await const SliceAssetPipeline().buildFromProof(proof),
      );
      final resources = (package.manifest['resources']! as List)
          .cast<Map<String, Object?>>();
      expect(
        resources.where((value) => value['kind'] == 'collision'),
        hasLength(2),
      );
      expect(resources.where((value) => value['kind'] == 'mesh'), hasLength(2));
      final nodes = (package.manifest['objects']! as List)
          .cast<Map<String, Object?>>()
          .where((value) => value['kind'] == 'scene-node');
      expect(
        nodes.map((value) => (value['metadata']! as Map)['section']).toSet(),
        {'LVL001/STR01_00.KWN', 'LVL001/STR01_01.KWN'},
      );
    },
  );

  test('reports a controlled range error for a damaged mesh', () async {
    final temporary = await Directory.systemTemp.createTemp('asset-invalid-');
    addTearDown(() => temporary.delete(recursive: true));
    final proof = Directory('${temporary.path}/proof');
    await _writeProof(proof, reverseOrder: false);
    final sceneFile = File('${proof.path}/scene.json');
    final scene =
        jsonDecode(await sceneFile.readAsString()) as Map<String, Object?>;
    final mesh = ((scene['meshes']! as List).single as Map<String, Object?>);
    mesh
      ..['vertices'] = [
        [0.0, 0.0, 0.0],
      ]
      ..['materials'] = [<String, Object?>{}]
      ..['triangles'] = [
        [0, 1, 0, 0],
      ];
    await sceneFile.writeAsString(jsonEncode(scene));

    await expectLater(
      const SliceAssetPipeline().buildFromProof(proof),
      throwsA(
        isA<AssetPipelineException>()
            .having(
              (error) => error.code,
              'code',
              AssetPipelineErrorCode.invalidRange,
            )
            .having((error) => error.path, 'path', sceneFile.path),
      ),
    );
  });
}

Future<void> _writeProof(Directory root, {required bool reverseOrder}) async {
  await Directory('${root.path}/textures').create(recursive: true);
  await Directory('${root.path}/animations').create(recursive: true);
  final image = img.Image(width: 2, height: 2)
    ..setPixelRgba(0, 0, 255, 0, 0, 255)
    ..setPixelRgba(1, 0, 0, 255, 0, 255)
    ..setPixelRgba(0, 1, 0, 0, 255, 255)
    ..setPixelRgba(1, 1, 255, 255, 255, 255);
  final files = <String, Object>{
    '${root.path}/manifest.json': {'schemaVersion': 1, 'slice': 'gaul-stage-1'},
    '${root.path}/scene.json': {
      'schemaVersion': 1,
      'format': 'asterix-sector-scene',
      'meshes': [
        {
          'objectId': 7,
          'frames': <Object>[],
          'vertices': <Object>[],
          'triangles': <Object>[],
          'materials': <Object>[],
        },
      ],
      'nodes': [
        {
          'classId': 2,
          'objectId': 1,
          'transform': List<double>.filled(16, 0),
          'parent': {'raw': 4294967295, 'null': true},
          'next': {'raw': 4294967295, 'null': true},
          'geometry': {
            'raw': 917642,
            'category': 10,
            'classId': 2,
            'objectId': 7,
          },
        },
      ],
    },
    '${root.path}/collision.json': {
      'schemaVersion': 1,
      'meshes': [
        {
          'objectId': 1,
          'kind': 'ground',
          'vertices': [
            [0.0, 0.0, 0.0],
            [1.0, 0.0, 0.0],
            [0.0, 0.0, 1.0],
          ],
          'triangles': [
            [0, 1, 2],
          ],
        },
      ],
      'spatialRegions': <Object>[],
    },
    '${root.path}/textures/manifest.json': {
      'schemaVersion': 1,
      'textures': [
        {'name': 'stone', 'width': 2, 'height': 2},
      ],
    },
    '${root.path}/animations/manifest.json': {
      'schemaVersion': 1,
      'animations': [
        {'duration': 1.0},
      ],
      'skins': [
        {'objectId': 7},
      ],
    },
    '${root.path}/animations/bindings.json': {
      'schemaVersion': 1,
      'requiredStates': {
        'asterix': ['idle'],
      },
      'bindings': [
        {
          'actor': 'asterix',
          'skin': 4,
          'costume': 'default',
          'action': 'idle',
          'context': 'gameplay',
          'variant': null,
          'clip': '0000.animation.json',
          'loop': true,
          'priority': 0,
          'fallback': false,
          'skeletonNodes': 58,
          'transitions': <String>[],
        },
      ],
    },
    '${root.path}/animations/0000.animation.json': {
      'schemaVersion': 1,
      'duration': 1.0,
      'nodeCount': 58,
      'frames': <Object>[],
    },
    '${root.path}/animations/skin_0007.json': {
      'schemaVersion': 1,
      'objectId': 7,
      'frames': <Object>[],
      'vertices': <Object>[],
      'normals': <Object>[],
      'uvSets': <Object>[],
      'triangles': <Object>[],
      'materials': <Object>[],
      'materialSlots': <Object>[],
    },
    '${root.path}/audio.wav': Uint8List.fromList(ascii.encode('RIFFtestWAVE')),
    '${root.path}/textures/000_stone.png': Uint8List.fromList(
      img.encodePng(image),
    ),
  };
  final entries = reverseOrder
      ? files.entries.toList().reversed
      : files.entries;
  for (final entry in entries) {
    await _write(entry);
  }
}

Future<void> _write(MapEntry<String, Object> entry) async {
  final file = File(entry.key);
  if (entry.value case final Uint8List bytes) {
    await file.writeAsBytes(bytes);
  } else {
    await file.writeAsString(jsonEncode(entry.value));
  }
}
