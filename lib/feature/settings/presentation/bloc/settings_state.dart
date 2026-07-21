part of 'settings_bloc.dart';

final class SettingsState {
  const SettingsState({
    this.settings = const GameSettings(),
    this.isLoading = false,
  });

  final GameSettings settings;
  final bool isLoading;

  SettingsState copyWith({GameSettings? settings, bool? isLoading}) {
    return SettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
