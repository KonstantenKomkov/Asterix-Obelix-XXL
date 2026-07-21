import 'package:injectable/injectable.dart';

import '../entities/game_settings.dart';
import '../repositories/settings_repository.dart';

@lazySingleton
final class LoadSettings {
  const LoadSettings(this._repository);

  final SettingsRepository _repository;

  Future<GameSettings> call() => _repository.load();
}
