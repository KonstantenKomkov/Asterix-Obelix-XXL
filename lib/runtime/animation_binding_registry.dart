import 'dart:convert';
import 'dart:typed_data';

final class AnimationBindingException implements Exception {
  const AnimationBindingException(this.message);
  final String message;
  @override
  String toString() => 'AnimationBindingException: $message';
}

final class AnimationBindingQuery {
  const AnimationBindingQuery({
    required this.actor,
    required this.skin,
    required this.costume,
    required this.action,
    required this.context,
    this.variant,
  });
  final String actor;
  final int skin;
  final String costume;
  final String action;
  final String context;
  final String? variant;
}

final class AnimationBindingRegistry {
  AnimationBindingRegistry._(this.manifest, this.bindings);
  final Map<String, Object?> manifest;
  final List<Map<String, Object?>> bindings;

  Iterable<String> actors() =>
      bindings.map((binding) => binding['actor']! as String).toSet();

  List<Map<String, Object?>> heroBindings(String actor) => bindings
      .where(
        (binding) =>
            binding['actor'] == actor && binding['context'] == 'gameplay',
      )
      .toList(growable: false);

  List<Map<String, Object?>> profileBindings({
    required String actor,
    required int skin,
    required String costume,
    required String context,
  }) => bindings
      .where(
        (binding) =>
            binding['actor'] == actor &&
            binding['skin'] == skin &&
            binding['costume'] == costume &&
            binding['context'] == context,
      )
      .toList(growable: false);

  static AnimationBindingRegistry parse(Object? value) {
    if (value is! Map<String, Object?> || value['schemaVersion'] != 1) {
      throw const AnimationBindingException('schemaVersion must equal 1');
    }
    final rawBindings = value['bindings'];
    final requiredStates = value['requiredStates'];
    if (rawBindings is! List || requiredStates is! Map<String, Object?>) {
      throw const AnimationBindingException(
        'bindings and requiredStates must be present',
      );
    }
    final bindings = <Map<String, Object?>>[];
    final keys = <String>{};
    for (var index = 0; index < rawBindings.length; index++) {
      final raw = rawBindings[index];
      if (raw is! Map<String, Object?>) {
        throw AnimationBindingException('bindings[$index] must be an object');
      }
      for (final field in const [
        'actor',
        'skin',
        'costume',
        'action',
        'context',
        'clip',
        'loop',
        'priority',
        'fallback',
        'transitions',
        'skeletonNodes',
      ]) {
        if (!raw.containsKey(field)) {
          throw AnimationBindingException(
            'bindings[$index].$field is required',
          );
        }
      }
      if (raw['actor'] is! String ||
          raw['skin'] is! int ||
          raw['costume'] is! String ||
          raw['action'] is! String ||
          raw['context'] is! String ||
          raw['clip'] is! String ||
          !RegExp(
            r'^\d{4}\.animation\.json$',
          ).hasMatch(raw['clip']! as String) ||
          raw['loop'] is! bool ||
          raw['priority'] is! int ||
          raw['fallback'] is! bool ||
          raw['skeletonNodes'] is! int ||
          (raw['skeletonNodes']! as int) <= 0 ||
          raw['transitions'] is! List) {
        throw AnimationBindingException(
          'bindings[$index] has invalid field types',
        );
      }
      final phases = raw['phases'];
      if (phases != null) {
        if (phases is! Map<String, Object?> || phases.isEmpty) {
          throw AnimationBindingException(
            'bindings[$index].phases must be a non-empty object',
          );
        }
        var previous = 0.0;
        for (final phase in phases.entries) {
          final value = phase.value;
          if (value is! num || value < previous || value < 0 || value > 1) {
            throw AnimationBindingException(
              'bindings[$index].phases must be ordered in [0, 1]',
            );
          }
          previous = value.toDouble();
        }
      }
      final variant = raw['variant'];
      if (variant != null && variant is! String) {
        throw AnimationBindingException(
          'bindings[$index].variant must be a string',
        );
      }
      final key = [
        raw['actor'],
        raw['skin'],
        raw['costume'],
        raw['action'],
        raw['context'],
        variant ?? '',
      ].join('|');
      if (!keys.add(key)) {
        throw AnimationBindingException('ambiguous binding $key');
      }
      bindings.add(Map<String, Object?>.from(raw));
    }
    _validateEventTracks(value, bindings);
    for (var index = 0; index < bindings.length; index++) {
      final transitions = bindings[index]['transitions']! as List;
      final actor = bindings[index]['actor'];
      final actions = bindings
          .where((binding) => binding['actor'] == actor)
          .map((binding) => binding['action'])
          .toSet();
      if (transitions.any(
        (value) => value is! String || !actions.contains(value),
      )) {
        throw AnimationBindingException(
          'bindings[$index] has an unknown transition',
        );
      }
    }
    final registry = AnimationBindingRegistry._(
      Map<String, Object?>.from(value),
      bindings,
    );
    _validateRuntimeProfiles(value, bindings);
    for (final entry in requiredStates.entries) {
      if (entry.value is! List) {
        throw AnimationBindingException(
          'requiredStates.${entry.key} must be a list',
        );
      }
      for (final state in entry.value! as List) {
        if (state is! String ||
            !bindings.any(
              (binding) =>
                  binding['actor'] == entry.key && binding['action'] == state,
            )) {
          throw AnimationBindingException(
            'required state ${entry.key}.$state is not bound',
          );
        }
      }
    }
    if (value['graphVersion'] != null) {
      if (value['graphVersion'] != 1 ||
          value['entryStates'] is! Map<String, Object?>) {
        throw const AnimationBindingException(
          'graphVersion 1 requires entryStates',
        );
      }
      final entryStates = value['entryStates']! as Map<String, Object?>;
      for (final actor in requiredStates.keys) {
        final entry = entryStates[actor];
        if (entry is! String) {
          throw AnimationBindingException('entryStates.$actor is required');
        }
        final reachable = <String>{entry};
        final pending = <String>[entry];
        while (pending.isNotEmpty) {
          final action = pending.removeLast();
          for (final binding in bindings.where(
            (candidate) =>
                candidate['actor'] == actor && candidate['action'] == action,
          )) {
            for (final target in binding['transitions']! as List) {
              if (reachable.add(target! as String)) pending.add(target);
            }
          }
        }
        final missing = (requiredStates[actor]! as List)
            .where((action) => !reachable.contains(action))
            .toList();
        if (missing.isNotEmpty) {
          throw AnimationBindingException(
            'hero graph $actor has unreachable actions: ${missing.join(', ')}',
          );
        }
      }
    }
    if (value['characterGraphVersion'] != null) {
      if (value['characterGraphVersion'] != 1 ||
          value['characterProfiles'] is! List ||
          value['characterCatalog'] is! Map<String, Object?>) {
        throw const AnimationBindingException(
          'characterGraphVersion 1 requires profiles and catalog totals',
        );
      }
      final catalog = value['characterCatalog']! as Map<String, Object?>;
      final profiles = value['characterProfiles']! as List;
      final profileKeys = <String>{};
      var contextCount = 0;
      final characterClips = <Object?>{};
      for (var index = 0; index < profiles.length; index++) {
        final raw = profiles[index];
        if (raw is! Map<String, Object?> ||
            raw['actor'] is! String ||
            raw['skin'] is! int ||
            raw['skinProfile'] is! String ||
            raw['costume'] is! String ||
            raw['context'] is! String ||
            raw['entryState'] is! String ||
            raw['requiredStates'] is! List ||
            raw['stateBindings'] is! Map<String, Object?>) {
          throw AnimationBindingException(
            'characterProfiles[$index] is invalid',
          );
        }
        final key = '${raw['actor']}|${raw['skin']}|${raw['costume']}';
        if (!profileKeys.add(key)) {
          throw AnimationBindingException('duplicate character profile $key');
        }
        final candidates = bindings.where(
          (binding) =>
              binding['actor'] == raw['actor'] &&
              binding['skin'] == raw['skin'] &&
              binding['costume'] == raw['costume'] &&
              binding['context'] == raw['context'],
        );
        final actions = candidates
            .map((binding) => binding['action']! as String)
            .toSet();
        if (candidates.any(
          (binding) => (binding['transitions']! as List).any(
            (target) => !actions.contains(target),
          ),
        )) {
          throw AnimationBindingException(
            'character profile $key has a cross-profile transition',
          );
        }
        final required = (raw['requiredStates']! as List)
            .cast<String>()
            .toSet();
        final entry = raw['entryState']! as String;
        if (!actions.containsAll(required) || !required.contains(entry)) {
          throw AnimationBindingException(
            'character profile $key has missing required states',
          );
        }
        final stateBindings = raw['stateBindings']! as Map<String, Object?>;
        if (stateBindings.values.any(
          (action) => action is! String || !actions.contains(action),
        )) {
          throw AnimationBindingException(
            'character profile $key has an unbound runtime state',
          );
        }
        final reachable = <String>{entry};
        final pending = <String>[entry];
        while (pending.isNotEmpty) {
          final action = pending.removeLast();
          for (final binding in candidates.where(
            (candidate) => candidate['action'] == action,
          )) {
            for (final target in binding['transitions']! as List) {
              if (target is String && reachable.add(target)) {
                pending.add(target);
              }
            }
          }
        }
        if (!reachable.containsAll(required)) {
          throw AnimationBindingException(
            'character graph $key has unreachable actions',
          );
        }
        contextCount += candidates.length;
        characterClips.addAll(candidates.map((binding) => binding['clip']));
      }
      if (catalog['contextCount'] != contextCount ||
          catalog['clipCount'] != characterClips.length) {
        throw const AnimationBindingException(
          'character graph catalog totals do not match bindings',
        );
      }
    }
    if (value['worldGraphVersion'] != null) {
      if (value['worldGraphVersion'] != 1 ||
          value['worldProfiles'] is! List ||
          value['worldCatalog'] is! Map<String, Object?>) {
        throw const AnimationBindingException(
          'worldGraphVersion 1 requires profiles and catalog totals',
        );
      }
      final profiles = value['worldProfiles']! as List;
      final catalog = value['worldCatalog']! as Map<String, Object?>;
      final keys = <String>{};
      final clips = <Object?>{};
      var contexts = 0;
      for (var index = 0; index < profiles.length; index++) {
        final raw = profiles[index];
        if (raw is! Map<String, Object?> ||
            raw['actor'] is! String ||
            raw['skin'] is! int ||
            raw['skinProfile'] is! String ||
            raw['costume'] is! String ||
            raw['context'] != 'world' ||
            raw['entryState'] is! String ||
            raw['requiredStates'] is! List ||
            raw['eventBindings'] is! Map<String, Object?> ||
            raw['restorePolicy'] != 'snapshot-without-replay') {
          throw AnimationBindingException('worldProfiles[$index] is invalid');
        }
        final key = '${raw['actor']}|${raw['skin']}';
        if (!keys.add(key)) {
          throw AnimationBindingException('duplicate world profile $key');
        }
        final candidates = bindings.where(
          (binding) =>
              binding['actor'] == raw['actor'] &&
              binding['skin'] == raw['skin'] &&
              binding['costume'] == raw['costume'] &&
              binding['context'] == 'world',
        );
        final actions = candidates
            .map((binding) => binding['action']! as String)
            .toSet();
        final required = (raw['requiredStates']! as List)
            .cast<String>()
            .toSet();
        final entry = raw['entryState']! as String;
        final events = raw['eventBindings']! as Map<String, Object?>;
        if (!actions.containsAll(required) ||
            !required.contains(entry) ||
            events.isEmpty ||
            events.values.any(
              (action) => action is! String || !actions.contains(action),
            ) ||
            candidates.any(
              (binding) =>
                  binding['trigger'] is! String ||
                  events[binding['trigger']] != binding['action'] ||
                  (binding['transitions']! as List).any(
                    (target) => !actions.contains(target),
                  ),
            )) {
          throw AnimationBindingException(
            'world profile $key has incomplete event/state bindings',
          );
        }
        final reachable = <String>{entry};
        final pending = <String>[entry];
        while (pending.isNotEmpty) {
          final action = pending.removeLast();
          for (final binding in candidates.where(
            (candidate) => candidate['action'] == action,
          )) {
            for (final target in binding['transitions']! as List) {
              if (target is String && reachable.add(target)) {
                pending.add(target);
              }
            }
          }
        }
        if (!reachable.containsAll(required)) {
          throw AnimationBindingException(
            'world graph $key has unreachable actions',
          );
        }
        contexts += candidates.length;
        clips.addAll(candidates.map((binding) => binding['clip']));
      }
      if (catalog['contextCount'] != contexts ||
          catalog['clipCount'] != clips.length) {
        throw const AnimationBindingException(
          'world graph catalog totals do not match bindings',
        );
      }
    }
    if (value['cinematicGraphVersion'] != null) {
      if (value['cinematicGraphVersion'] != 1 ||
          value['cinematicTimelines'] is! List ||
          value['cinematicCatalog'] is! Map<String, Object?>) {
        throw const AnimationBindingException(
          'cinematicGraphVersion 1 requires timelines and catalog totals',
        );
      }
      final timelines = value['cinematicTimelines']! as List;
      final catalog = value['cinematicCatalog']! as Map<String, Object?>;
      final ids = <String>{};
      final scriptEvents = <String>{};
      final clips = <Object?>{};
      var contexts = 0;
      for (var index = 0; index < timelines.length; index++) {
        final raw = timelines[index];
        if (raw is! Map<String, Object?> ||
            raw['id'] is! String ||
            raw['scriptEvent'] is! String ||
            raw['tracks'] is! List ||
            raw['cues'] is! List ||
            raw['terminalCue'] is! int ||
            raw['skipPolicy'] != 'apply-terminal-state' ||
            raw['interruptPolicy'] != 'checkpoint-current-cue' ||
            raw['controlPolicy'] != 'lock-on-start-return-on-terminal' ||
            raw['reentryPolicy'] !=
                'resume-checkpoint-or-restart-after-interrupt') {
          throw AnimationBindingException(
            'cinematicTimelines[$index] is invalid',
          );
        }
        final id = raw['id']! as String;
        final event = raw['scriptEvent']! as String;
        if (!ids.add(id) || !scriptEvents.add(event)) {
          throw AnimationBindingException('duplicate cinematic timeline $id');
        }
        final rawTracks = raw['tracks']! as List;
        final tracks = rawTracks.whereType<Map<String, Object?>>();
        final rawCues = raw['cues']! as List;
        if (tracks.isEmpty ||
            tracks.length != rawTracks.length ||
            rawCues.whereType<Map<String, Object?>>().length !=
                rawCues.length ||
            rawCues.length < 3) {
          throw AnimationBindingException(
            'cinematic timeline $id is incomplete',
          );
        }
        for (final track in tracks) {
          if (track['actor'] is! String ||
              track['dictionaryId'] is! int ||
              track['slot'] is! int ||
              track['action'] is! String ||
              track['cueIndex'] is! int) {
            throw AnimationBindingException(
              'cinematic track in $id is invalid',
            );
          }
          final matches = bindings.where(
            (binding) =>
                binding['context'] == 'cinematic' &&
                binding['timeline'] == id &&
                binding['actor'] == track['actor'] &&
                binding['dictionaryId'] == track['dictionaryId'] &&
                binding['slot'] == track['slot'] &&
                binding['action'] == track['action'] &&
                binding['cueIndex'] == track['cueIndex'] &&
                binding['trigger'] == '$event:cue-${track['cueIndex']}',
          );
          if (matches.length != 1) {
            throw AnimationBindingException(
              'cinematic track in $id has no exact event binding',
            );
          }
          clips.add(matches.single['clip']);
          contexts++;
        }
      }
      final cinematicBindings = bindings
          .where((binding) => binding['context'] == 'cinematic')
          .length;
      if (catalog['timelineCount'] != timelines.length ||
          catalog['contextCount'] != contexts ||
          catalog['clipCount'] != clips.length ||
          cinematicBindings != contexts) {
        throw const AnimationBindingException(
          'cinematic graph catalog totals do not match bindings',
        );
      }
    }
    return registry;
  }

  static void _validateRuntimeProfiles(
    Map<String, Object?> manifest,
    List<Map<String, Object?>> bindings,
  ) {
    final version = manifest['runtimeProfileVersion'];
    final profiles = manifest['runtimeProfiles'];
    if (version == null && profiles == null) return;
    if (version != 1 || profiles is! List || profiles.isEmpty) {
      throw const AnimationBindingException(
        'runtimeProfileVersion must equal 1 and runtimeProfiles must be non-empty',
      );
    }
    final ids = <String>{};
    for (var profileIndex = 0; profileIndex < profiles.length; profileIndex++) {
      final profile = profiles[profileIndex];
      if (profile is! Map<String, Object?> ||
          profile['id'] is! String ||
          !ids.add(profile['id']! as String) ||
          profile['actor'] is! String ||
          profile['skin'] is! int ||
          profile['costume'] is! String ||
          profile['context'] is! String ||
          profile['states'] is! Map<String, Object?> ||
          (profile['states']! as Map<String, Object?>).isEmpty) {
        throw AnimationBindingException(
          'runtimeProfiles[$profileIndex] is invalid',
        );
      }
      for (final state
          in (profile['states']! as Map<String, Object?>).entries) {
        final selector = state.value;
        if (selector is! Map<String, Object?> ||
            selector['action'] is! String ||
            selector['variant'] is! String) {
          throw AnimationBindingException(
            'runtimeProfiles[$profileIndex].states.${state.key} is invalid',
          );
        }
        final matches = bindings.where(
          (binding) =>
              binding['actor'] == profile['actor'] &&
              binding['skin'] == profile['skin'] &&
              binding['costume'] == profile['costume'] &&
              binding['context'] == profile['context'] &&
              binding['action'] == selector['action'] &&
              binding['variant'] == selector['variant'] &&
              binding['fallback'] == false,
        );
        if (matches.length != 1) {
          throw AnimationBindingException(
            'runtimeProfiles[$profileIndex].states.${state.key} must resolve '
            'exactly one non-fallback binding',
          );
        }
      }
      final complete = profile['complete'];
      if (complete != null && complete is! bool) {
        throw AnimationBindingException(
          'runtimeProfiles[$profileIndex].complete must be a boolean',
        );
      }
      if (complete == true) {
        final profileBindings = bindings
            .where(
              (binding) =>
                  binding['actor'] == profile['actor'] &&
                  binding['skin'] == profile['skin'] &&
                  binding['costume'] == profile['costume'] &&
                  binding['context'] == profile['context'],
            )
            .map((binding) => '${binding['action']}|${binding['variant']}')
            .toSet();
        final selectors = (profile['states']! as Map<String, Object?>).values
            .cast<Map<String, Object?>>()
            .map((selector) => '${selector['action']}|${selector['variant']}')
            .toList(growable: false);
        if (selectors.length != selectors.toSet().length ||
            selectors.toSet().difference(profileBindings).isNotEmpty ||
            profileBindings.difference(selectors.toSet()).isNotEmpty) {
          throw AnimationBindingException(
            'runtimeProfiles[$profileIndex] complete profile must select '
            'every exact binding once',
          );
        }
      }
    }
  }

  static void _validateEventTracks(
    Map<String, Object?> manifest,
    List<Map<String, Object?>> bindings,
  ) {
    final version = manifest['eventTrackVersion'];
    final tracks = manifest['eventTracks'];
    if (version == null && tracks == null) return;
    if (version != 1 || tracks is! List || tracks.isEmpty) {
      throw const AnimationBindingException(
        'eventTrackVersion must equal 1 and eventTracks must be non-empty',
      );
    }
    const types = {
      'footstep',
      'hit-window-open',
      'hit-window-close',
      'hurt-window-open',
      'hurt-window-close',
      'impulse',
      'root-motion',
      'object-state',
      'vfx',
      'sfx',
      'camera',
      'one-shot-complete',
    };
    final trackIds = <String>{};
    for (var trackIndex = 0; trackIndex < tracks.length; trackIndex++) {
      final track = tracks[trackIndex];
      if (track is! Map<String, Object?> ||
          track['id'] is! String ||
          !trackIds.add(track['id']! as String) ||
          track['actor'] is! String ||
          track['action'] is! String ||
          track['context'] is! String ||
          track['loop'] is! bool ||
          track['events'] is! List ||
          (track['events']! as List).isEmpty) {
        throw AnimationBindingException('eventTracks[$trackIndex] is invalid');
      }
      final matches = bindings.where(
        (binding) =>
            binding['actor'] == track['actor'] &&
            binding['action'] == track['action'] &&
            binding['context'] == track['context'] &&
            binding['loop'] == track['loop'],
      );
      if (matches.isEmpty) {
        throw AnimationBindingException(
          'eventTracks[$trackIndex] has no matching binding',
        );
      }
      var previous = -1.0;
      final eventIds = <String>{};
      for (final event in track['events']! as List) {
        if (event is! Map<String, Object?> ||
            event['id'] is! String ||
            !eventIds.add(event['id']! as String) ||
            !types.contains(event['type']) ||
            event['phase'] is! num ||
            (event['phase']! as num) < previous ||
            (event['phase']! as num) < 0 ||
            (event['phase']! as num) > 1 ||
            event['target'] is! String ||
            event['value'] is! String) {
          throw AnimationBindingException(
            'eventTracks[$trackIndex] events must be typed, unique and ordered',
          );
        }
        previous = (event['phase']! as num).toDouble();
      }
      if (track['loop'] == false &&
          !(track['events']! as List).any(
            (event) =>
                (event as Map<String, Object?>)['type'] == 'one-shot-complete',
          )) {
        throw AnimationBindingException(
          'eventTracks[$trackIndex] one-shot has no completion event',
        );
      }
    }
  }

  static AnimationBindingRegistry decode(Uint8List bytes) =>
      parse(jsonDecode(utf8.decode(bytes)));

  Map<String, Object?> resolve(AnimationBindingQuery query) {
    var matches = bindings
        .where(
          (binding) =>
              binding['actor'] == query.actor &&
              binding['skin'] == query.skin &&
              binding['costume'] == query.costume &&
              binding['action'] == query.action &&
              binding['context'] == query.context &&
              binding['variant'] == query.variant,
        )
        .toList();
    if (matches.isEmpty && query.variant != null) {
      matches = bindings
          .where(
            (binding) =>
                binding['actor'] == query.actor &&
                binding['skin'] == query.skin &&
                binding['costume'] == query.costume &&
                binding['action'] == query.action &&
                binding['context'] == query.context &&
                binding['fallback'] == true,
          )
          .toList();
    }
    matches.sort(
      (a, b) => (b['priority']! as int).compareTo(a['priority']! as int),
    );
    if (matches.length > 1 &&
        matches[0]['priority'] == matches[1]['priority']) {
      throw AnimationBindingException(
        'ambiguous binding ${query.actor}/${query.action}',
      );
    }
    if (matches.length > 1) matches = [matches.first];
    if (matches.length != 1) {
      throw AnimationBindingException(
        matches.isEmpty
            ? 'unknown binding ${query.actor}/${query.action}'
            : 'ambiguous binding ${query.actor}/${query.action}',
      );
    }
    return matches.single;
  }

  Map<String, Object?> select({
    required String actor,
    required int skin,
    required String costume,
    required String action,
    String context = 'gameplay',
    int selector = 0,
  }) {
    final matches =
        bindings
            .where(
              (binding) =>
                  binding['actor'] == actor &&
                  binding['skin'] == skin &&
                  binding['costume'] == costume &&
                  binding['action'] == action &&
                  binding['context'] == context,
            )
            .toList()
          ..sort(
            (a, b) => (a['variant']?.toString() ?? '').compareTo(
              b['variant']?.toString() ?? '',
            ),
          );
    if (matches.isEmpty) {
      throw AnimationBindingException('unknown binding $actor/$action');
    }
    return matches[selector.abs() % matches.length];
  }

  Map<String, Object?> resolveRuntimeState({
    required String profileId,
    required String state,
  }) {
    final profiles = (manifest['runtimeProfiles'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    final matches = profiles.where((profile) => profile['id'] == profileId);
    if (matches.length != 1) {
      throw AnimationBindingException('unknown runtime profile $profileId');
    }
    final profile = matches.single;
    final selector = (profile['states']! as Map<String, Object?>)[state];
    if (selector is! Map<String, Object?>) {
      throw AnimationBindingException(
        'unknown runtime state $profileId/$state',
      );
    }
    return resolve(
      AnimationBindingQuery(
        actor: profile['actor']! as String,
        skin: profile['skin']! as int,
        costume: profile['costume']! as String,
        action: selector['action']! as String,
        context: profile['context']! as String,
        variant: selector['variant']! as String,
      ),
    );
  }

  bool allowsTransition(Map<String, Object?> from, Map<String, Object?> to) =>
      from['actor'] == to['actor'] &&
      (from['transitions']! as List).contains(to['action']);

  List<String> phasesCrossed(
    Map<String, Object?> binding,
    double from,
    double to,
  ) {
    if (from < 0 || to < from || to > 1) {
      throw const AnimationBindingException(
        'phase interval must be ordered in [0, 1]',
      );
    }
    final phases = binding['phases'];
    if (phases is! Map<String, Object?>) return const [];
    return phases.entries
        .where((entry) {
          final value = (entry.value! as num).toDouble();
          return value > from && value <= to;
        })
        .map((entry) => entry.key)
        .toList(growable: false);
  }
}
