import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/game_settings.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/save_settings.dart';
import 'settings_event.dart';

export 'settings_event.dart';

part 'settings_state.dart';

@injectable
final class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    required LoadSettings loadSettings,
    required SaveSettings saveSettings,
  }) : _loadSettings = loadSettings,
       _saveSettings = saveSettings,
       super(const SettingsState()) {
    on<SettingsLoadRequested>(_onLoadRequested);
    on<SettingsChanged>(_onChanged);
  }

  final LoadSettings _loadSettings;
  final SaveSettings _saveSettings;

  Future<void> _onLoadRequested(
    SettingsLoadRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    final settings = await _loadSettings();
    emit(SettingsState(settings: settings));
  }

  Future<void> _onChanged(
    SettingsChanged event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsState(settings: event.settings));
    await _saveSettings(event.settings);
  }
}
