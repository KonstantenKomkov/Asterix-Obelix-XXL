import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: animation_cinematic_graph.dart <bindings.json> '
      '<cinematic-annotations.json> <catalog.json> <output.json>',
    );
    exitCode = 64;
    return;
  }
  final manifest = _read(arguments[0]);
  final annotations = _read(arguments[1]);
  final catalog = _read(arguments[2]);
  final nodeCounts = <String, int>{
    for (final raw in catalog['clips']! as List<Object?>)
      (raw! as Map<String, Object?>)['id']! as String:
          (raw as Map<String, Object?>)['nodeCount']! as int,
  };
  final bindings = (manifest['bindings']! as List<Object?>)
      .where(
        (raw) => raw is! Map<String, Object?> || raw['context'] != 'cinematic',
      )
      .toList();
  final runtimeProfiles = (manifest['runtimeProfiles']! as List<Object?>)
      .where(
        (raw) => raw is! Map<String, Object?> || raw['context'] != 'cinematic',
      )
      .toList();
  final timelines = <int, Map<String, Object?>>{};
  final cinematicClips = <String>{};
  var cueCount = 0;

  for (final rawClip in annotations['clips']! as List<Object?>) {
    final clip = rawClip! as Map<String, Object?>;
    final id = clip['id']! as String;
    for (final rawContext in clip['contexts']! as List<Object?>) {
      final context = rawContext! as Map<String, Object?>;
      final costume = context['costume']! as String;
      if (!RegExp(r'^scene-\d+$').hasMatch(costume)) continue;
      final scene = int.parse(costume.substring(6));
      final dictionary = context['dictionaryId']! as int;
      final slot = context['slot']! as int;
      final actor = context['owner']! as String;
      final action = '${context['action']}.cue-$slot';
      final event = 'script.cinematic.scene-data-$scene';
      final timeline = timelines.putIfAbsent(
        scene,
        () => {
          'id': 'scene-data-$scene',
          'scriptEvent': event,
          'kind': scene == 0
              ? 'entrance'
              : scene == 13
              ? 'exit'
              : 'in-game',
          'reentryPolicy': 'resume-checkpoint-or-restart-after-interrupt',
          'skipPolicy': 'apply-terminal-state',
          'interruptPolicy': 'checkpoint-current-cue',
          'controlPolicy': 'lock-on-start-return-on-terminal',
          'tracks': <Map<String, Object?>>[],
          'cues': <Map<String, Object?>>[
            {'index': 0, 'type': 'camera', 'value': 'cinematic:$scene'},
            {'index': 0, 'type': 'audio', 'value': 'cinematic:$scene'},
            {'index': 0, 'type': 'subtitle', 'value': 'cinematic.scene-$scene'},
          ],
        },
      );
      (timeline['tracks']! as List<Map<String, Object?>>).add({
        'actor': actor,
        'dictionaryId': dictionary,
        'slot': slot,
        'action': action,
        'cueIndex': slot,
      });
      bindings.add({
        'actor': actor,
        'skin': dictionary,
        'skinProfile': context['skin'],
        'costume': costume,
        'action': action,
        'context': 'cinematic',
        'variant': 'dictionary-$dictionary-slot-$slot',
        'clip': '$id.animation.json',
        'loop': false,
        'priority': 100,
        'fallback': false,
        'skeletonNodes': nodeCounts[id],
        'transitions': <String>[],
        'phases': const {'complete': 1.0},
        'rootMotion': context['rootMotion'],
        'trigger': '$event:cue-$slot',
        'dictionaryId': dictionary,
        'slot': slot,
        'timeline': 'scene-data-$scene',
        'cueIndex': slot,
      });
      cinematicClips.add(id);
      cueCount++;
    }
  }
  final ordered = timelines.values.toList()
    ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
  for (final timeline in ordered) {
    final tracks = timeline['tracks']! as List<Map<String, Object?>>;
    tracks.sort(
      (a, b) => (a['cueIndex']! as int).compareTo(b['cueIndex']! as int),
    );
    timeline['terminalCue'] = tracks
        .map((track) => track['cueIndex']! as int)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final scene = (timeline['id']! as String).substring(11);
    final first = tracks.first;
    final states = <String, Object?>{};
    final cueStates = <String, List<String>>{};
    for (final track in tracks) {
      final state = 'dictionary_slot_${track['slot']}';
      states[state] = {
        'action': track['action'],
        'variant': 'dictionary-${track['dictionaryId']}-slot-${track['slot']}',
      };
      cueStates.putIfAbsent('cue_${track['cueIndex']}', () => []).add(state);
    }
    runtimeProfiles.add({
      'id': 'cinematic-scene-data-$scene',
      'actor': first['actor'],
      'skin': first['dictionaryId'],
      'costume': 'scene-$scene',
      'context': 'cinematic',
      'instance': 'cinematic-timeline-$scene',
      'scriptEvent': timeline['scriptEvent'],
      'cueStates': cueStates,
      'controlPolicy': timeline['controlPolicy'],
      'skipPolicy': timeline['skipPolicy'],
      'interruptPolicy': timeline['interruptPolicy'],
      'reentryPolicy': timeline['reentryPolicy'],
      'restorePolicy': 'snapshot-without-replay',
      'complete': true,
      'states': states,
    });
  }
  manifest
    ..['cinematicGraphVersion'] = 1
    ..['cinematicCatalog'] = {
      'clipCount': cinematicClips.length,
      'contextCount': cueCount,
      'timelineCount': ordered.length,
    }
    ..['cinematicTimelines'] = ordered
    ..['runtimeProfiles'] = runtimeProfiles
    ..['bindings'] = bindings;
  await File(arguments[3]).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    flush: true,
  );
}

Map<String, Object?> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
