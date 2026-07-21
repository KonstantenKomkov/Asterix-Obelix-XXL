import 'package:injectable/injectable.dart';

import '../../domain/entities/game_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/preferences_settings_data_source.dart';

@LazySingleton(as: SettingsRepository)
final class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl(this._dataSource);

  final PreferencesSettingsDataSource _dataSource;

  @override
  Future<GameSettings> load() async => _dataSource.read();

  @override
  Future<void> save(GameSettings settings) => _dataSource.write(settings);
}
