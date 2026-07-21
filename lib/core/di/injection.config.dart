// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:asterix_xxl/core/di/app_module.dart' as _i347;
import 'package:asterix_xxl/feature/settings/data/datasources/preferences_settings_data_source.dart'
    as _i240;
import 'package:asterix_xxl/feature/settings/data/repositories/settings_repository_impl.dart'
    as _i40;
import 'package:asterix_xxl/feature/settings/domain/repositories/settings_repository.dart'
    as _i64;
import 'package:asterix_xxl/feature/settings/domain/usecases/load_settings.dart'
    as _i563;
import 'package:asterix_xxl/feature/settings/domain/usecases/save_settings.dart'
    as _i289;
import 'package:asterix_xxl/feature/settings/presentation/bloc/settings_bloc.dart'
    as _i635;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:shared_preferences/shared_preferences.dart' as _i460;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final appModule = _$AppModule();
    await gh.factoryAsync<_i460.SharedPreferences>(
      () => appModule.sharedPreferences,
      preResolve: true,
    );
    gh.lazySingleton<_i240.PreferencesSettingsDataSource>(
      () => _i240.PreferencesSettingsDataSource(gh<_i460.SharedPreferences>()),
    );
    gh.lazySingleton<_i64.SettingsRepository>(
      () => _i40.SettingsRepositoryImpl(
        gh<_i240.PreferencesSettingsDataSource>(),
      ),
    );
    gh.lazySingleton<_i563.LoadSettings>(
      () => _i563.LoadSettings(gh<_i64.SettingsRepository>()),
    );
    gh.lazySingleton<_i289.SaveSettings>(
      () => _i289.SaveSettings(gh<_i64.SettingsRepository>()),
    );
    gh.factory<_i635.SettingsBloc>(
      () => _i635.SettingsBloc(
        loadSettings: gh<_i563.LoadSettings>(),
        saveSettings: gh<_i289.SaveSettings>(),
      ),
    );
    return this;
  }
}

class _$AppModule extends _i347.AppModule {}
