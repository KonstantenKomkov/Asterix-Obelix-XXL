import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/game_settings.dart';

@lazySingleton
final class PreferencesSettingsDataSource {
  const PreferencesSettingsDataSource(this._preferences);

  final SharedPreferences _preferences;

  GameSettings read() {
    return GameSettings(
      musicVolume: _preferences.getDouble('musicVolume') ?? 0.8,
      effectsVolume: _preferences.getDouble('effectsVolume') ?? 0.8,
      fullscreen: _preferences.getBool('fullscreen') ?? false,
      subtitles: _preferences.getBool('subtitles') ?? true,
    );
  }

  Future<void> write(GameSettings settings) async {
    await Future.wait([
      _preferences.setDouble('musicVolume', settings.musicVolume),
      _preferences.setDouble('effectsVolume', settings.effectsVolume),
      _preferences.setBool('fullscreen', settings.fullscreen),
      _preferences.setBool('subtitles', settings.subtitles),
    ]);
  }
}
