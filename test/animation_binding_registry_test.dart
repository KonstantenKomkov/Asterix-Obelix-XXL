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

  test('validates versioned typed animation event tracks', () {
    final value = manifest()
      ..['eventTrackVersion'] = 1
      ..['eventTracks'] = [
        {
          'id': 'hero.idle',
          'actor': 'hero',
          'action': 'idle',
          'context': 'gameplay',
          'loop': true,
          'events': [
            {
              'id': 'cue',
              'phase': .5,
              'type': 'sfx',
              'target': 'hero',
              'value': 'idle.cue',
            },
          ],
        },
      ];
    expect(
      AnimationBindingRegistry.parse(value).manifest['eventTrackVersion'],
      1,
    );
    final malformed = Map<String, Object?>.from(value);
    malformed['eventTracks'] = [
      {
        ...(value['eventTracks']! as List).first as Map<String, Object?>,
        'loop': false,
      },
    ];
    expect(
      () => AnimationBindingRegistry.parse(malformed),
      throwsA(isA<AnimationBindingException>()),
    );
  });

  test('full hero graph binds every confirmed hero clip', () async {
    final registry = AnimationBindingRegistry.parse(
      jsonDecode(
        await File('assets/animation_bindings.v1.json').readAsString(),
      ),
    );
    expect(
      registry.actors().toSet(),
      containsAll({'asterix', 'obelix', 'idefix'}),
    );
    expect(registry.heroBindings('asterix'), hasLength(97));
    expect(registry.heroBindings('obelix'), hasLength(71));
    expect(registry.heroBindings('idefix'), hasLength(22));
    expect(
      registry.bindings
          .where(
            (binding) =>
                {'asterix', 'obelix', 'idefix'}.contains(binding['actor']) &&
                binding['context'] == 'gameplay' &&
                binding['variant'] != null,
          )
          .map((binding) => binding['clip'])
          .toSet(),
      hasLength(183),
    );
  });

  test('character graph covers every confirmed character context', () async {
    final decoded =
        jsonDecode(
              await File('assets/animation_bindings.v1.json').readAsString(),
            )
            as Map<String, Object?>;
    final registry = AnimationBindingRegistry.parse(decoded);
    expect(decoded['characterGraphVersion'], 1);
    expect(decoded['characterCatalog'], {'clipCount': 92, 'contextCount': 109});
    expect(decoded['characterProfiles'], hasLength(27));
    final profiles = (decoded['characterProfiles']! as List)
        .cast<Map<String, Object?>>();
    for (final profile in profiles) {
      final bindings = registry.profileBindings(
        actor: profile['actor']! as String,
        skin: profile['skin']! as int,
        costume: profile['costume']! as String,
        context: profile['context']! as String,
      );
      expect(bindings, isNotEmpty);
      expect(
        bindings.map((binding) => binding['skeletonNodes']).toSet(),
        hasLength(1),
      );
      expect(
        bindings.map((binding) => binding['action']).toSet(),
        containsAll(profile['requiredStates']! as List),
      );
    }
  });

  test('world graph covers every world event context and clip', () async {
    final decoded =
        jsonDecode(
              await File('assets/animation_bindings.v1.json').readAsString(),
            )
            as Map<String, Object?>;
    final registry = AnimationBindingRegistry.parse(decoded);
    expect(decoded['worldGraphVersion'], 1);
    expect(decoded['worldCatalog'], {'clipCount': 45, 'contextCount': 46});
    final profiles = (decoded['worldProfiles']! as List)
        .cast<Map<String, Object?>>();
    expect(profiles, hasLength(13));
    final clips = <Object?>{};
    var contexts = 0;
    for (final profile in profiles) {
      final bindings = registry.profileBindings(
        actor: profile['actor']! as String,
        skin: profile['skin']! as int,
        costume: profile['costume']! as String,
        context: 'world',
      );
      expect(bindings, isNotEmpty);
      expect(
        bindings.map((binding) => binding['action']).toSet(),
        containsAll(profile['requiredStates']! as List),
      );
      expect(
        bindings.every(
          (binding) =>
              binding['trigger'] is String &&
              (binding['trigger']! as String).isNotEmpty,
        ),
        isTrue,
      );
      contexts += bindings.length;
      clips.addAll(bindings.map((binding) => binding['clip']));
    }
    expect(contexts, 46);
    expect(clips, hasLength(45));
  });

  test('cinematic timelines bind every scene-data cue and clip', () async {
    final decoded =
        jsonDecode(
              await File('assets/animation_bindings.v1.json').readAsString(),
            )
            as Map<String, Object?>;
    final registry = AnimationBindingRegistry.parse(decoded);
    expect(decoded['cinematicGraphVersion'], 1);
    expect(decoded['cinematicCatalog'], {
      'clipCount': 44,
      'contextCount': 63,
      'timelineCount': 14,
    });
    final timelines = (decoded['cinematicTimelines']! as List)
        .cast<Map<String, Object?>>();
    expect(timelines, hasLength(14));
    final clips = <Object?>{};
    var contexts = 0;
    for (final timeline in timelines) {
      expect((timeline['cues']! as List).map((cue) => cue['type']).toSet(), {
        'camera',
        'audio',
        'subtitle',
      });
      for (final track
          in (timeline['tracks']! as List).cast<Map<String, Object?>>()) {
        final binding = registry.resolve(
          AnimationBindingQuery(
            actor: track['actor']! as String,
            skin: track['dictionaryId']! as int,
            costume: 'scene-${(timeline['id']! as String).substring(11)}',
            action: track['action']! as String,
            context: 'cinematic',
            variant:
                'dictionary-${track['dictionaryId']}-slot-${track['slot']}',
          ),
        );
        expect(binding['timeline'], timeline['id']);
        clips.add(binding['clip']);
        contexts++;
      }
    }
    expect(contexts, 63);
    expect(clips, hasLength(44));
  });

  test('cinematic graph rejects a cue without an exact event binding', () {
    final value = manifest();
    value.addAll({
      'cinematicGraphVersion': 1,
      'cinematicCatalog': {
        'clipCount': 1,
        'contextCount': 1,
        'timelineCount': 1,
      },
      'cinematicTimelines': [
        {
          'id': 'scene-data-1',
          'scriptEvent': 'script.scene-1',
          'kind': 'in-game',
          'reentryPolicy': 'resume-checkpoint-or-restart-after-interrupt',
          'skipPolicy': 'apply-terminal-state',
          'interruptPolicy': 'checkpoint-current-cue',
          'controlPolicy': 'lock-on-start-return-on-terminal',
          'terminalCue': 0,
          'cues': [
            {'type': 'camera'},
            {'type': 'audio'},
            {'type': 'subtitle'},
          ],
          'tracks': [
            {
              'actor': 'hero',
              'dictionaryId': 4,
              'slot': 0,
              'action': 'performance',
              'cueIndex': 0,
            },
          ],
        },
      ],
    });
    expect(
      () => AnimationBindingRegistry.parse(value),
      throwsA(isA<AnimationBindingException>()),
    );
  });

  test(
    'world graph rejects an unbound event and a cross-profile transition',
    () {
      final value = manifest();
      value.addAll({
        'worldGraphVersion': 1,
        'worldCatalog': {'clipCount': 1, 'contextCount': 1},
        'worldProfiles': [
          {
            'actor': 'lever',
            'skin': 22,
            'skinProfile': 'lever-hanim-1',
            'costume': 'default',
            'context': 'world',
            'entryState': 'idle',
            'requiredStates': ['idle'],
            'eventBindings': {'activate': 'missing'},
            'restorePolicy': 'snapshot-without-replay',
          },
        ],
      });
      (value['bindings']! as List).add({
        ...(value['bindings']! as List).first as Map<String, Object?>,
        'actor': 'lever',
        'skin': 22,
        'context': 'world',
        'action': 'idle',
        'clip': '0002.animation.json',
        'transitions': ['foreign'],
      });
      expect(
        () => AnimationBindingRegistry.parse(value),
        throwsA(isA<AnimationBindingException>()),
      );

      final missingTrigger = jsonDecode(jsonEncode(value));
      final worldBinding = (missingTrigger['bindings']! as List).last;
      (worldBinding as Map<String, Object?>)
        ..['transitions'] = <String>[]
        ..remove('trigger');
      ((missingTrigger['worldProfiles']! as List).first
          as Map<String, Object?>)['eventBindings'] = {
        'idle': 'idle',
      };
      expect(
        () => AnimationBindingRegistry.parse(missingTrigger),
        throwsA(isA<AnimationBindingException>()),
      );
    },
  );

  test('enemy variants and gameplay phases are deterministic', () async {
    final registry = AnimationBindingRegistry.parse(
      jsonDecode(
        await File('assets/animation_bindings.v1.json').readAsString(),
      ),
    );
    final attack = registry.select(
      actor: 'basic-enemy:roman',
      skin: 48,
      costume: 'roman-default',
      action: 'combat.attack',
      selector: 7,
    );
    expect(
      registry.select(
        actor: 'basic-enemy:roman',
        skin: 48,
        costume: 'roman-default',
        action: 'combat.attack',
        selector: 7,
      )['clip'],
      attack['clip'],
    );
    final impact =
        (attack['phases']! as Map<String, Object?>)['impact']! as num;
    expect(impact.toDouble(), closeTo(0.25 / 0.65, 1e-12));
    expect(registry.phasesCrossed(attack, 0, impact.toDouble()), [
      'windup',
      'impact',
    ]);
    final death = registry.select(
      actor: 'basic-enemy:roman',
      skin: 48,
      costume: 'roman-default',
      action: 'death.variant',
    );
    expect(death['transitions'], isEmpty);
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
