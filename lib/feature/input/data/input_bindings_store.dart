import 'package:shared_preferences/shared_preferences.dart';

import '../domain/game_input.dart';

final class InputBindingsStore {
  const InputBindingsStore(this.preferences);
  static const key = 'inputBindingsV1';
  final SharedPreferences preferences;

  InputBindings load() {
    final encoded = preferences.getString(key);
    return encoded == null ? InputBindings() : InputBindings.decode(encoded);
  }

  Future<void> save(InputBindings bindings) =>
      preferences.setString(key, bindings.encode());
}
