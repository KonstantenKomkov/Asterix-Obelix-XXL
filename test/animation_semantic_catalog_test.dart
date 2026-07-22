import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/tooling/animation_semantic_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('world scope contains mechanisms, fauna, interface and FX only', () {
    expect(
      worldAnimationDictionaryIds,
      equals({19, 20, 21, 22, 23, 24, 25, 26, 29, 30, 49, 50, 51}),
    );
    expect(worldAnimationDictionaryIds, isNot(contains(27)));
    expect(worldAnimationDictionaryIds, isNot(contains(3)));
  });

  test('character scope contains enemy, leader and NPC dictionaries only', () {
    expect(characterAnimationDictionaryIds, containsAll([4, 27, 28, 48]));
    expect(
      characterAnimationDictionaryIds,
      containsAll(List.generate(17, (i) => i + 31)),
    );
    expect(characterAnimationDictionaryIds, isNot(contains(30)));
    expect(characterAnimationDictionaryIds, isNot(contains(49)));
    expect(characterAnimationDictionaryIds, hasLength(25));
  });

  test('catalog measures root motion from the animated HAnim root', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'asterix-animation-catalog-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final inventory = File('${temporary.path}/inventory.json');
    await inventory.writeAsString(
      jsonEncode({
        'source': 'fixture',
        'clipCount': 1,
        'dictionaryCount': 1,
        'dictionaries': [
          {
            'objectId': 2,
            'slots': [0],
          },
        ],
        'dictionaryOwnerReferences': [
          {
            'dictionaryObjectId': 2,
            'ownerClass': 'CKHkAsterix',
            'sourceObjectId': 0,
            'field': 'heroAnimDict',
            'referenceKind': 'typed-field',
            'evidence': 'fixture',
          },
        ],
      }),
    );
    List<double> transform(double x, double y, double z) => [
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
      x,
      y,
      z,
      1,
    ];
    await File('${temporary.path}/0000.animation.json').writeAsString(
      jsonEncode({
        'nodeCount': 2,
        'duration': 1.0,
        'frameCount': 4,
        'samples': [
          {
            'localTransforms': [transform(100, 0, 0), transform(1, 2, 3)],
          },
          {
            'localTransforms': [transform(200, 0, 0), transform(4, 6, 3)],
          },
        ],
      }),
    );

    final catalog = await buildAnimationCatalogDraft(
      inventoryFile: inventory,
      animationsDirectory: temporary,
    );
    final clip = (catalog['clips']! as List).single as Map;
    final analysis = clip['analysis'] as Map;

    expect(analysis['motionRootNodeIndex'], 1);
    expect(analysis['rootTranslationDelta'], [3.0, 4.0, 0.0]);
    expect(analysis['rootMotionDistance'], 5.0);
  });

  test('semantic validator rejects unreviewed and evidence-free clips', () {
    final catalog = <String, Object?>{
      'schemaVersion': 1,
      'clipCount': 1,
      'dictionaries': [
        {
          'objectId': 2,
          'slots': [0],
        },
      ],
      'clips': [
        <String, Object?>{
          'id': '0000',
          'managerIndex': 0,
          'dictionaryMemberships': [
            {'dictionaryId': 2, 'slot': 0},
          ],
          'ownerCandidates': [
            {'ownerClass': 'CKHkAsterix'},
          ],
          'status': 'unreviewed',
          'owner': null,
          'skin': null,
          'costume': null,
          'action': null,
          'playback': null,
          'variants': <Object?>[],
          'transitions': <Object?>[],
          'rootMotion': null,
          'events': <Object?>[],
          'evidence': <Object?>[],
        },
      ],
    };

    final issues = validateAnimationSemanticCatalog(catalog);

    expect(issues, isNotEmpty);
    expect(issues.map((issue) => issue.path), contains('clips[0].status'));
    expect(issues.map((issue) => issue.path), contains('clips[0].action'));
    expect(issues.map((issue) => issue.path), contains('clips[0].evidence'));
    expect(issues.map((issue) => issue.path), contains('clips[0].contexts'));
  });

  test('semantic validator accepts a fully classified clip', () {
    final catalog = <String, Object?>{
      'schemaVersion': 1,
      'clipCount': 1,
      'dictionaries': [
        {
          'objectId': 2,
          'slots': [0],
        },
      ],
      'clips': [
        <String, Object?>{
          'id': '0000',
          'managerIndex': 0,
          'dictionaryMemberships': [
            {'dictionaryId': 2, 'slot': 0},
          ],
          'ownerCandidates': [
            {'ownerClass': 'CKHkAsterix'},
          ],
          'status': 'confirmed',
          'owner': 'asterix',
          'skin': 'asterix',
          'costume': 'default',
          'action': 'attack.combo_1',
          'playback': 'one-shot',
          'variants': <Object?>[],
          'transitions': <Object?>[],
          'rootMotion': 'none',
          'events': <Object?>[],
          'evidence': [
            {'method': 'runtime-observation', 'reference': 'task-62/0000'},
          ],
          'contexts': [
            {
              'dictionaryId': 2,
              'slot': 0,
              'owner': 'asterix',
              'skin': 'asterix',
              'costume': 'default',
              'action': 'attack.combo_1',
              'playback': 'one-shot',
              'rootMotion': 'none',
              'variants': <Object?>[],
              'transitions': <Object?>[],
              'events': <Object?>[],
              'evidence': <Object?>[],
            },
          ],
        },
      ],
    };

    expect(validateAnimationSemanticCatalog(catalog), isEmpty);
  });

  test('dictionary validation requires only the selected owner catalog', () {
    Map<String, Object?> clip(
      int index,
      int dictionaryId, {
      required String status,
    }) => <String, Object?>{
      'id': index.toString().padLeft(4, '0'),
      'managerIndex': index,
      'dictionaryMemberships': [
        {'dictionaryId': dictionaryId, 'slot': 0},
      ],
      'ownerCandidates': [
        {'ownerClass': dictionaryId == 2 ? 'CKHkAsterix' : 'CKHkObelix'},
      ],
      'status': status,
      'owner': status == 'confirmed' ? 'asterix' : null,
      'skin': status == 'confirmed' ? 'asterix-default' : null,
      'costume': status == 'confirmed' ? 'default' : null,
      'action': status == 'confirmed' ? 'locomotion.idle' : null,
      'playback': status == 'confirmed' ? 'loop' : null,
      'variants': <Object?>[],
      'transitions': <Object?>[],
      'rootMotion': status == 'confirmed' ? 'none' : null,
      'events': <Object?>[],
      'evidence': status == 'confirmed'
          ? <Object?>[
              {'method': 'fixture-review', 'reference': 'clip-$index'},
            ]
          : <Object?>[],
      'contexts': status == 'confirmed'
          ? <Object?>[
              {
                'dictionaryId': dictionaryId,
                'slot': 0,
                'owner': 'asterix',
                'skin': 'asterix-default',
                'costume': 'default',
                'action': 'locomotion.idle',
                'playback': 'loop',
                'rootMotion': 'none',
                'variants': <Object?>[],
                'transitions': <Object?>[],
                'events': <Object?>[],
                'evidence': <Object?>[],
              },
            ]
          : <Object?>[],
    };
    final catalog = <String, Object?>{
      'schemaVersion': 1,
      'clipCount': 2,
      'dictionaries': [
        {
          'objectId': 2,
          'slots': [0],
        },
        {
          'objectId': 1,
          'slots': [1],
        },
      ],
      'clips': [
        clip(0, 2, status: 'confirmed'),
        clip(1, 1, status: 'unreviewed'),
      ],
    };

    expect(
      validateAnimationSemanticCatalog(catalog, requiredDictionaryIds: {2}),
      isEmpty,
    );
    expect(validateAnimationSemanticCatalog(catalog), isNotEmpty);
    expect(
      validateAnimationSemanticCatalog(
        catalog,
        requiredDictionaryIds: {99},
      ).map((issue) => issue.message),
      contains('does not contain requested dictionary 99'),
    );
  });

  test('semantic validator rejects ambiguous playback policy', () {
    final catalog = <String, Object?>{
      'schemaVersion': 1,
      'clipCount': 1,
      'dictionaries': [
        {
          'objectId': 2,
          'slots': [0],
        },
      ],
      'clips': [
        <String, Object?>{
          'id': '0000',
          'managerIndex': 0,
          'dictionaryMemberships': [
            {'dictionaryId': 2, 'slot': 0},
          ],
          'ownerCandidates': [
            {'ownerClass': 'CKHkAsterix'},
          ],
          'status': 'confirmed',
          'owner': 'asterix',
          'skin': 'asterix',
          'costume': 'default',
          'action': 'attack.combo_1',
          'playback': 'unknown',
          'variants': <Object?>[],
          'transitions': <Object?>[],
          'rootMotion': 'none',
          'events': <Object?>[],
          'evidence': [
            {'method': 'runtime-observation', 'reference': 'task-62/0000'},
          ],
        },
      ],
    };

    expect(
      validateAnimationSemanticCatalog(catalog).map((issue) => issue.path),
      contains('clips[0].playback'),
    );
  });

  test('semantic validator requires a context for every dictionary slot', () {
    final catalog = <String, Object?>{
      'schemaVersion': 1,
      'clipCount': 1,
      'dictionaries': [
        {
          'objectId': 2,
          'slots': [0, 0],
        },
      ],
      'clips': [
        <String, Object?>{
          'id': '0000',
          'managerIndex': 0,
          'dictionaryMemberships': [
            {'dictionaryId': 2, 'slot': 0},
            {'dictionaryId': 2, 'slot': 1},
          ],
          'ownerCandidates': [
            {'ownerClass': 'CKHkAsterix'},
          ],
          'status': 'confirmed',
          'owner': 'asterix',
          'skin': 'asterix',
          'costume': 'default',
          'action': 'idle',
          'playback': 'loop',
          'variants': <Object?>[],
          'transitions': <Object?>[],
          'rootMotion': 'none',
          'events': <Object?>[],
          'evidence': [
            {'method': 'runtime-observation', 'reference': 'task-62/0000'},
          ],
          'contexts': [
            {
              'dictionaryId': 2,
              'slot': 0,
              'owner': 'asterix',
              'skin': 'asterix',
              'costume': 'default',
              'action': 'idle',
              'playback': 'loop',
              'rootMotion': 'none',
              'variants': <Object?>[],
              'transitions': <Object?>[],
              'events': <Object?>[],
              'evidence': <Object?>[],
            },
          ],
        },
      ],
    };

    expect(
      validateAnimationSemanticCatalog(
        catalog,
      ).map((issue) => '${issue.path}: ${issue.message}'),
      contains(
        'clips[0].contexts: must cover every dictionary membership exactly once',
      ),
    );
  });

  test('semantic validator rejects malformed identity and semantic types', () {
    final catalog = <String, Object?>{
      'schemaVersion': 1,
      'clipCount': 1,
      'dictionaries': [
        {
          'objectId': 2,
          'slots': [0],
        },
      ],
      'clips': [
        <String, Object?>{
          'id': '0042',
          'managerIndex': 42,
          'dictionaryMemberships': [
            {'dictionaryId': 2, 'slot': 0},
          ],
          'ownerCandidates': [
            {'ownerClass': 'CKHkAsterix'},
          ],
          'status': 'confirmed',
          'owner': 1,
          'skin': 'asterix',
          'costume': 'default',
          'action': 'idle',
          'playback': 'loop',
          'variants': <Object?>[],
          'transitions': <Object?>[],
          'rootMotion': 'none',
          'events': <Object?>[],
          'evidence': [
            {'method': ' ', 'reference': 'task-62/0042'},
          ],
        },
      ],
    };

    final paths = validateAnimationSemanticCatalog(
      catalog,
    ).map((issue) => issue.path);
    expect(paths, contains('clips[0].id'));
    expect(paths, contains('clips[0].managerIndex'));
    expect(paths, contains('clips[0].owner'));
    expect(paths, contains('clips[0].evidence[0]'));
  });

  test('semantic validator rejects a fabricated dictionary membership', () {
    final catalog = <String, Object?>{
      'schemaVersion': 1,
      'clipCount': 1,
      'dictionaries': [
        {
          'objectId': 2,
          'slots': [0],
        },
      ],
      'clips': [
        <String, Object?>{
          'id': '0000',
          'managerIndex': 0,
          'dictionaryMemberships': [
            {'dictionaryId': 2, 'slot': 1},
          ],
          'ownerCandidates': [
            {'ownerClass': 'CKHkAsterix'},
          ],
          'status': 'unreviewed',
        },
      ],
    };

    expect(
      validateAnimationSemanticCatalog(
        catalog,
        requireConfirmed: false,
      ).map((issue) => issue.path),
      contains('clips[0].dictionaryMemberships[0]'),
    );
  });

  test('annotations update only semantic fields', () {
    final catalog = <String, Object?>{
      'clips': [
        <String, Object?>{
          'id': '0000',
          'managerIndex': 0,
          'status': 'unreviewed',
        },
      ],
    };
    final result = applyAnimationCatalogAnnotations(catalog, {
      'schemaVersion': 1,
      'clips': [
        {'id': '0000', 'status': 'provisional', 'action': 'attack'},
      ],
    });
    final clip = (result['clips']! as List).single as Map;
    expect(clip['status'], 'provisional');
    expect(clip['action'], 'attack');
    expect(clip['managerIndex'], 0);
    expect((catalog['clips']! as List).single['status'], 'unreviewed');
  });

  test('annotations reject objective field changes and duplicate ids', () {
    final catalog = <String, Object?>{
      'clips': [
        <String, Object?>{'id': '0000', 'managerIndex': 0},
      ],
    };
    expect(
      () => applyAnimationCatalogAnnotations(catalog, {
        'schemaVersion': 1,
        'clips': [
          {'id': '0000', 'managerIndex': 42},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => applyAnimationCatalogAnnotations(catalog, {
        'schemaVersion': 1,
        'clips': [
          {'id': '0000'},
          {'id': '0000'},
        ],
      }),
      throwsFormatException,
    );
  });
}
