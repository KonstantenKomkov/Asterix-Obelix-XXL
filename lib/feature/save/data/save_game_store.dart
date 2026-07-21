import 'package:shared_preferences/shared_preferences.dart';

import '../domain/save_game.dart';

final class SaveGameStore {
  const SaveGameStore(this.preferences);
  static const key = 'verticalSliceSaveV2';
  final SharedPreferences preferences;

  SaveGame? load() {
    final encoded = preferences.getString(key);
    if (encoded == null) return null;
    try {
      return SaveGame.decode(encoded);
    } on FormatException {
      return null;
    }
  }

  Future<bool> save(SaveGame game) => preferences.setString(key, game.encode());
  Future<bool> clear() => preferences.remove(key);
}
