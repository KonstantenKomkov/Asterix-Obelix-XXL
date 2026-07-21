import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/game_settings.dart';

part 'settings_event.freezed.dart';

@freezed
sealed class SettingsEvent with _$SettingsEvent {
  const factory SettingsEvent.loadRequested() = SettingsLoadRequested;

  const factory SettingsEvent.changed(GameSettings settings) = SettingsChanged;
}
