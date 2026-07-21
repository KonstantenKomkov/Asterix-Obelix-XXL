import 'package:asterix_xxl/feature/settings/data/datasources/preferences_settings_data_source.dart';
import 'package:asterix_xxl/feature/settings/domain/entities/game_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('volume settings persist and clamp invalid values', () async {
    SharedPreferences.setMockInitialValues({
      'musicVolume': 2.0,
      'effectsVolume': -1.0,
      'languageCode': 'unsupported',
    });
    final preferences = await SharedPreferences.getInstance();
    final source = PreferencesSettingsDataSource(preferences);
    expect(source.read().musicVolume, 1);
    expect(source.read().effectsVolume, 0);
    expect(source.read().languageCode, 'ru');
    await source.write(
      const GameSettings(musicVolume: -4, effectsVolume: 8, languageCode: 'en'),
    );
    expect(preferences.getDouble('musicVolume'), 0);
    expect(preferences.getDouble('effectsVolume'), 1);
    expect(preferences.getString('languageCode'), 'en');
  });
}
