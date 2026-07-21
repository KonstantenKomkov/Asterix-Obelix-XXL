import 'package:injectable/injectable.dart';

import '../entities/game_settings.dart';
import '../repositories/settings_repository.dart';

@lazySingleton
final class SaveSettings {
  const SaveSettings(this._repository);

  final SettingsRepository _repository;

  Future<void> call(GameSettings settings) => _repository.save(settings);
}
