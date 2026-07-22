import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/tooling/animation_semantic_catalog.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: animation_cinematic_annotations.dart <catalog.json> '
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
      (item) => cinematicAnimationDictionaryIds.contains(item['dictionaryId']),
    )) {
      continue;
    }
    final existingContexts = (clip['contexts'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    final existingByMembership = {
      for (final context in existingContexts)
        (context['dictionaryId'] as int, context['slot'] as int): context,
    };
    final contexts = memberships
        .map((membership) {
          final dictionaryId = membership['dictionaryId']! as int;
          final slot = membership['slot']! as int;
          if (!cinematicAnimationDictionaryIds.contains(dictionaryId)) {
            final existing = existingByMembership[(dictionaryId, slot)];
            if (existing == null) {
              throw StateError(
                'Clip ${clip['id']} has an unreviewed non-cinematic membership '
                '$dictionaryId:$slot.',
              );
            }
            return existing;
          }
          return _cinematicContext(dictionaryId, slot, clip);
        })
        .toList(growable: false);
    final primary = contexts.firstWhere(
      (context) =>
          cinematicAnimationDictionaryIds.contains(context['dictionaryId']),
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
          'method': 'typed-cinematic-scene-data-reference',
          'reference':
              'all CKCinematicSceneData dictionary memberships retained',
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
          'reference': 'skeletal keyframes present; no authored event track',
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
  stdout.writeln('Wrote ${annotations.length} cinematic clip annotations.');
}

Map<String, Object?> _cinematicContext(
  int dictionaryId,
  int slot,
  Map<String, Object?> clip,
) {
  final profile = _profiles[dictionaryId]!;
  final analysis = clip['analysis']! as Map<String, Object?>;
  final rootDistance = (analysis['rootMotionDistance']! as num).toDouble();
  final sceneDataId = profile.sceneDataObjectId;
  return {
    'dictionaryId': dictionaryId,
    'slot': slot,
    'owner': profile.actor,
    'skin': '${profile.actor}-hanim-${clip['nodeCount']}',
    'costume': 'scene-$sceneDataId',
    'action': 'cinematic.scene-$sceneDataId.performance',
    'playback': 'one-shot',
    'variants': ['dictionary-$dictionaryId-slot-$slot'],
    'transitions': ['enter:on-timeline-cue', 'exit:on-timeline-advance'],
    'rootMotion': rootDistance > 0.001 ? 'authored' : 'none',
    'events': <Object?>[],
    'evidence': [
      {
        'method': 'typed-scene-data-owner',
        'reference':
            'CKCinematicSceneData:$sceneDataId animDict -> dictionary $dictionaryId',
      },
      {
        'method': 'timeline-dictionary-slot',
        'reference':
            'scene-data $sceneDataId dictionary $dictionaryId slot $slot -> clip ${clip['id']}',
      },
      {
        'method': 'actor-profile-and-pose-review',
        'reference': '${profile.actor}; HAnim node count ${clip['nodeCount']}',
      },
    ],
  };
}

final class _CinematicProfile {
  const _CinematicProfile(this.sceneDataObjectId, this.actor);

  final int sceneDataObjectId;
  final String actor;
}

const _profiles = <int, _CinematicProfile>{
  3: _CinematicProfile(0, 'cinematic-actor:scene-data-0'),
  5: _CinematicProfile(1, 'asterix'),
  6: _CinematicProfile(2, 'obelix'),
  7: _CinematicProfile(3, 'animated-character:dictionary-7'),
  8: _CinematicProfile(4, 'idefix'),
  9: _CinematicProfile(5, 'animated-character:dictionary-9'),
  10: _CinematicProfile(6, 'animated-character:dictionary-10'),
  11: _CinematicProfile(7, 'obelix'),
  12: _CinematicProfile(8, 'asterix'),
  13: _CinematicProfile(9, 'obelix'),
  14: _CinematicProfile(10, 'asterix'),
  15: _CinematicProfile(11, 'cinematic-actor:scene-data-11'),
  16: _CinematicProfile(12, 'cinematic-prop:scene-data-12'),
  18: _CinematicProfile(13, 'idefix'),
};
