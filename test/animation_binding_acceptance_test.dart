import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/runtime/animation_binding_registry.dart';
import 'package:asterix_xxl/tooling/animation_binding_acceptance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, Object?> manifest;
  late AnimationBindingRegistry registry;

  setUpAll(() async {
    manifest =
        jsonDecode(
              await File('assets/animation_bindings.v1.json').readAsString(),
            )
            as Map<String, Object?>;
    registry = AnimationBindingRegistry.parse(manifest);
  });

  test('every checked-in binding has a verified runtime path', () {
    final paths = animationRuntimePaths(manifest);
    final concretePaths = animationConcreteRuntimePaths(manifest);
    expect(registry.bindings, hasLength(408));
    expect(
      registry.bindings.map(bindingAcceptanceKey).toSet(),
      everyElement(isIn(paths.keys)),
    );
    expect(paths.values, everyElement(isNotEmpty));
    expect(concretePaths, hasLength(190));
    expect(
      concretePaths.values.expand((paths) => paths),
      everyElement(
        anyOf(
          startsWith('runtime-profile:asterix-player:'),
          startsWith('runtime-profile:obelix-player:'),
          startsWith('runtime-profile:idefix-player:'),
        ),
      ),
    );
    expect(
      registry.bindings.map((binding) => binding['clip']).toSet(),
      hasLength(345),
    );
  });

  test('gameplay idle uses the calm authored loop', () {
    final idle = registry.resolve(
      const AnimationBindingQuery(
        actor: 'asterix',
        skin: 4,
        costume: 'default',
        action: 'locomotion.idle',
        context: 'gameplay',
        variant: 'clip-0058',
      ),
    );
    expect(idle['clip'], '0058.animation.json');
    expect(idle['loop'], isTrue);
  });

  test('gameplay double jump uses the authored somersault', () {
    final doubleJump = registry.resolve(
      const AnimationBindingQuery(
        actor: 'asterix',
        skin: 4,
        costume: 'default',
        action: 'locomotion.airborne',
        context: 'gameplay',
        variant: 'clip-0064',
      ),
    );
    expect(doubleJump['clip'], '0064.animation.json');
    expect(doubleJump['loop'], isFalse);
  });

  test('representative visual evidence resolves exact bindings', () async {
    final evidence =
        jsonDecode(
              await File(
                'assets/animation_visual_acceptance.v1.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    expect(
      validateAnimationVisualEvidence(evidence, registry.bindings),
      isEmpty,
    );

    final invalid = Map<String, Object?>.from(evidence);
    invalid['sequences'] = [
      {
        'result': 'match',
        'originalReference': 'local reference',
        'steps': [
          {
            'actor': 'asterix',
            'action': 'unknown',
            'clip': '9999.animation.json',
          },
        ],
      },
    ];
    expect(
      validateAnimationVisualEvidence(invalid, registry.bindings),
      contains(contains('unknown binding')),
    );
  });

  test('end-to-end gate rejects an incomplete dataset and graph manifest', () {
    final incompleteManifest = Map<String, Object?>.from(manifest)
      ..remove('worldGraphVersion');
    expect(
      () => buildAnimationBindingAcceptanceReport(
        catalog: {
          'schemaVersion': 1,
          'clipCount': 0,
          'dictionaryCount': 0,
          'dictionaries': <Object?>[],
          'clips': <Object?>[],
        },
        manifest: incompleteManifest,
        visualEvidence: const {
          'schemaVersion': 1,
          'dataset': 'XXL1/LVL01',
          'sequences': <Object?>[],
        },
      ),
      throwsA(
        isA<AnimationBindingAcceptanceException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          allOf(contains('clipCount'), contains('worldGraphVersion')),
        ),
      ),
    );
  });
}
