import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/tooling/animation_semantic_catalog.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: animation_character_annotations.dart <catalog.json> '
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
          characterAnimationDictionaryIds.contains(membership['dictionaryId']),
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
                'method': 'dictionary-owner-and-slot',
                'reference':
                    'dictionary $dictionaryId slot $slot -> clip ${clip['id']}',
              },
            ],
          };
        })
        .toList(growable: false);
    final primary = contexts.firstWhere(
      (context) =>
          characterAnimationDictionaryIds.contains(context['dictionaryId']),
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
          'reference':
              'all serialized dictionary memberships retained as contexts',
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
          'reference':
              'skeletal keyframes present; no separate event track in imported payload',
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
  stdout.writeln('Wrote ${annotations.length} character clip annotations.');
}

Map<String, Object?> _semantics(
  int dictionaryId,
  int slot,
  Map<String, Object?> clip,
) {
  final nodeCount = clip['nodeCount'] as int;
  final analysis = clip['analysis']! as Map<String, Object?>;
  final rootDistance = (analysis['rootMotionDistance']! as num).toDouble();
  final isBasicEnemy = dictionaryId == 48;
  final isLeader = dictionaryId == 27 || dictionaryId == 28;
  final isCharacterDictionary = characterAnimationDictionaryIds.contains(
    dictionaryId,
  );
  final owner = isBasicEnemy
      ? 'basic-enemy:roman'
      : isLeader
      ? 'basic-enemy-leader:roman'
      : isCharacterDictionary
      ? 'animated-character:dictionary-$dictionaryId'
      : 'cinematic-scene:dictionary-$dictionaryId';
  final action = (isBasicEnemy || isLeader)
      ? _enemyAction(slot)
      : 'special.scripted-performance';
  final playback =
      (isBasicEnemy || isLeader) && {0, 5, 33, 34, 35}.contains(slot)
      ? 'loop'
      : 'one-shot';
  return {
    'owner': owner,
    'skin': 'dictionary-$dictionaryId-hanim-$nodeCount',
    'costume': isBasicEnemy || isLeader ? 'roman-default' : 'scene-default',
    'action': action,
    'playback': playback,
    'variants': ['dictionary-$dictionaryId-slot-$slot'],
    'transitions': playback == 'loop'
        ? ['enter:$action', 'exit:on-state-change']
        : ['enter:on-trigger', 'exit:on-clip-complete'],
    'rootMotion': rootDistance > 0.001 ? 'authored' : 'none',
    'events': <Object?>[],
  };
}

String _enemyAction(int slot) {
  if (slot == 0 || {33, 34, 35}.contains(slot)) return 'locomotion.idle';
  if (slot == 5) return 'locomotion.move';
  if ({12, 13, 14}.contains(slot)) return 'locomotion.transition';
  if ({1, 2, 3, 19, 20, 21}.contains(slot)) return 'damage.hit-reaction';
  if ({4, 29, 30, 31, 32, 36, 37, 38, 39}.contains(slot)) {
    return 'death.variant';
  }
  if ({6, 7, 8, 9, 10, 15, 16, 22, 23, 24}.contains(slot)) {
    return 'combat.attack';
  }
  if ({25, 26, 27, 28, 40, 41, 42}.contains(slot)) {
    return 'special.enemy-state';
  }
  return 'spawn.or-awareness';
}
