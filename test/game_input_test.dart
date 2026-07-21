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
