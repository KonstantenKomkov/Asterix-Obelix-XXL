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
      .where((binding) => binding['actor'] == actor)
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
    return registry;
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
