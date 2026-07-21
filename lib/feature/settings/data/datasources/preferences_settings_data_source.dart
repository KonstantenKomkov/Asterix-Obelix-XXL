import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/game_settings.dart';

@lazySingleton
final class PreferencesSettingsDataSource {
  const PreferencesSettingsDataSource(this._preferences);

  final SharedPreferences _preferences;

  GameSettings read() {
    return GameSettings(
      musicVolume: (_preferences.getDouble('musicVolume') ?? 0.8).clamp(0, 1),
      effectsVolume: (_preferences.getDouble('effectsVolume') ?? 0.8).clamp(
        0,
        1,
      ),
      languageCode: switch (_preferences.getString('languageCode')) {
        'en' => 'en',
        _ => 'ru',
      },
      fullscreen: _preferences.getBool('fullscreen') ?? false,
      subtitles: _preferences.getBool('subtitles') ?? true,
    );
  }

  Future<void> write(GameSettings settings) async {
    final music = settings.musicVolume.clamp(0.0, 1.0);
    final effects = settings.effectsVolume.clamp(0.0, 1.0);
    await Future.wait([
      _preferences.setDouble('musicVolume', music),
      _preferences.setDouble('effectsVolume', effects),
      _preferences.setBool('fullscreen', settings.fullscreen),
      _preferences.setBool('subtitles', settings.subtitles),
      _preferences.setString(
        'languageCode',
        settings.languageCode == 'en' ? 'en' : 'ru',
      ),
    ]);
  }
}
