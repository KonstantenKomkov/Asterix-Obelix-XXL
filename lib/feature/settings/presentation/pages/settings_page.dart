import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/localization/app_strings.dart';
import '../bloc/settings_bloc.dart';
import '../../../input/presentation/controls_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          final settings = state.settings;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  Text(
                    strings.sound,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  _VolumeSlider(
                    label: strings.music,
                    value: settings.musicVolume,
                    onChanged: (value) => context.read<SettingsBloc>().add(
                      SettingsEvent.changed(
                        settings.copyWith(musicVolume: value),
                      ),
                    ),
                  ),
                  _VolumeSlider(
                    label: strings.effects,
                    value: settings.effectsVolume,
                    onChanged: (value) => context.read<SettingsBloc>().add(
                      SettingsEvent.changed(
                        settings.copyWith(effectsVolume: value),
                      ),
                    ),
                  ),
                  const Divider(height: 48),
                  SwitchListTile(
                    title: Text(strings.fullscreen),
                    subtitle: Text(strings.fullscreenHint),
                    value: settings.fullscreen,
                    onChanged: (value) => context.read<SettingsBloc>().add(
                      SettingsEvent.changed(
                        settings.copyWith(fullscreen: value),
                      ),
                    ),
                  ),
                  const Divider(height: 48),
                  ListTile(
                    key: const Key('controls-settings'),
                    title: Text(strings.controls),
                    subtitle: Text(strings.controlsHint),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ControlsPage(),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: Text(strings.subtitles),
                    value: settings.subtitles,
                    onChanged: (value) => context.read<SettingsBloc>().add(
                      SettingsEvent.changed(
                        settings.copyWith(subtitles: value),
                      ),
                    ),
                  ),
                  const Divider(height: 48),
                  ListTile(
                    title: Text(strings.language),
                    trailing: DropdownButton<String>(
                      key: const Key('language-selector'),
                      value: settings.languageCode,
                      items: [
                        DropdownMenuItem(
                          value: 'ru',
                          child: Text(strings.russian),
                        ),
                        DropdownMenuItem(
                          value: 'en',
                          child: Text(strings.english),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        context.read<SettingsBloc>().add(
                          SettingsEvent.changed(
                            settings.copyWith(languageCode: value),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: Slider(value: value, onChanged: onChanged),
        ),
        SizedBox(width: 48, child: Text('${(value * 100).round()}%')),
      ],
    );
  }
}
