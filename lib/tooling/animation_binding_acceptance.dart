import 'dart:convert';

import 'package:asterix_xxl/runtime/animation_binding_registry.dart';
import 'package:asterix_xxl/tooling/animation_semantic_catalog.dart';

final class AnimationBindingAcceptanceException implements Exception {
  const AnimationBindingAcceptanceException(this.issues);

  final List<String> issues;

  @override
  String toString() => issues.join('\n');
}

/// Cross-checks the imported LVL01 inventory, semantic dictionary contexts,
/// binding registry and the runtime entry points which can select a binding.
Map<String, Object?> buildAnimationBindingAcceptanceReport({
  required Map<String, Object?> catalog,
  required Map<String, Object?> manifest,
  required Map<String, Object?> visualEvidence,
}) {
  final issues = validateLvl01AnimationCatalogAcceptance(
    catalog,
  ).map((issue) => issue.toString()).toList();
  AnimationBindingRegistry? registry;
  try {
    registry = AnimationBindingRegistry.parse(manifest);
  } on AnimationBindingException catch (error) {
    issues.add(error.message);
  }
  if (registry == null) {
    throw AnimationBindingAcceptanceException(issues);
  }
  issues.addAll(_acceptanceManifestIssues(manifest));
  if (issues.isNotEmpty) {
    throw AnimationBindingAcceptanceException(issues);
  }

  final bindings = registry.bindings;
  final paths = animationRuntimePaths(manifest);
  final clips = (catalog['clips']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final rows = <Map<String, Object?>>[];
  var unbound = 0;
  var unexplained = 0;
  var unreachable = 0;

  for (final clip in clips) {
    final source = clip['source'] as String;
    final clipBindings = bindings
        .where((binding) => binding['clip'] == source)
        .toList(growable: false);
    final contexts = (clip['contexts']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final missingContexts = <String>[];
    for (final context in contexts) {
      // Dictionary annotations deliberately use broader semantic actions for
      // variants and directional slots. Clip identity is the lossless join to
      // one or more concrete registry actions; do not guess a string alias.
      if (clipBindings.isEmpty) {
        missingContexts.add(
          'dictionary-${context['dictionaryId']}/slot-${context['slot']}:${context['action']}',
        );
      }
    }
    final bindingRows = clipBindings
        .map((binding) {
          final key = _bindingKey(binding);
          return <String, Object?>{
            'actor': binding['actor'],
            'action': binding['action'],
            'context': binding['context'],
            if (binding['variant'] != null) 'variant': binding['variant'],
            'runtimePaths': paths[key] ?? const <String>[],
          };
        })
        .toList(growable: false);
    final missingPaths = bindingRows
        .where((row) => (row['runtimePaths']! as List).isEmpty)
        .length;
    if (clipBindings.isEmpty) unbound++;
    if (missingContexts.isNotEmpty) unexplained++;
    if (missingPaths > 0) unreachable++;
    rows.add({
      'clip': source,
      'memberships': clip['dictionaryMemberships'],
      'bindings': bindingRows,
      'missingSemanticContexts': missingContexts,
    });
  }

  final catalogSources = clips.map((clip) => clip['source']).toSet();
  final unknownBindings =
      bindings
          .where((binding) => !catalogSources.contains(binding['clip']))
          .map((binding) => binding['clip'])
          .toSet()
          .toList()
        ..sort();
  if (unbound != 0) issues.add('$unbound catalog clips are unbound');
  if (unexplained != 0) {
    final examples = rows
        .where((row) => (row['missingSemanticContexts']! as List).isNotEmpty)
        .take(8)
        .map((row) => '${row['clip']}:${row['missingSemanticContexts']}')
        .join('; ');
    issues.add(
      '$unexplained clips have dictionary contexts without a binding ($examples)',
    );
  }
  if (unreachable != 0) {
    final examples = rows
        .where(
          (row) => (row['bindings']! as List<Map<String, Object?>>).any(
            (binding) => (binding['runtimePaths']! as List).isEmpty,
          ),
        )
        .take(8)
        .map((row) => row['clip'])
        .join(', ');
    issues.add(
      '$unreachable clips contain bindings without a runtime path ($examples)',
    );
  }
  if (unknownBindings.isNotEmpty) {
    issues.add(
      'bindings reference unknown clips: ${unknownBindings.join(', ')}',
    );
  }
  issues.addAll(validateAnimationVisualEvidence(visualEvidence, bindings));

  final report = <String, Object?>{
    'schemaVersion': 1,
    'dataset': 'XXL1/LVL01',
    'summary': {
      'catalogClips': clips.length,
      'dictionaryCount': catalog['dictionaryCount'],
      'dictionarySlots': (catalog['dictionaries']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .expand((dictionary) => dictionary['slots']! as List<Object?>)
          .length,
      'bindings': bindings.length,
      'boundClips': rows
          .where((row) => (row['bindings']! as List).isNotEmpty)
          .length,
      'unboundClips': unbound,
      'unexplainedClips': unexplained,
      'clipsWithoutRuntimePath': unreachable,
      'unknownBindingClips': unknownBindings.length,
      'representativeSequences':
          (visualEvidence['sequences'] as List<Object?>? ?? const []).length,
    },
    'visualEvidence': visualEvidence,
    'clips': rows,
  };
  if (issues.isNotEmpty) {
    throw AnimationBindingAcceptanceException(issues);
  }
  return report;
}

Map<String, List<String>> animationRuntimePaths(Map<String, Object?> manifest) {
  final result = <String, List<String>>{};
  final bindings = (manifest['bindings']! as List<Object?>)
      .cast<Map<String, Object?>>();
  void add(Map<String, Object?> binding, String path) {
    result.putIfAbsent(_bindingKey(binding), () => []).add(path);
  }

  final entryStates = (manifest['entryStates']! as Map<String, Object?>);
  for (final entry in entryStates.entries) {
    final actorBindings = bindings
        .where(
          (item) => item['actor'] == entry.key && item['context'] == 'gameplay',
        )
        .toList(growable: false);
    final reachable = <Object?>{entry.value};
    final pending = <Object?>[entry.value];
    while (pending.isNotEmpty) {
      final action = pending.removeLast();
      for (final binding in actorBindings.where(
        (item) => item['action'] == action,
      )) {
        for (final target in binding['transitions']! as List<Object?>) {
          if (reachable.add(target)) pending.add(target);
        }
      }
    }
    for (final binding in actorBindings.where(
      (item) => reachable.contains(item['action']),
    )) {
      add(binding, 'hero-graph:${entry.key}:${entry.value}');
    }
  }
  // The current Metal renderer retains a seven-state Asterix compatibility
  // graph beside the complete semantic graph. Its unversioned variants form
  // an independently connected component rooted at `idle`.
  for (final root in bindings.where(
    (item) =>
        item['context'] == 'gameplay' &&
        item['variant'] == null &&
        item['action'] == 'idle',
  )) {
    final component = bindings
        .where(
          (item) =>
              item['actor'] == root['actor'] &&
              item['context'] == root['context'] &&
              item['variant'] == null,
        )
        .toList(growable: false);
    final reachable = <Object?>{'idle'};
    final pending = <Object?>['idle'];
    while (pending.isNotEmpty) {
      final action = pending.removeLast();
      for (final binding in component.where(
        (item) => item['action'] == action,
      )) {
        for (final target in binding['transitions']! as List<Object?>) {
          if (reachable.add(target)) pending.add(target);
        }
      }
    }
    for (final binding in component.where(
      (item) => reachable.contains(item['action']),
    )) {
      add(binding, 'renderer-state-machine:${root['actor']}:idle');
    }
  }
  for (final raw in manifest['characterProfiles']! as List<Object?>) {
    final profile = raw! as Map<String, Object?>;
    final triggers = profile['stateBindings']! as Map<String, Object?>;
    final requiredStates = (profile['requiredStates']! as List<Object?>)
        .toSet();
    for (final binding in bindings.where(
      (item) =>
          item['actor'] == profile['actor'] &&
          item['skin'] == profile['skin'] &&
          item['costume'] == profile['costume'] &&
          item['context'] == profile['context'] &&
          requiredStates.contains(item['action']),
    )) {
      add(binding, 'character-graph:${profile['entryState']}');
    }
    for (final trigger in triggers.entries) {
      for (final binding in bindings.where(
        (item) =>
            item['actor'] == profile['actor'] &&
            item['skin'] == profile['skin'] &&
            item['costume'] == profile['costume'] &&
            item['context'] == profile['context'] &&
            item['action'] == trigger.value,
      )) {
        add(binding, 'character:${trigger.key}');
      }
    }
  }
  for (final raw in manifest['worldProfiles']! as List<Object?>) {
    final profile = raw! as Map<String, Object?>;
    final triggers = profile['eventBindings']! as Map<String, Object?>;
    for (final trigger in triggers.entries) {
      for (final binding in bindings.where(
        (item) =>
            item['actor'] == profile['actor'] &&
            item['skin'] == profile['skin'] &&
            item['costume'] == profile['costume'] &&
            item['context'] == profile['context'] &&
            item['action'] == trigger.value,
      )) {
        add(binding, 'world:${trigger.key}');
      }
    }
  }
  for (final raw in manifest['cinematicTimelines']! as List<Object?>) {
    final timeline = raw! as Map<String, Object?>;
    for (final rawTrack in timeline['tracks']! as List<Object?>) {
      final track = rawTrack! as Map<String, Object?>;
      for (final binding in bindings.where(
        (item) =>
            item['actor'] == track['actor'] &&
            item['context'] == 'cinematic' &&
            item['action'] == track['action'],
      )) {
        add(
          binding,
          'cinematic:${timeline['scriptEvent']}:cue-${track['cueIndex']}',
        );
      }
    }
  }
  return result;
}

List<String> validateAnimationVisualEvidence(
  Map<String, Object?> evidence,
  List<Map<String, Object?>> bindings,
) {
  final issues = <String>[];
  if (evidence['schemaVersion'] != 1 || evidence['dataset'] != 'XXL1/LVL01') {
    return ['visual evidence must use schemaVersion 1 and XXL1/LVL01'];
  }
  final sequences = evidence['sequences'];
  if (sequences is! List || sequences.isEmpty) {
    return ['visual evidence must contain representative sequences'];
  }
  for (var index = 0; index < sequences.length; index++) {
    final sequence = sequences[index];
    if (sequence is! Map<String, Object?> ||
        sequence['result'] != 'match' ||
        sequence['originalReference'] is! String ||
        (sequence['originalReference']! as String).isEmpty ||
        sequence['steps'] is! List ||
        (sequence['steps']! as List).isEmpty) {
      issues.add('visualEvidence.sequences[$index] is incomplete');
      continue;
    }
    for (final rawStep in sequence['steps']! as List<Object?>) {
      if (rawStep is! Map<String, Object?> ||
          !bindings.any(
            (binding) =>
                binding['actor'] == rawStep['actor'] &&
                binding['action'] == rawStep['action'] &&
                binding['clip'] == rawStep['clip'],
          )) {
        issues.add(
          'visualEvidence.sequences[$index] references an unknown binding',
        );
      }
    }
  }
  return issues;
}

String _bindingKey(Map<String, Object?> binding) => jsonEncode([
  binding['actor'],
  binding['skin'],
  binding['costume'],
  binding['action'],
  binding['context'],
  binding['variant'],
]);

String bindingAcceptanceKey(Map<String, Object?> binding) =>
    _bindingKey(binding);

List<String> _acceptanceManifestIssues(Map<String, Object?> manifest) {
  final issues = <String>[];
  for (final version in const {
    'graphVersion',
    'characterGraphVersion',
    'worldGraphVersion',
    'cinematicGraphVersion',
    'eventTrackVersion',
  }) {
    if (manifest[version] != 1) issues.add('$version must equal 1');
  }
  for (final section in const {
    'entryStates',
    'characterProfiles',
    'worldProfiles',
    'cinematicTimelines',
    'eventTracks',
  }) {
    if (manifest[section] == null) issues.add('$section must be present');
  }
  return issues;
}
