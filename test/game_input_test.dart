import 'package:asterix_xxl/feature/input/domain/game_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keyboard and controller use one action snapshot with pause edge', () {
    final router = GameInputRouter();
    var snapshot = router.handleKey(
      const KeyDownEvent(
        logicalKey: LogicalKeyboardKey.keyW,
        physicalKey: PhysicalKeyboardKey.keyW,
        timeStamp: Duration.zero,
      ),
    );
    expect(snapshot.pressed(GameAction.moveForward), isTrue);
    snapshot = router.handleController(const {
      'type': 'control',
      'control': 'buttonA',
      'value': 1.0,
    });
    expect(snapshot.pressed(GameAction.jump), isTrue);
    snapshot = router.handleKey(
      const KeyDownEvent(
        logicalKey: LogicalKeyboardKey.keyE,
        physicalKey: PhysicalKeyboardKey.keyE,
        timeStamp: Duration.zero,
      ),
    );
    expect(snapshot.pressed(GameAction.interact), isTrue);
    snapshot = router.handleController(const {
      'type': 'control',
      'control': 'menu',
      'value': 1.0,
    });
    expect(router.consumePauseEdge(snapshot), isTrue);
    expect(router.consumePauseEdge(snapshot), isFalse);
  });

  test('disconnect clears controller state and reconnect accepts input', () {
    final router = GameInputRouter();
    router.handleController(const {
      'type': 'control',
      'control': 'buttonX',
      'value': 1.0,
    });
    var snapshot = router.handleController(const {'type': 'disconnected'});
    expect(snapshot.controllerConnected, isFalse);
    expect(snapshot.pressed(GameAction.attack), isFalse);
    snapshot = router.handleController(const {'type': 'connected'});
    snapshot = router.handleController(const {
      'type': 'control',
      'control': 'buttonX',
      'value': 1.0,
    });
    expect(snapshot.controllerConnected, isTrue);
    expect(snapshot.pressed(GameAction.attack), isTrue);
  });

  test(
    'native macOS keyboard fallback preserves arrow key-down and key-up',
    () {
      final router = GameInputRouter();
      var snapshot = router.handleController(const {
        'type': 'keyboard',
        'action': 'moveForward',
        'value': 1.0,
      });
      expect(snapshot.pressed(GameAction.moveForward), isTrue);
      snapshot = router.handleController(const {
        'type': 'keyboard',
        'action': 'moveForward',
        'value': 0.0,
      });
      expect(snapshot.pressed(GameAction.moveForward), isFalse);
    },
  );

  test('arrow key-down and key-up drive all movement actions', () {
    final router = GameInputRouter();
    expect(router.handlesKey(LogicalKeyboardKey.arrowLeft), isTrue);
    const arrows = <(LogicalKeyboardKey, PhysicalKeyboardKey, GameAction)>[
      (
        LogicalKeyboardKey.arrowLeft,
        PhysicalKeyboardKey.arrowLeft,
        GameAction.moveLeft,
      ),
      (
        LogicalKeyboardKey.arrowRight,
        PhysicalKeyboardKey.arrowRight,
        GameAction.moveRight,
      ),
      (
        LogicalKeyboardKey.arrowUp,
        PhysicalKeyboardKey.arrowUp,
        GameAction.moveForward,
      ),
      (
        LogicalKeyboardKey.arrowDown,
        PhysicalKeyboardKey.arrowDown,
        GameAction.moveBackward,
      ),
    ];

    for (final (logical, physical, action) in arrows) {
      var snapshot = router.handleKey(
        KeyDownEvent(
          logicalKey: logical,
          physicalKey: physical,
          timeStamp: Duration.zero,
        ),
      );
      expect(snapshot.pressed(action), isTrue, reason: '$logical key-down');
      snapshot = router.handleKey(
        KeyUpEvent(
          logicalKey: logical,
          physicalKey: physical,
          timeStamp: Duration.zero,
        ),
      );
      expect(snapshot.pressed(action), isFalse, reason: '$logical key-up');
    }
  });

  test('WASD and gamepad axes resolve to the same movement actions', () {
    const cases =
        <(LogicalKeyboardKey, PhysicalKeyboardKey, String, double, GameAction)>[
          (
            LogicalKeyboardKey.keyA,
            PhysicalKeyboardKey.keyA,
            'leftX',
            -1,
            GameAction.moveLeft,
          ),
          (
            LogicalKeyboardKey.keyD,
            PhysicalKeyboardKey.keyD,
            'leftX',
            1,
            GameAction.moveRight,
          ),
          (
            LogicalKeyboardKey.keyW,
            PhysicalKeyboardKey.keyW,
            'leftY',
            1,
            GameAction.moveForward,
          ),
          (
            LogicalKeyboardKey.keyS,
            PhysicalKeyboardKey.keyS,
            'leftY',
            -1,
            GameAction.moveBackward,
          ),
        ];

    for (final (logical, physical, control, value, action) in cases) {
      final keyboard = GameInputRouter().handleKey(
        KeyDownEvent(
          logicalKey: logical,
          physicalKey: physical,
          timeStamp: Duration.zero,
        ),
      );
      final gamepad = GameInputRouter().handleController({
        'type': 'control',
        'control': control,
        'value': value,
      });
      expect(
        keyboard.value(action),
        gamepad.value(action),
        reason: action.name,
      );
    }
  });

  test(
    'releasing an arrow preserves a remapped key held for the same action',
    () {
      final router = GameInputRouter();
      router.bindings.keyboard[GameAction.moveLeft] =
          LogicalKeyboardKey.keyQ.keyId;
      router.handleKey(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyQ,
          physicalKey: PhysicalKeyboardKey.keyQ,
          timeStamp: Duration.zero,
        ),
      );
      router.handleKey(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowLeft,
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
      );
      final snapshot = router.handleKey(
        const KeyUpEvent(
          logicalKey: LogicalKeyboardKey.arrowLeft,
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(snapshot.pressed(GameAction.moveLeft), isTrue);
    },
  );

  test('bindings round-trip and malformed versions fall back safely', () {
    final bindings = InputBindings();
    bindings.keyboard[GameAction.jump] = LogicalKeyboardKey.enter.keyId;
    final restored = InputBindings.decode(bindings.encode());
    expect(restored.keyboard[GameAction.jump], LogicalKeyboardKey.enter.keyId);
    expect(
      InputBindings.decode('{"version":99}').keyboard[GameAction.pause],
      LogicalKeyboardKey.escape.keyId,
    );
  });
}
