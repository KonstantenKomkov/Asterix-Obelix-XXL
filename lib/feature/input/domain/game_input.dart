import 'dart:convert';

import 'package:flutter/services.dart';

enum GameAction {
  moveLeft,
  moveRight,
  moveForward,
  moveBackward,
  jump,
  attack,
  pause,
}

final defaultKeyboardBindings = <GameAction, int>{
  GameAction.moveLeft: LogicalKeyboardKey.keyA.keyId,
  GameAction.moveRight: LogicalKeyboardKey.keyD.keyId,
  GameAction.moveForward: LogicalKeyboardKey.keyW.keyId,
  GameAction.moveBackward: LogicalKeyboardKey.keyS.keyId,
  GameAction.jump: LogicalKeyboardKey.space.keyId,
  GameAction.attack: LogicalKeyboardKey.keyJ.keyId,
  GameAction.pause: LogicalKeyboardKey.escape.keyId,
};

const defaultGamepadBindings = <GameAction, String>{
  GameAction.moveLeft: 'leftX-',
  GameAction.moveRight: 'leftX+',
  GameAction.moveForward: 'leftY+',
  GameAction.moveBackward: 'leftY-',
  GameAction.jump: 'buttonA',
  GameAction.attack: 'buttonX',
  GameAction.pause: 'menu',
};

final class InputBindings {
  InputBindings({
    Map<GameAction, int>? keyboard,
    Map<GameAction, String>? gamepad,
  }) : keyboard = {...defaultKeyboardBindings, ...?keyboard},
       gamepad = {...defaultGamepadBindings, ...?gamepad};

  final Map<GameAction, int> keyboard;
  final Map<GameAction, String> gamepad;

  String encode() => jsonEncode({
    'version': 1,
    'keyboard': {
      for (final entry in keyboard.entries) entry.key.name: entry.value,
    },
    'gamepad': {
      for (final entry in gamepad.entries) entry.key.name: entry.value,
    },
  });

  factory InputBindings.decode(String value) {
    try {
      final root = jsonDecode(value) as Map<String, dynamic>;
      if (root['version'] != 1) return InputBindings();
      final keyboard = root['keyboard'] as Map<String, dynamic>? ?? const {};
      final gamepad = root['gamepad'] as Map<String, dynamic>? ?? const {};
      return InputBindings(
        keyboard: {
          for (final action in GameAction.values)
            if (keyboard[action.name] is int)
              action: keyboard[action.name] as int,
        },
        gamepad: {
          for (final action in GameAction.values)
            if (gamepad[action.name] is String)
              action: gamepad[action.name] as String,
        },
      );
    } on Object {
      return InputBindings();
    }
  }
}

final class GameInputSnapshot {
  const GameInputSnapshot(this.values, {required this.controllerConnected});
  final Map<GameAction, double> values;
  final bool controllerConnected;
  double value(GameAction action) => values[action] ?? 0;
  bool pressed(GameAction action) => value(action) > 0.5;
}

final class GameInputRouter {
  GameInputRouter({InputBindings? bindings})
    : bindings = bindings ?? InputBindings();

  InputBindings bindings;
  final Set<int> _keys = {};
  final Map<String, double> _controls = {};
  bool _controllerConnected = false;
  bool _pauseWasPressed = false;

  GameInputSnapshot handleKey(KeyEvent event) {
    final id = event.logicalKey.keyId;
    if (event is KeyDownEvent || event is KeyRepeatEvent) _keys.add(id);
    if (event is KeyUpEvent) _keys.remove(id);
    return snapshot();
  }

  GameInputSnapshot handleController(Map<Object?, Object?> event) {
    final type = event['type'];
    if (type == 'connected') _controllerConnected = true;
    if (type == 'disconnected') {
      _controllerConnected = false;
      _controls.clear();
    }
    if (type == 'control') {
      _controllerConnected = true;
      final control = event['control'];
      final value = event['value'];
      if (control is String && value is num) {
        _controls[control] = value.toDouble();
      }
    }
    return snapshot();
  }

  void reset() {
    _keys.clear();
    _controls.clear();
    _pauseWasPressed = false;
  }

  GameInputSnapshot snapshot() {
    final values = <GameAction, double>{};
    for (final action in GameAction.values) {
      final keyboard = _keys.contains(bindings.keyboard[action]) ? 1.0 : 0.0;
      final binding = bindings.gamepad[action];
      var gamepad = 0.0;
      if (binding != null) {
        final suffix = binding.endsWith('+')
            ? '+'
            : binding.endsWith('-')
            ? '-'
            : '';
        final name = suffix.isEmpty
            ? binding
            : binding.substring(0, binding.length - 1);
        final raw = _controls[name] ?? 0;
        gamepad = suffix == '+'
            ? raw.clamp(0, 1)
            : suffix == '-'
            ? (-raw).clamp(0, 1)
            : raw.clamp(0, 1);
      }
      values[action] = keyboard > gamepad ? keyboard : gamepad;
    }
    return GameInputSnapshot(values, controllerConnected: _controllerConnected);
  }

  bool consumePauseEdge(GameInputSnapshot snapshot) {
    final pressed = snapshot.pressed(GameAction.pause);
    final edge = pressed && !_pauseWasPressed;
    _pauseWasPressed = pressed;
    return edge;
  }
}

String actionLabel(GameAction action) => switch (action) {
  GameAction.moveLeft => 'Влево',
  GameAction.moveRight => 'Вправо',
  GameAction.moveForward => 'Вперёд',
  GameAction.moveBackward => 'Назад',
  GameAction.jump => 'Прыжок',
  GameAction.attack => 'Атака',
  GameAction.pause => 'Пауза',
};
