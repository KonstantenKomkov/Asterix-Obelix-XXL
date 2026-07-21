import '../entities/game_settings.dart';

abstract interface class SettingsRepository {
  Future<GameSettings> load();
  Future<void> save(GameSettings settings);
}
