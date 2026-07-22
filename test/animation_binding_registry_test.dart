import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/runtime/animation_binding_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> manifest() => {
    'schemaVersion': 1,
    'requiredStates': {
      'hero': ['idle'],
    },
    'bindings': [
      {
        'actor': 'hero',
        'skin': 4,
        'costume': 'default',
        'action': 'idle',
        'context': 'gameplay',
        'variant': null,
        'clip': '0001.animation.json',
        'loop': true,
        'priority': 0,
        'fallback': false,
        'skeletonNodes': 58,
        'transitions': <String>[],
      },
    ],
  };

  test('resolves an exact data-driven binding', () {
    final registry = AnimationBindingRegistry.parse(manifest());
    expect(
      registry.resolve(
        const AnimationBindingQuery(
          actor: 'hero',
          skin: 4,
          costume: 'default',
          action: 'idle',
          context: 'gameplay',
        ),
      )['clip'],
      '0001.animation.json',
    );
  });

  test('rejects unknown, ambiguous and incomplete registries', () {
    final registry = AnimationBindingRegistry.parse(manifest());
    expect(
      () => registry.resolve(
        const AnimationBindingQuery(
          actor: 'hero',
          skin: 4,
          costume: 'default',
          action: 'run',
          context: 'gameplay',
        ),
      ),
      throwsA(isA<AnimationBindingException>()),
    );
    final duplicate = manifest();
    (duplicate['bindings']! as List).add(
      Map<String, Object?>.from(
        (duplicate['bindings']! as List).first as Map<String, Object?>,
      ),
    );
    expect(
      () => AnimationBindingRegistry.parse(duplicate),
      throwsA(isA<AnimationBindingException>()),
    );
    final incomplete = manifest();
    incomplete['requiredStates'] = {
      'hero': ['death'],
    };
    expect(
      () => AnimationBindingRegistry.parse(incomplete),
      throwsA(isA<AnimationBindingException>()),
    );
  });

  test('rejects malformed phases and unreachable graph actions', () {
    final malformed = manifest();
    (malformed['bindings']! as List).first['phases'] = {
      'impact': 0.7,
      'windup': 0.2,
    };
    expect(
      () => AnimationBindingRegistry.parse(malformed),
      throwsA(isA<AnimationBindingException>()),
    );

    final unreachable = manifest();
    unreachable['graphVersion'] = 1;
    unreachable['entryStates'] = {'hero': 'idle'};
    unreachable['requiredStates'] = {
      'hero': ['idle', 'death'],
    };
    (unreachable['bindings']! as List).add({
      ...(unreachable['bindings']! as List).first as Map<String, Object?>,
      'action': 'death',
      'clip': '0002.animation.json',
    });
    expect(
      () => AnimationBindingRegistry.parse(unreachable),
      throwsA(isA<AnimationBindingException>()),
    );
  });

  test('full hero graph binds every confirmed hero clip', () async {
    final registry = AnimationBindingRegistry.parse(
      jsonDecode(
        await File('assets/animation_bindings.v1.json').readAsString(),
      ),
    );
    expect(registry.actors().toSet(), {'asterix', 'obelix', 'idefix'});
    expect(registry.heroBindings('asterix'), hasLength(97));
    expect(registry.heroBindings('obelix'), hasLength(71));
    expect(registry.heroBindings('idefix'), hasLength(22));
    expect(
      registry.bindings
          .where((binding) => binding['variant'] != null)
          .map((binding) => binding['clip'])
          .toSet(),
      hasLength(183),
    );
  });

  test(
    'hero variants, transitions and clip phases are deterministic',
    () async {
      final registry = AnimationBindingRegistry.parse(
        jsonDecode(
          await File('assets/animation_bindings.v1.json').readAsString(),
        ),
      );
      final first = registry.select(
        actor: 'asterix',
        skin: 4,
        costume: 'default',
        action: 'combat.attack-combo',
        selector: 4,
      );
      final repeated = registry.select(
        actor: 'asterix',
        skin: 4,
        costume: 'default',
        action: 'combat.attack-combo',
        selector: 4,
      );
      expect(repeated['clip'], first['clip']);
      final idle = registry.select(
        actor: 'asterix',
        skin: 4,
        costume: 'default',
        action: 'locomotion.idle',
      );
      expect(registry.allowsTransition(first, idle), isTrue);
      expect(registry.phasesCrossed(first, 0, 0.55), ['windup', 'impact']);
    },
  );

  test(
    'representative visual sequence keeps compatible skeleton palettes',
    () async {
      final registry = AnimationBindingRegistry.parse(
        jsonDecode(
          await File('assets/animation_bindings.v1.json').readAsString(),
        ),
      );
      for (final actor in const {
        'asterix': 58,
        'obelix': 58,
        'idefix': 31,
      }.entries) {
        final sequence = [
          registry.select(
            actor: actor.key,
            skin: actor.key == 'asterix'
                ? 4
                : actor.key == 'obelix'
                ? 2
                : 0,
            costume: 'default',
            action: 'locomotion.idle',
          ),
          registry.select(
            actor: actor.key,
            skin: actor.key == 'asterix'
                ? 4
                : actor.key == 'obelix'
                ? 2
                : 0,
            costume: 'default',
            action: 'locomotion.run',
          ),
          registry.select(
            actor: actor.key,
            skin: actor.key == 'asterix'
                ? 4
                : actor.key == 'obelix'
                ? 2
                : 0,
            costume: 'default',
            action: 'damage.death',
          ),
        ];
        expect(sequence.map((binding) => binding['skeletonNodes']).toSet(), {
          actor.value,
        });
        expect(registry.allowsTransition(sequence[0], sequence[1]), isTrue);
        expect(registry.allowsTransition(sequence[1], sequence[2]), isTrue);
      }
    },
  );
}
