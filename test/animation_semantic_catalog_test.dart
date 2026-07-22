import 'package:asterix_xxl/tooling/animation_semantic_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
