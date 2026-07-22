import 'package:asterix_xxl/runtime/animation_binding_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> manifest() => {
    'schemaVersion': 1,
    'requiredStates': {
      'hero': ['idle'],
    },
    'bindings': [
      {
        'actor': 'hero',
        'skin': 4,
        'costume': 'default',
        'action': 'idle',
        'context': 'gameplay',
        'variant': null,
        'clip': '0001.animation.json',
        'loop': true,
        'priority': 0,
        'fallback': false,
        'skeletonNodes': 58,
        'transitions': <String>[],
      },
    ],
  };

  test('resolves an exact data-driven binding', () {
    final registry = AnimationBindingRegistry.parse(manifest());
    expect(
      registry.resolve(
        const AnimationBindingQuery(
          actor: 'hero',
          skin: 4,
          costume: 'default',
          action: 'idle',
          context: 'gameplay',
        ),
      )['clip'],
      '0001.animation.json',
    );
  });

  test('rejects unknown, ambiguous and incomplete registries', () {
    final registry = AnimationBindingRegistry.parse(manifest());
    expect(
      () => registry.resolve(
        const AnimationBindingQuery(
          actor: 'hero',
          skin: 4,
          costume: 'default',
          action: 'run',
          context: 'gameplay',
        ),
      ),
      throwsA(isA<AnimationBindingException>()),
    );
    final duplicate = manifest();
    (duplicate['bindings']! as List).add(
      Map<String, Object?>.from(
        (duplicate['bindings']! as List).first as Map<String, Object?>,
      ),
    );
    expect(
      () => AnimationBindingRegistry.parse(duplicate),
      throwsA(isA<AnimationBindingException>()),
    );
    final incomplete = manifest();
    incomplete['requiredStates'] = {
      'hero': ['death'],
    };
    expect(
      () => AnimationBindingRegistry.parse(incomplete),
      throwsA(isA<AnimationBindingException>()),
    );
  });
}
