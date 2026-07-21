import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/localization/app_strings.dart';
import '../data/input_bindings_store.dart';
import '../domain/game_input.dart';

class ControlsPage extends StatefulWidget {
  const ControlsPage({super.key});
  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  static const _gamepadOptions = <String, String>{
    'leftX-': 'Left stick ←',
    'leftX+': 'Left stick →',
    'leftY+': 'Left stick ↑',
    'leftY-': 'Left stick ↓',
    'buttonA': 'A / Cross',
    'buttonX': 'X / Square',
    'buttonB': 'B / Circle',
    'menu': 'Menu / Options',
  };
  InputBindings _bindings = InputBindings();
  InputBindingsStore? _store;
  GameAction? _capturing;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((preferences) {
      if (!mounted) return;
      setState(() {
        _store = InputBindingsStore(preferences);
        _bindings = _store!.load();
      });
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_capturing == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    setState(() {
      _bindings.keyboard[_capturing!] = event.logicalKey.keyId;
      _capturing = null;
    });
    _store?.save(_bindings);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.controls)),
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Text(
              strings.keyboard,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final action in GameAction.values)
              ListTile(
                title: Text(strings.action(action.name)),
                subtitle: DropdownButton<String>(
                  key: Key('pad-bind-${action.name}'),
                  value: _bindings.gamepad[action],
                  isDense: true,
                  items: [
                    for (final option in _gamepadOptions.entries)
                      DropdownMenuItem(
                        value: option.key,
                        child: Text(option.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _bindings.gamepad[action] = value);
                    _store?.save(_bindings);
                  },
                ),
                trailing: OutlinedButton(
                  key: Key('bind-${action.name}'),
                  onPressed: () => setState(() => _capturing = action),
                  child: Text(
                    _capturing == action
                        ? strings.pressKey
                        : LogicalKeyboardKey(
                            _bindings.keyboard[action]!,
                          ).keyLabel,
                  ),
                ),
              ),
            const Divider(),
            Text(strings.reconnectHint),
            TextButton(
              onPressed: () {
                setState(() => _bindings = InputBindings());
                _store?.save(_bindings);
              },
              child: Text(strings.resetBindings),
            ),
          ],
        ),
      ),
    );
  }
}
