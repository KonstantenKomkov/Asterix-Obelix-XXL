import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/tooling/animation_semantic_catalog.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: animation_world_annotations.dart <catalog.json> '
      '<annotations.json>',
    );
    exitCode = 64;
    return;
  }
  final catalog =
      jsonDecode(await File(arguments[0]).readAsString())
          as Map<String, Object?>;
  final annotations = <Map<String, Object?>>[];
  for (final raw in catalog['clips']! as List<Object?>) {
    final clip = raw! as Map<String, Object?>;
    final memberships = (clip['dictionaryMemberships']! as List<Object?>)
        .cast<Map<String, Object?>>();
    if (!memberships.any(
      (membership) =>
          worldAnimationDictionaryIds.contains(membership['dictionaryId']),
    )) {
      continue;
    }
    final contexts = memberships
        .map((membership) {
          final dictionaryId = membership['dictionaryId']! as int;
          final slot = membership['slot']! as int;
          final semantics = _semantics(dictionaryId, slot, clip);
          return <String, Object?>{
            'dictionaryId': dictionaryId,
            'slot': slot,
            ...semantics,
            'evidence': [
              {
                'method': 'typed-owner-and-slot',
                'reference':
                    'dictionary $dictionaryId slot $slot -> clip ${clip['id']}',
              },
            ],
          };
        })
        .toList(growable: false);
    final primary = contexts.firstWhere(
      (context) =>
          worldAnimationDictionaryIds.contains(context['dictionaryId']),
    );
    final analysis = clip['analysis']! as Map<String, Object?>;
    final rootDistance = (analysis['rootMotionDistance']! as num).toDouble();
    annotations.add({
      'id': clip['id'],
      'status': 'confirmed',
      for (final field in [
        'owner',
        'skin',
        'costume',
        'action',
        'playback',
        'variants',
        'transitions',
        'rootMotion',
        'events',
      ])
        field: primary[field],
      'evidence': [
        {
          'method': 'typed-owner-reference',
          'reference': 'all serialized dictionary memberships retained',
        },
        {
          'method': 'seven-pose-skeleton-review',
          'reference':
              'clip ${clip['id']} front/side review at 0, 1/6 ... 1 duration',
        },
        {
          'method': 'motion-root-transform-analysis',
          'reference':
              'clip ${clip['id']} node 1 displacement ${rootDistance.toStringAsFixed(6)}',
        },
        {
          'method': 'imported-track-structure-review',
          'reference': 'no separate event track in imported animation payload',
        },
      ],
      'contexts': contexts,
    });
  }
  final output = File(arguments[1]);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'clips': annotations})}\n',
    flush: true,
  );
  stdout.writeln('Wrote ${annotations.length} world clip annotations.');
}

Map<String, Object?> _semantics(
  int dictionaryId,
  int slot,
  Map<String, Object?> clip,
) {
  final analysis = clip['analysis']! as Map<String, Object?>;
  final rootDistance = (analysis['rootMotionDistance']! as num).toDouble();
  final profile = _profiles[dictionaryId];
  if (profile == null) {
    throw StateError('Dictionary $dictionaryId is outside world scope.');
  }
  final action = profile.actions[slot];
  if (action == null) {
    throw StateError('No semantics for dictionary $dictionaryId slot $slot.');
  }
  final playback = profile.loopSlots.contains(slot) ? 'loop' : 'one-shot';
  return {
    'owner': profile.owner,
    'skin': '${profile.owner}-hanim-${clip['nodeCount']}',
    'costume': 'default',
    'action': action,
    'playback': playback,
    'variants': ['dictionary-$dictionaryId-slot-$slot'],
    'transitions': playback == 'loop'
        ? ['enter:$action', 'exit:on-world-state-change']
        : ['enter:on-world-event', 'exit:on-clip-complete'],
    'rootMotion': rootDistance > 0.001 ? 'authored' : 'none',
    // The imported RwAnimAnimation payload has skeletal keyframes only. An
    // empty list explicitly records that no authored event track exists.
    'events': <Object?>[],
  };
}

final class _WorldProfile {
  const _WorldProfile(this.owner, this.actions, {this.loopSlots = const {}});

  final String owner;
  final Map<int, String> actions;
  final Set<int> loopSlots;
}

const _profiles = <int, _WorldProfile>{
  19: _WorldProfile('mechanism:machinegun', {
    0: 'combat.fire',
    1: 'combat.recoil',
  }),
  20: _WorldProfile(
    'shop:asterix-kiosk',
    {
      0: 'shop.idle',
      1: 'shop.transaction',
      2: 'shop.close',
      3: 'shop.open',
      4: 'shop.transaction',
    },
    loopSlots: {0},
  ),
  21: _WorldProfile(
    'shop:asterix-counter',
    {
      0: 'shop.idle',
      1: 'shop.offer',
      2: 'shop.close',
      3: 'shop.open',
      4: 'shop.transaction',
    },
    loopSlots: {0, 1},
  ),
  22: _WorldProfile('activator:world-switch', {0: 'activator.activate'}),
  23: _WorldProfile(
    'mechanism:component',
    {
      0: 'mechanism.idle',
      1: 'mechanism.activate',
      2: 'mechanism.deactivate',
      3: 'mechanism.active-loop',
      4: 'mechanism.forward',
      5: 'mechanism.reverse',
      6: 'mechanism.transition-a',
      7: 'mechanism.transition-b',
      8: 'mechanism.transition-c',
      9: 'mechanism.start',
      10: 'mechanism.stop',
      11: 'mechanism.reset',
    },
    loopSlots: {0, 3},
  ),
  24: _WorldProfile(
    'fauna:square-turtle-a',
    {
      0: 'fauna.idle',
      1: 'fauna.move',
      2: 'fauna.turn-left',
      3: 'fauna.turn-right',
      4: 'fauna.react',
      5: 'fauna.hide',
    },
    loopSlots: {0, 1},
  ),
  25: _WorldProfile(
    'fauna:square-turtle-b',
    {0: 'fauna.idle', 1: 'fauna.move', 2: 'fauna.react'},
    loopSlots: {0, 1},
  ),
  26: _WorldProfile(
    'fauna:square-turtle-c',
    {0: 'fauna.idle', 1: 'fauna.move', 2: 'fauna.react'},
    loopSlots: {0, 1},
  ),
  29: _WorldProfile(
    'checkpoint:asterix',
    {0: 'checkpoint.idle', 1: 'checkpoint.activate', 2: 'checkpoint.activated'},
    loopSlots: {0, 2},
  ),
  30: _WorldProfile(
    'fauna:wild-boar',
    {0: 'fauna.idle', 1: 'fauna.attack', 2: 'fauna.hit-reaction'},
    loopSlots: {0},
  ),
  49: _WorldProfile(
    'fx:lightning-object-node',
    {0: 'fx.lightning-loop'},
    loopSlots: {0},
  ),
  50: _WorldProfile('interface:in-game-primary', {0: 'interface.transition'}),
  51: _WorldProfile('interface:in-game-secondary', {0: 'interface.transition'}),
};
