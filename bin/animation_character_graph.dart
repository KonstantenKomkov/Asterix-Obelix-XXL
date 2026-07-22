import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: animation_character_graph.dart <bindings.json> '
      '<character-annotations.json> <character-catalog.json> <output.json>',
    );
    exitCode = 64;
    return;
  }
  final manifest = _read(arguments[0]);
  final annotations = _read(arguments[1]);
  final catalog = _read(arguments[2]);
  final catalogClips = (catalog['clips']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final nodeCounts = <String, int>{
    for (final clip in catalogClips)
      clip['id']! as String: clip['nodeCount']! as int,
  };
  final previousProfiles = (manifest['characterProfiles'] as List? ?? const [])
      .whereType<Map<String, Object?>>()
      .map(
        (profile) =>
            '${profile['actor']}|${profile['skin']}|${profile['costume']}',
      )
      .toSet();
  final bindings = (manifest['bindings']! as List<Object?>)
      .whereType<Map<String, Object?>>()
      .where(
        (binding) => !previousProfiles.contains(
          '${binding['actor']}|${binding['skin']}|${binding['costume']}',
        ),
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
      final costume = context['costume']! as String;
      final action = context['action']! as String;
      final profileKey = '$actor|$dictionary|$costume';
      final profile = profiles.putIfAbsent(
        profileKey,
        () => {
          'actor': actor,
          'skin': dictionary,
          'skinProfile': context['skin'],
          'costume': costume,
          'context': actor.startsWith('basic-enemy') ? 'gameplay' : 'scripted',
          'entryState': action,
          'requiredStates': <String>[],
          'stateBindings': _stateBindings(actor),
        },
      );
      (profile['requiredStates']! as List<String>).add(action);
      bindings.add({
        'actor': actor,
        'skin': dictionary,
        'skinProfile': context['skin'],
        'costume': costume,
        'action': action,
        'context': profile['context'],
        'variant': 'dictionary-$dictionary-slot-$slot',
        'clip': '$id.animation.json',
        'loop': context['playback'] == 'loop',
        'priority': 0,
        'fallback': false,
        'skeletonNodes': nodeCounts[id],
        'transitions': <String>[],
        'phases': _phases(action),
        'catalogVariants': context['variants'],
        'rootMotion': context['rootMotion'],
        'trigger': _trigger(action),
        'dictionaryId': dictionary,
        'slot': slot,
      });
      contextCount++;
    }
  }

  for (final profile in profiles.values) {
    final required =
        (profile['requiredStates']! as List<String>).toSet().toList()..sort();
    profile['requiredStates'] = required;
    profile['stateBindings'] = Map<String, String>.fromEntries(
      (profile['stateBindings']! as Map<String, String>).entries.where(
        (entry) => required.contains(entry.value),
      ),
    );
    profile['entryState'] = required.contains('locomotion.idle')
        ? 'locomotion.idle'
        : required.first;
    for (final raw in bindings.cast<Map<String, Object?>>().where(
      (binding) =>
          binding['actor'] == profile['actor'] &&
          binding['skin'] == profile['skin'] &&
          binding['costume'] == profile['costume'],
    )) {
      raw['transitions'] = raw['action'] == 'death.variant'
          ? <String>[]
          : required;
    }
  }
  final orderedProfiles = profiles.values.toList()
    ..sort((a, b) => (a['skin']! as int).compareTo(b['skin']! as int));
  manifest['characterGraphVersion'] = 1;
  manifest['characterCatalog'] = {
    'clipCount': (annotations['clips']! as List<Object?>).length,
    'contextCount': contextCount,
  };
  manifest['characterProfiles'] = orderedProfiles;
  manifest['bindings'] = bindings;
  final output = File(arguments[3]);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    flush: true,
  );
}

Map<String, Object?> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Map<String, String> _stateBindings(String actor) =>
    actor.startsWith('basic-enemy')
    ? const {
        'spawn': 'spawn.or-awareness',
        'idle': 'locomotion.idle',
        'perception': 'spawn.or-awareness',
        'pursuit': 'locomotion.move',
        'returning': 'locomotion.move',
        'attack': 'combat.attack',
        'hit': 'damage.hit-reaction',
        'stun': 'damage.hit-reaction',
        'knockback': 'damage.hit-reaction',
        'death': 'death.variant',
        'despawn': 'death.variant',
        'special': 'special.enemy-state',
      }
    : const {
        'script-event': 'special.scripted-performance',
        'complete': 'special.scripted-performance',
      };

Map<String, double> _phases(String action) {
  if (action == 'combat.attack') {
    return const {'windup': 0.2, 'impact': 0.38461538461538464, 'recovery': 1};
  }
  if (action == 'damage.hit-reaction') {
    return const {'stun': 0.65, 'recovery': 1};
  }
  if (action.startsWith('locomotion.') && action != 'locomotion.transition') {
    return const {'contact': 0.5, 'cycle': 1};
  }
  if (action == 'spawn.or-awareness') {
    return const {'perception': 0.35, 'complete': 1};
  }
  if (action.startsWith('special.')) {
    return const {'commit': 0.5, 'complete': 1};
  }
  return const {'complete': 1};
}

String _trigger(String action) => switch (action) {
  'locomotion.idle' => 'ai-state:idle',
  'locomotion.move' => 'ai-state:pursuit-or-returning',
  'locomotion.transition' => 'ai-transition',
  'combat.attack' => 'ai-state:attack',
  'damage.hit-reaction' => 'gameplay-event:hit-stun-knockback',
  'death.variant' => 'gameplay-event:death-despawn',
  'spawn.or-awareness' => 'gameplay-event:spawn-or-perception',
  'special.enemy-state' => 'ai-event:special',
  _ => 'script-event',
};
