import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/settings_bloc.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
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
                    'Звук',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  _VolumeSlider(
                    label: 'Музыка',
                    value: settings.musicVolume,
                    onChanged: (value) => context.read<SettingsBloc>().add(
                      SettingsEvent.changed(
                        settings.copyWith(musicVolume: value),
                      ),
                    ),
                  ),
                  _VolumeSlider(
                    label: 'Эффекты',
                    value: settings.effectsVolume,
                    onChanged: (value) => context.read<SettingsBloc>().add(
                      SettingsEvent.changed(
                        settings.copyWith(effectsVolume: value),
                      ),
                    ),
                  ),
                  const Divider(height: 48),
                  SwitchListTile(
                    title: const Text('Полноэкранный режим'),
                    subtitle: const Text(
                      'Применение окна будет подключено к macOS-слою',
                    ),
                    value: settings.fullscreen,
                    onChanged: (value) => context.read<SettingsBloc>().add(
                      SettingsEvent.changed(
                        settings.copyWith(fullscreen: value),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Субтитры'),
                    value: settings.subtitles,
                    onChanged: (value) => context.read<SettingsBloc>().add(
                      SettingsEvent.changed(
                        settings.copyWith(subtitles: value),
                      ),
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
