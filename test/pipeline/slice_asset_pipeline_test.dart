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
          'render-composition',
        }),
      );
      final compositionResource = resources.singleWhere(
        (resource) => resource['kind'] == 'render-composition',
      );
      final composition =
          jsonDecode(
                utf8.decode(
                  package.payload(compositionResource['id']! as String),
                ),
              )
              as Map<String, Object?>;
      expect(composition['unexplainedSkinObjectIds'], isEmpty);
      expect(composition['skinObjectIds'], [7]);
      final composed = (composition['compositions']! as List).single as Map;
      expect(composed['actor'], 'asterix');
      expect(((composed['layers']! as List).single as Map)['skin'], 7);
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

  test('rejects an exported skin without an actor composition', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'asset-composition-unbound-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final proof = Directory('${temporary.path}/proof');
    await _writeProof(proof, reverseOrder: false);
    final bindingsFile = File('${proof.path}/animations/bindings.json');
    final bindings =
        jsonDecode(await bindingsFile.readAsString()) as Map<String, Object?>;
    ((bindings['bindings']! as List).single as Map<String, Object?>)['skin'] =
        8;
    await bindingsFile.writeAsString(jsonEncode(bindings));

    await expectLater(
      const SliceAssetPipeline().buildFromProof(proof),
      throwsA(
        isA<AssetPipelineException>()
            .having(
              (error) => error.code,
              'code',
              AssetPipelineErrorCode.invalidReference,
            )
            .having(
              (error) => error.message,
              'message',
              contains('no actor/object render composition'),
            ),
      ),
    );
  });

  test('rejects ambiguous render composition identities', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'asset-composition-ambiguous-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final proof = Directory('${temporary.path}/proof');
    await _writeProof(proof, reverseOrder: false);
    final overrides = File(
      '${proof.path}/animations/composition_overrides.json',
    );
    final entry = {
      'actor': 'asterix',
      'costume': 'default',
      'context': 'gameplay',
      'layers': [
        {'skin': 7, 'role': 'body', 'required': true},
      ],
    };
    await overrides.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'overrides': [entry, entry],
        'representatives': <Object>[],
      }),
    );

    await expectLater(
      const SliceAssetPipeline().buildFromProof(proof),
      throwsA(
        isA<AssetPipelineException>()
            .having(
              (error) => error.code,
              'code',
              AssetPipelineErrorCode.duplicateId,
            )
            .having((error) => error.message, 'message', contains('ambiguous')),
      ),
    );
  });

  test('rejects a skin repeated under different layer roles', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'asset-composition-duplicate-layer-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final proof = Directory('${temporary.path}/proof');
    await _writeProof(proof, reverseOrder: false);
    final overrides = File(
      '${proof.path}/animations/composition_overrides.json',
    );
    await overrides.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'overrides': [
          {
            'actor': 'asterix',
            'costume': 'default',
            'context': 'gameplay',
            'layers': [
              {'skin': 7, 'role': 'body', 'required': true},
              {'skin': 7, 'role': 'overlay', 'required': true},
            ],
          },
        ],
        'representatives': <Object>[],
      }),
    );

    await expectLater(
      const SliceAssetPipeline().buildFromProof(proof),
      throwsA(
        isA<AssetPipelineException>()
            .having(
              (error) => error.code,
              'code',
              AssetPipelineErrorCode.duplicateId,
            )
            .having(
              (error) => error.message,
              'message',
              contains('roles and skins must be unique'),
            ),
      ),
    );
  });

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

  test('packages the authored checkpoint binding and transform', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'asset-checkpoint-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final proof = Directory('${temporary.path}/proof');
    await _writeProof(proof, reverseOrder: false);
    await File('${proof.path}/manifest.json').writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'slice': 'gaul-stage-1',
        'sectors': [
          {'source': 'LVL001/STR01_00.KWN', 'directory': '.'},
        ],
        'outputs': {'checkpoint': 'checkpoint.json'},
      }),
    );
    final transform = <double>[
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      63.5,
      3.2,
      78.2,
      1,
    ];
    await File('${proof.path}/checkpoint.json').writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'classId': 193,
        'objectId': 0,
        'node': {'raw': 3014859, 'category': 11, 'classId': 3, 'objectId': 23},
        'nodeTransform': transform,
        'position': [63.5, 3.2, 78.2],
      }),
    );

    final package = AsterixAssetPackage.parse(
      await const SliceAssetPipeline().buildFromProof(proof),
    );
    final resource = (package.manifest['resources']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((value) => value['kind'] == 'checkpoint');
    final payload =
        jsonDecode(utf8.decode(package.payload(resource['id']! as String)))
            as Map<String, Object?>;
    expect(payload['hookClassId'], 193);
    expect(payload['position'], [63.5, 3.2, 78.2]);
    expect(payload['transform'], transform);
  });

  test(
    'packages level-local collision used by the authored checkpoint',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'asset-level-collision-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final proof = Directory('${temporary.path}/proof');
      await _writeProof(proof, reverseOrder: false);
      await File('${proof.path}/manifest.json').writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'slice': 'gaul-stage-1',
          'sectors': [
            {'source': 'LVL001/STR01_00.KWN', 'directory': '.'},
          ],
          'outputs': {'levelCollision': 'level_collision.json'},
        }),
      );
      await File('${proof.path}/level_collision.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'source': 'LVL01.KWN',
          'meshes': [
            {
              'objectId': 10,
              'kind': 'ground',
              'vertices': [
                [60.0, 2.0, 75.0],
                [67.0, 2.0, 75.0],
                [60.0, 2.0, 82.0],
              ],
              'triangles': [
                [0, 1, 2],
              ],
            },
          ],
        }),
      );

      final package = AsterixAssetPackage.parse(
        await const SliceAssetPipeline().buildFromProof(proof),
      );
      final resources = (package.manifest['resources']! as List)
          .cast<Map<String, Object?>>();
      final levelCollision = resources.singleWhere(
        (value) =>
            value['kind'] == 'collision' &&
            (value['metadata'] as Map)['scope'] == 'level-authored',
      );
      expect((levelCollision['metadata'] as Map)['meshCount'], 1);
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

  test('packages burning-house emitters without a static fallback', () async {
    final temporary = await Directory.systemTemp.createTemp('asset-fire-fx-');
    addTearDown(() => temporary.delete(recursive: true));
    final proof = Directory('${temporary.path}/proof');
    await _writeProof(proof, reverseOrder: false);
    final sceneFile = File('${proof.path}/scene.json');
    final scene =
        jsonDecode(await sceneFile.readAsString()) as Map<String, Object?>;
    (scene['nodes']! as List).add({
      'classId': 19,
      'objectId': 136,
      'transform': [
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        -13.9,
        7.65,
        -51.9,
        1.0,
      ],
      'parent': {'raw': 4294967295, 'null': true},
      'next': {'raw': 4294967295, 'null': true},
      'child': {'raw': 4294967295, 'null': true},
      'geometry': {
        'raw': 19791946,
        'category': 10,
        'classId': 1,
        'objectId': 151,
      },
      'particle': {'enabled': 2, 'mode': 1, 'rate': 1.0, 'seed': 42},
    });
    await sceneFile.writeAsString(jsonEncode(scene));

    final package = AsterixAssetPackage.parse(
      await const SliceAssetPipeline().buildFromProof(proof),
    );
    final resources = (package.manifest['resources']! as List)
        .cast<Map<String, Object?>>();
    final resource = resources.singleWhere(
      (value) => value['kind'] == 'environment-fx',
    );
    final effect =
        jsonDecode(utf8.decode(package.payload(resource['id']! as String)))
            as Map<String, Object?>;
    final emitter =
        (effect['emitters']! as List).single as Map<String, Object?>;
    expect(effect['kind'], 'burning-house-fire');
    expect(effect['loopSeconds'], 1.0);
    expect(emitter['position'], [-13.9, 7.65, -51.9]);
    expect(emitter['texture'], 'sfx_feu_flammes01');
    expect(resources.where((value) => value['kind'] == 'mesh'), hasLength(1));
  });

  test(
    'packages level-hook water surface with authored UV multipliers',
    () async {
      final temporary = await Directory.systemTemp.createTemp('asset-water-');
      addTearDown(() => temporary.delete(recursive: true));
      final proof = Directory('${temporary.path}/proof');
      await _writeProof(proof, reverseOrder: false);
      final sectorSceneFile = File('${proof.path}/scene.json');
      final sectorScene =
          jsonDecode(await sectorSceneFile.readAsString())
              as Map<String, Object?>;
      final sectorMesh =
          (sectorScene['meshes']! as List).single as Map<String, Object?>;
      sectorMesh['materials'] = [
        {'texture': 'sfx_riviere', 'uAddressing': 1, 'vAddressing': 1},
      ];
      await sectorSceneFile.writeAsString(jsonEncode(sectorScene));
      await File('${proof.path}/manifest.json').writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'slice': 'gaul-stage-1',
          'sectors': [
            {'source': 'LVL001/STR01_00.KWN', 'directory': '.'},
          ],
          'outputs': {'waterSurfaces': 'water_surfaces.json'},
        }),
      );
      await File('${proof.path}/water_surfaces.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'bindings': [
            {
              'objectId': 0,
              'uMultiplier': 0.3,
              'vMultiplier': 0.6,
              'surfaces': [
                {
                  'node': {
                    'classId': 3,
                    'objectId': 24,
                    'transform': [
                      1.0,
                      0.0,
                      0.0,
                      0.0,
                      0.0,
                      1.0,
                      0.0,
                      0.0,
                      0.0,
                      0.0,
                      1.0,
                      0.0,
                      259.84,
                      2.797,
                      128.16,
                      1.0,
                    ],
                  },
                  'mesh': {
                    'objectId': 44,
                    'frames': <Object>[],
                    'vertices': <Object>[],
                    'triangles': <Object>[],
                    'materials': [
                      {
                        'texture': 'sfx_riviere',
                        'uAddressing': 1,
                        'vAddressing': 1,
                      },
                    ],
                  },
                },
              ],
            },
          ],
        }),
      );

      final package = AsterixAssetPackage.parse(
        await const SliceAssetPipeline().buildFromProof(proof),
      );
      final resource = (package.manifest['resources']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere(
            (value) =>
                value['kind'] == 'mesh' &&
                (value['metadata'] as Map?)?['environmentKind'] ==
                    'water-surface',
          );
      final packed =
          jsonDecode(utf8.decode(package.payload(resource['id']! as String)))
              as Map<String, Object?>;
      final material = (packed['materials']! as List).single as Map;
      expect(material['waterAnimation'], {
        'mechanism': 'uv-scroll',
        'uSpeed': 0.3,
        'vSpeed': 0.6,
        'phase': 0.0,
        'clock': 'simulation-time',
        'source': 'CKHkWaterFall',
      });
      final object = (package.manifest['objects']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere(
            (value) =>
                (value['metadata'] as Map?)?['environmentKind'] ==
                'water-surface',
          );
      expect((object['metadata'] as Map)['transform'], contains(259.84));
      final sectorResource = (package.manifest['resources']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere(
            (value) =>
                value['kind'] == 'mesh' &&
                (value['metadata'] as Map?)?['environmentKind'] == null,
          );
      final packedSector =
          jsonDecode(
                utf8.decode(package.payload(sectorResource['id']! as String)),
              )
              as Map<String, Object?>;
      final sectorMaterial = (packedSector['materials']! as List).single as Map;
      expect(sectorMaterial['texture'], 'sfx_riviere');
      expect(sectorMaterial, isNot(contains('waterAnimation')));
    },
  );

  test(
    'packages authored fog volumes without a static mesh fallback',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'asset-fog-audit-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final proof = Directory('${temporary.path}/proof');
      await _writeProof(proof, reverseOrder: false);
      final sceneFile = File('${proof.path}/scene.json');
      final scene =
          jsonDecode(await sceneFile.readAsString()) as Map<String, Object?>;
      final node = (scene['nodes']! as List).single as Map<String, Object?>;
      node['classId'] = 26;
      node['fog'] = {
        'schemaVersion': 1,
        'kind': 'authored-fog-volume',
        'flags': 0,
        'matrices': [List<double>.generate(16, (i) => i % 5 == 0 ? 1 : 0)],
        'effectName': 'fog',
        'type': 1,
        'modeBytes': [0, 0, 0, 0],
        'counts': [0, 0, 0, 0],
        'origin': [0.0, 0.0, 0.0],
        'scale': 1.0,
        'coordinates': <Object>[],
        'tailBytes': [0, 0],
        'colorStops': [
          {
            'position': 0.0,
            'density': 0.5,
            'innerColor': 0xFF112233,
            'outerColor': 0xFF445566,
          },
        ],
        'vectors': <Object>[],
        'profile': [0.1, 0.2],
      };
      await sceneFile.writeAsString(jsonEncode(scene));

      final package = AsterixAssetPackage.parse(
        await const SliceAssetPipeline().buildFromProof(proof),
      );
      final object = (package.manifest['objects']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((value) => value['kind'] == 'scene-node');
      final metadata = object['metadata']! as Map;
      expect(object['payloadIds'], hasLength(1));
      expect(metadata['environmentFxMechanism'], 'fog-volume');
      expect(metadata['rendererPath'], 'Metal/authored-fog-volume');
      expect(metadata['clock'], 'simulation-time');
      final resource = (package.manifest['resources']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((value) => value['kind'] == 'fog-volume');
      expect(resource['id'], (object['payloadIds'] as List).single);
    },
  );

  test('packages authored stone push block at its level transform', () async {
    final temporary = await Directory.systemTemp.createTemp('asset-push-');
    addTearDown(() => temporary.delete(recursive: true));
    final proof = Directory('${temporary.path}/proof');
    await _writeProof(proof, reverseOrder: false);
    await File('${proof.path}/manifest.json').writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'slice': 'gaul-stage-1',
        'sectors': [
          {'source': 'LVL001/STR01_00.KWN', 'directory': '.'},
        ],
        'outputs': {'pushPull': 'push_pull.json'},
      }),
    );
    await File('${proof.path}/push_pull.json').writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'bindings': [
          {
            'objectId': 0,
            'origin': [-7.82, 3.079, -5.31],
            'axis': [0.0, 0.0, 1.0],
            'pathValues': [0.0, 11.863],
            'transform': [
              1.0,
              0.0,
              0.0,
              0.0,
              0.0,
              1.0,
              0.0,
              0.0,
              0.0,
              0.0,
              1.0,
              0.0,
              -7.82,
              3.079,
              -5.31,
              1.0,
            ],
            'visualMesh': {
              'objectId': 17,
              'frames': <Object>[],
              'vertices': <Object>[],
              'triangles': <Object>[],
              'materials': [
                {'texture': 'it_bloc2_01_mt'},
              ],
            },
          },
        ],
      }),
    );

    final package = AsterixAssetPackage.parse(
      await const SliceAssetPipeline().buildFromProof(proof),
    );
    final objects = (package.manifest['objects']! as List)
        .cast<Map<String, Object?>>();
    final block = objects.singleWhere(
      (value) =>
          (value['metadata'] as Map?)?['interactiveKind'] == 'push-pull-stone',
    );
    final metadata = block['metadata']! as Map<String, Object?>;
    expect(
      metadata['transform'],
      containsAllInOrder([-7.82, 3.079, -5.31, 1.0]),
    );
    expect(metadata['axis'], [0.0, 0.0, 1.0]);
    expect(metadata['maximumOffset'], 11.863);
    final resource = (package.manifest['resources']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere(
          (value) =>
              (value['metadata'] as Map?)?['interactiveKind'] ==
              'push-pull-stone',
        );
    final mesh =
        jsonDecode(utf8.decode(package.payload(resource['id']! as String)))
            as Map<String, Object?>;
    expect(
      ((mesh['materials']! as List).single as Map)['texture'],
      'it_bloc2_01_mt',
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
          'skin': 7,
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
    '${root.path}/animations/asterix.authored-graph.v1.json': {
      'schemaVersion': 1,
      'resourceType': 'asterix.authored-animation-graph',
      'profile': {'id': 'actor:CKHkAsterix'},
      'entryState': 'binding:idle',
      'states': [
        {
          'id': 'binding:idle',
          'binding': 'idle',
          'clip': {'dictionary': 0, 'slot': 0, 'asset': 'clip-0000'},
        },
      ],
      'transitions': [
        {'id': 'select:idle', 'fromState': '*', 'toState': 'binding:idle'},
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
      'skin': {
        'boneCount': 58,
        'vertexBoneIndices': <Object>[],
        'vertexWeights': <Object>[],
      },
    },
    '${root.path}/animations/composition_overrides.json': {
      'schemaVersion': 1,
      'overrides': <Object>[],
      'representatives': <Object>[],
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
