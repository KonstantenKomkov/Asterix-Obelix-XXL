import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

final class AnimationCatalogIssue {
  const AnimationCatalogIssue(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Animation dictionaries owned by gameplay enemies, enemy leaders and
/// animated scene/NPC character hooks in XXL1 LVL01.
const characterAnimationDictionaryIds = <int>{
  4,
  7,
  9,
  10,
  17,
  27,
  28,
  31,
  32,
  33,
  34,
  35,
  36,
  37,
  38,
  39,
  40,
  41,
  42,
  43,
  44,
  45,
  46,
  47,
  48,
};

/// Builds the objective part of the semantic catalog from importer output.
/// Human conclusions live in a separate annotations file and are never
/// guessed from a clip number.
Future<Map<String, Object?>> buildAnimationCatalogDraft({
  required File inventoryFile,
  required Directory animationsDirectory,
}) async {
  final inventory =
      jsonDecode(await inventoryFile.readAsString()) as Map<String, Object?>;
  final clipCount = inventory['clipCount'] as int;
  final memberships = <int, List<Map<String, int>>>{};
  for (final raw in inventory['dictionaries']! as List<Object?>) {
    final dictionary = raw! as Map<String, Object?>;
    final dictionaryId = dictionary['objectId'] as int;
    final slots = dictionary['slots']! as List<Object?>;
    for (var slot = 0; slot < slots.length; slot++) {
      final clip = slots[slot];
      if (clip is int) {
        memberships.putIfAbsent(clip, () => []).add({
          'dictionaryId': dictionaryId,
          'slot': slot,
        });
      }
    }
  }
  final dictionaryOwners = <int, List<Map<String, Object?>>>{};
  for (final raw in inventory['dictionaryOwnerReferences']! as List<Object?>) {
    final reference = raw! as Map<String, Object?>;
    final dictionaryId = reference['dictionaryObjectId']! as int;
    dictionaryOwners.putIfAbsent(dictionaryId, () => []).add({
      'ownerClass': reference['ownerClass'],
      'ownerObjectId': reference['sourceObjectId'],
      'field': reference['field'],
      'referenceKind': reference['referenceKind'],
      'evidence': reference['evidence'],
    });
  }

  final clips = <Map<String, Object?>>[];
  for (var index = 0; index < clipCount; index++) {
    final id = index.toString().padLeft(4, '0');
    final file = File('${animationsDirectory.path}/$id.animation.json');
    final animation =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final samples = animation['samples']! as List<Object?>;
    final first = samples.first! as Map<String, Object?>;
    final last = samples.last! as Map<String, Object?>;
    final firstTransforms = first['localTransforms']! as List<Object?>;
    final lastTransforms = last['localTransforms']! as List<Object?>;
    // XXL HAnim clips keep a stationary scene root at node 0. Node 1 is the
    // animated character root whose translation carries authored root motion.
    final motionRootNodeIndex = firstTransforms.length > 1 ? 1 : 0;
    final rootStart = _translation(
      firstTransforms[motionRootNodeIndex]! as List<Object?>,
    );
    final rootEnd = _translation(
      lastTransforms[motionRootNodeIndex]! as List<Object?>,
    );
    final rootDelta = List<double>.generate(
      3,
      (component) => rootEnd[component] - rootStart[component],
    );
    var endpointTranslationError = 0.0;
    for (var joint = 0; joint < firstTransforms.length; joint++) {
      final a = _translation(firstTransforms[joint]! as List<Object?>);
      final b = _translation(lastTransforms[joint]! as List<Object?>);
      for (var component = 0; component < 3; component++) {
        final delta = b[component] - a[component];
        endpointTranslationError += delta * delta;
      }
    }
    endpointTranslationError = math.sqrt(
      endpointTranslationError / firstTransforms.length,
    );
    final clipMemberships = memberships[index] ?? const [];
    final ownerCandidates = <Map<String, Object?>>[];
    final ownerKeys = <String>{};
    for (final membership in clipMemberships) {
      for (final owner
          in dictionaryOwners[membership['dictionaryId']] ?? const []) {
        final key = '${owner['ownerClass']}:${owner['ownerObjectId']}';
        if (ownerKeys.add(key)) ownerCandidates.add(owner);
      }
    }
    clips.add({
      'id': id,
      'managerIndex': index,
      'source': '$id.animation.json',
      'nodeCount': animation['nodeCount'],
      'durationSeconds': animation['duration'],
      'frameCount': animation['frameCount'],
      'dictionaryMemberships': clipMemberships,
      'ownerCandidates': ownerCandidates,
      'analysis': {
        'motionRootNodeIndex': motionRootNodeIndex,
        'rootTranslationDelta': rootDelta,
        'rootMotionDistance': math.sqrt(
          rootDelta.fold<double>(0, (sum, value) => sum + value * value),
        ),
        'endpointTranslationRms': endpointTranslationError,
      },
      'status': 'unreviewed',
      'owner': null,
      'skin': null,
      'costume': null,
      'action': null,
      'playback': null,
      'variants': <Object?>[],
      'transitions': <Object?>[],
      'rootMotion': null,
      'events': <Object?>[],
      'evidence': <Object?>[],
      'contexts': <Object?>[],
    });
  }
  return {
    'schemaVersion': 1,
    'source': inventory['source'],
    'clipCount': clipCount,
    'dictionaryCount': inventory['dictionaryCount'],
    'dictionaries': inventory['dictionaries'],
    'clips': clips,
  };
}

Map<String, Object?> applyAnimationCatalogAnnotations(
  Map<String, Object?> catalog,
  Map<String, Object?> annotations,
) {
  if (annotations['schemaVersion'] != 1 ||
      annotations['clips'] is! List<Object?>) {
    throw const FormatException(
      'Annotations must have schemaVersion 1 and a clips list.',
    );
  }
  final result = Map<String, Object?>.from(catalog);
  final clips = (catalog['clips']! as List<Object?>)
      .map((clip) => Map<String, Object?>.from(clip! as Map<String, Object?>))
      .toList();
  final byId = {for (final clip in clips) clip['id'] as String: clip};
  final applied = <String>{};
  const semanticFields = {
    'status',
    'owner',
    'skin',
    'costume',
    'action',
    'playback',
    'variants',
    'transitions',
    'rootMotion',
    'events',
    'evidence',
    'contexts',
  };
  for (final raw in annotations['clips']! as List<Object?>) {
    if (raw is! Map<String, Object?> || raw['id'] is! String) {
      throw const FormatException('Every annotation must have a string id.');
    }
    final id = raw['id']! as String;
    final clip = byId[id];
    if (clip == null) throw FormatException('Unknown annotated clip $id.');
    if (!applied.add(id)) {
      throw FormatException('Duplicate annotation for $id.');
    }
    for (final entry in raw.entries) {
      if (entry.key == 'id') continue;
      if (!semanticFields.contains(entry.key)) {
        throw FormatException(
          'Annotation $id changes objective field ${entry.key}.',
        );
      }
      clip[entry.key] = entry.value;
    }
  }
  result['clips'] = clips;
  return result;
}

List<AnimationCatalogIssue> validateAnimationSemanticCatalog(
  Map<String, Object?> catalog, {
  bool requireConfirmed = true,
  Set<int>? requiredDictionaryIds,
}) {
  final issues = <AnimationCatalogIssue>[];
  if (catalog['schemaVersion'] != 1) {
    issues.add(const AnimationCatalogIssue('schemaVersion', 'must equal 1'));
  }
  final count = catalog['clipCount'];
  final clips = catalog['clips'];
  if (count is! int || clips is! List<Object?> || clips.length != count) {
    issues.add(
      const AnimationCatalogIssue('clips', 'must match clipCount exactly'),
    );
    return issues;
  }
  final dictionarySlots = <(int, int), int>{};
  final catalogDictionaryIds = <int>{};
  final dictionaries = catalog['dictionaries'];
  if (dictionaries is! List<Object?>) {
    issues.add(const AnimationCatalogIssue('dictionaries', 'must be a list'));
  } else {
    for (var index = 0; index < dictionaries.length; index++) {
      final dictionary = dictionaries[index];
      final path = 'dictionaries[$index]';
      if (dictionary is! Map<String, Object?> ||
          dictionary['objectId'] is! int ||
          dictionary['slots'] is! List<Object?>) {
        issues.add(
          AnimationCatalogIssue(
            path,
            'must contain integer objectId and slots list',
          ),
        );
        continue;
      }
      final dictionaryId = dictionary['objectId']! as int;
      catalogDictionaryIds.add(dictionaryId);
      final slots = dictionary['slots']! as List<Object?>;
      for (var slot = 0; slot < slots.length; slot++) {
        final clipIndex = slots[slot];
        if (clipIndex != null && clipIndex is! int) {
          issues.add(
            AnimationCatalogIssue('$path.slots[$slot]', 'must be int or null'),
          );
        } else if (clipIndex is int) {
          dictionarySlots[(dictionaryId, slot)] = clipIndex;
        }
      }
    }
  }
  if (requiredDictionaryIds != null) {
    for (final dictionaryId in requiredDictionaryIds) {
      if (!catalogDictionaryIds.contains(dictionaryId)) {
        issues.add(
          AnimationCatalogIssue(
            'dictionaries',
            'does not contain requested dictionary $dictionaryId',
          ),
        );
      }
    }
  }
  final ids = <String>{};
  final managerIndices = <int>{};
  const requiredSemanticFields = [
    'owner',
    'skin',
    'costume',
    'action',
    'playback',
    'rootMotion',
  ];
  for (var index = 0; index < clips.length; index++) {
    final path = 'clips[$index]';
    final clip = clips[index];
    if (clip is! Map<String, Object?>) {
      issues.add(AnimationCatalogIssue(path, 'must be an object'));
      continue;
    }
    final id = clip['id'];
    final expectedId = index.toString().padLeft(4, '0');
    if (id is! String || !ids.add(id)) {
      issues.add(AnimationCatalogIssue('$path.id', 'must be a unique string'));
    } else if (id != expectedId) {
      issues.add(
        AnimationCatalogIssue(
          '$path.id',
          'must equal manager index $expectedId',
        ),
      );
    }
    final managerIndex = clip['managerIndex'];
    if (managerIndex is! int || !managerIndices.add(managerIndex)) {
      issues.add(
        AnimationCatalogIssue('$path.managerIndex', 'must be a unique integer'),
      );
    } else if (managerIndex != index) {
      issues.add(
        AnimationCatalogIssue('$path.managerIndex', 'must equal $index'),
      );
    }
    final memberships = clip['dictionaryMemberships'];
    if (memberships is! List<Object?> || memberships.isEmpty) {
      issues.add(
        AnimationCatalogIssue(
          '$path.dictionaryMemberships',
          'must reference at least one dictionary slot',
        ),
      );
    } else {
      for (
        var membershipIndex = 0;
        membershipIndex < memberships.length;
        membershipIndex++
      ) {
        final membership = memberships[membershipIndex];
        final membershipPath = '$path.dictionaryMemberships[$membershipIndex]';
        if (membership is! Map<String, Object?> ||
            membership['dictionaryId'] is! int ||
            membership['slot'] is! int) {
          issues.add(
            AnimationCatalogIssue(
              membershipPath,
              'must contain integer dictionaryId and slot',
            ),
          );
          continue;
        }
        final key = (
          membership['dictionaryId']! as int,
          membership['slot']! as int,
        );
        if (dictionarySlots[key] != managerIndex) {
          issues.add(
            AnimationCatalogIssue(
              membershipPath,
              'must match the referenced dictionary slot',
            ),
          );
        }
      }
    }
    final ownerCandidates = clip['ownerCandidates'];
    if (ownerCandidates is! List<Object?> || ownerCandidates.isEmpty) {
      issues.add(
        AnimationCatalogIssue(
          '$path.ownerCandidates',
          'must contain at least one structurally confirmed owner',
        ),
      );
    }
    final status = clip['status'];
    if (!{
      'unreviewed',
      'provisional',
      'confirmed',
      'excluded',
    }.contains(status)) {
      issues.add(AnimationCatalogIssue('$path.status', 'has unknown value'));
    }
    final isInRequiredDictionary =
        requiredDictionaryIds == null ||
        (memberships is List<Object?> &&
            memberships.whereType<Map<String, Object?>>().any(
              (membership) =>
                  requiredDictionaryIds.contains(membership['dictionaryId']),
            ));
    if (!requireConfirmed || !isInRequiredDictionary) continue;
    if (status != 'confirmed') {
      issues.add(AnimationCatalogIssue('$path.status', 'must be confirmed'));
    }
    for (final field in requiredSemanticFields) {
      final value = clip[field];
      if (value is! String || value.trim().isEmpty) {
        issues.add(
          AnimationCatalogIssue('$path.$field', 'must be a non-empty string'),
        );
      }
    }
    if (!{'loop', 'one-shot'}.contains(clip['playback'])) {
      issues.add(
        AnimationCatalogIssue(
          '$path.playback',
          'must be either loop or one-shot',
        ),
      );
    }
    for (final field in ['variants', 'transitions', 'events', 'evidence']) {
      final value = clip[field];
      if (value is! List<Object?>) {
        issues.add(AnimationCatalogIssue('$path.$field', 'must be a list'));
      }
    }
    final evidence = clip['evidence'];
    if (evidence is List<Object?> && evidence.isEmpty) {
      issues.add(AnimationCatalogIssue('$path.evidence', 'must not be empty'));
    } else if (evidence is List<Object?>) {
      for (
        var evidenceIndex = 0;
        evidenceIndex < evidence.length;
        evidenceIndex++
      ) {
        final item = evidence[evidenceIndex];
        if (item is! Map<String, Object?> ||
            item['method'] is! String ||
            (item['method']! as String).trim().isEmpty ||
            item['reference'] is! String ||
            (item['reference']! as String).trim().isEmpty) {
          issues.add(
            AnimationCatalogIssue(
              '$path.evidence[$evidenceIndex]',
              'must contain string method and reference',
            ),
          );
        }
      }
    }
    final contexts = clip['contexts'];
    if (contexts is! List<Object?> || contexts.isEmpty) {
      issues.add(
        AnimationCatalogIssue(
          '$path.contexts',
          'must cover every dictionary membership',
        ),
      );
    } else {
      final coveredMemberships = <(int, int)>{};
      for (
        var contextIndex = 0;
        contextIndex < contexts.length;
        contextIndex++
      ) {
        final context = contexts[contextIndex];
        final contextPath = '$path.contexts[$contextIndex]';
        if (context is! Map<String, Object?> ||
            context['dictionaryId'] is! int ||
            context['slot'] is! int) {
          issues.add(
            AnimationCatalogIssue(
              contextPath,
              'must contain integer dictionaryId and slot',
            ),
          );
          continue;
        }
        final membership = (
          context['dictionaryId']! as int,
          context['slot']! as int,
        );
        if (!coveredMemberships.add(membership)) {
          issues.add(
            AnimationCatalogIssue(contextPath, 'duplicates a context'),
          );
        }
        if (dictionarySlots[membership] != managerIndex) {
          issues.add(
            AnimationCatalogIssue(
              contextPath,
              'must match a dictionary membership of this clip',
            ),
          );
        }
        for (final field in requiredSemanticFields) {
          final value = context[field];
          if (value is! String || value.trim().isEmpty) {
            issues.add(
              AnimationCatalogIssue(
                '$contextPath.$field',
                'must be a non-empty string',
              ),
            );
          }
        }
        for (final field in ['variants', 'transitions', 'events', 'evidence']) {
          if (context[field] is! List<Object?>) {
            issues.add(
              AnimationCatalogIssue('$contextPath.$field', 'must be a list'),
            );
          }
        }
      }
      final expectedMemberships = {
        for (final membership in memberships! as List<Object?>)
          (
            (membership! as Map<String, Object?>)['dictionaryId']! as int,
            (membership as Map<String, Object?>)['slot']! as int,
          ),
      };
      if (!coveredMemberships.containsAll(expectedMemberships) ||
          !expectedMemberships.containsAll(coveredMemberships)) {
        issues.add(
          AnimationCatalogIssue(
            '$path.contexts',
            'must cover every dictionary membership exactly once',
          ),
        );
      }
    }
  }
  return issues;
}

List<double> _translation(List<Object?> matrix) => [
  (matrix[12]! as num).toDouble(),
  (matrix[13]! as num).toDouble(),
  (matrix[14]! as num).toDouble(),
];
