import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: animation_world_graph.dart <bindings.json> '
      '<world-annotations.json> <world-catalog.json> <output.json>',
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
  final oldProfiles = (manifest['worldProfiles'] as List? ?? const [])
      .whereType<Map<String, Object?>>()
      .map((profile) => '${profile['actor']}|${profile['skin']}')
      .toSet();
  final bindings = (manifest['bindings']! as List<Object?>)
      .whereType<Map<String, Object?>>()
      .where(
        (binding) =>
            !oldProfiles.contains('${binding['actor']}|${binding['skin']}'),
      )
      .cast<Object?>()
      .toList();
  final profiles = <String, Map<String, Object?>>{};
  var contextCount = 0;

  for (final rawClip in annotations['clips']! as List<Object?>) {
    final clip = rawClip! as Map<String, Object?>;
    final id = clip['id']! as String;
    for (final rawContext in clip['contexts']! as List<Object?>) {
      final context = rawContext! as Map<String, Object?>;
      final dictionary = context['dictionaryId']! as int;
      final slot = context['slot']! as int;
      final actor = context['owner']! as String;
      final action = context['action']! as String;
      final key = '$actor|$dictionary';
      final profile = profiles.putIfAbsent(
        key,
        () => {
          'actor': actor,
          'skin': dictionary,
          'skinProfile': context['skin'],
          'costume': context['costume'],
          'context': 'world',
          'entryState': action,
          'requiredStates': <String>[],
          'eventBindings': <String, String>{},
          'restorePolicy': 'snapshot-without-replay',
        },
      );
      (profile['requiredStates']! as List<String>).add(action);
      (profile['eventBindings']! as Map<String, String>)[_event(action)] =
          action;
      bindings.add({
        'actor': actor,
        'skin': dictionary,
        'skinProfile': context['skin'],
        'costume': context['costume'],
        'action': action,
        'context': 'world',
        'variant': 'dictionary-$dictionary-slot-$slot',
        'clip': '$id.animation.json',
        'loop': context['playback'] == 'loop',
        'priority': 0,
        'fallback': false,
        'skeletonNodes': nodeCounts[id],
        'transitions': <String>[],
        'phases': _phases(action),
        'rootMotion': context['rootMotion'],
        'trigger': _event(action),
        'dictionaryId': dictionary,
        'slot': slot,
      });
      contextCount++;
    }
  }

  for (final profile in profiles.values) {
    final states = (profile['requiredStates']! as List<String>).toSet().toList()
      ..sort();
    profile['requiredStates'] = states;
    profile['entryState'] = _entryState(states);
    for (final binding in bindings.cast<Map<String, Object?>>().where(
      (binding) =>
          binding['actor'] == profile['actor'] &&
          binding['skin'] == profile['skin'] &&
          binding['context'] == 'world',
    )) {
      binding['transitions'] = states;
    }
  }
  final ordered = profiles.values.toList()
    ..sort((a, b) => (a['skin']! as int).compareTo(b['skin']! as int));
  manifest['worldGraphVersion'] = 1;
  manifest['worldCatalog'] = {
    'clipCount': (annotations['clips']! as List<Object?>).length,
    'contextCount': contextCount,
  };
  manifest['worldProfiles'] = ordered;
  manifest['bindings'] = bindings;
  await File(arguments[3]).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    flush: true,
  );
}

Map<String, Object?> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

String _entryState(List<String> states) {
  for (final suffix in const [
    '.idle',
    '.active-loop',
    '.activated',
    '.lightning-loop',
  ]) {
    final match = states.where((state) => state.endsWith(suffix));
    if (match.isNotEmpty) return match.first;
  }
  return states.first;
}

Map<String, double> _phases(String action) {
  if (action.endsWith('.fire') || action.endsWith('.attack')) {
    return const {'windup': 0.25, 'commit': 0.5, 'complete': 1};
  }
  if (action.endsWith('.activate') || action.endsWith('.open')) {
    return const {'commit': 0.5, 'complete': 1};
  }
  if (action.endsWith('.close') ||
      action.endsWith('.deactivate') ||
      action.endsWith('.stop') ||
      action.endsWith('.reset')) {
    return const {'commit': 0.5, 'complete': 1};
  }
  if (action.endsWith('.idle') ||
      action.endsWith('.active-loop') ||
      action.endsWith('.lightning-loop')) {
    return const {'cycle': 1};
  }
  return const {'complete': 1};
}

String _event(String action) {
  if (action.endsWith('.idle') || action.endsWith('.active-loop')) {
    return 'world-state:$action';
  }
  if (action.startsWith('interface.')) return 'ui-event:$action';
  if (action.startsWith('fx.')) return 'environment-event:$action';
  if (action.startsWith('fauna.')) return 'world-event:$action';
  if (action.startsWith('checkpoint.')) return 'checkpoint-event:$action';
  if (action.startsWith('shop.')) return 'interaction-event:$action';
  return 'world-event:$action';
}
