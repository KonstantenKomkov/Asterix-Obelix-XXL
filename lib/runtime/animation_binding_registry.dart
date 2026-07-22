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
    final actions = bindings.map((binding) => binding['action']).toSet();
    for (var index = 0; index < bindings.length; index++) {
      final transitions = bindings[index]['transitions']! as List;
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
}
