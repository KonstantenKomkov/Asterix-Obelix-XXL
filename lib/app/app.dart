import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/di/injection.dart';
import '../core/theme/app_theme.dart';
import '../core/localization/app_strings.dart';
import '../feature/main_menu/presentation/pages/home_page.dart';
import '../feature/game/presentation/pages/game_page.dart';
import '../feature/settings/presentation/bloc/settings_bloc.dart';

class AsterixXxlApp extends StatelessWidget {
  const AsterixXxlApp({super.key});

  @override
  Widget build(BuildContext context) {
    const assetPackage = String.fromEnvironment('ASTERIX_ASSET_PACKAGE');
    return BlocProvider(
      create: (_) =>
          getIt<SettingsBloc>()..add(const SettingsEvent.loadRequested()),
      child: BlocConsumer<SettingsBloc, SettingsState>(
        listenWhen: (previous, current) =>
            previous.settings.fullscreen != current.settings.fullscreen,
        listener: (_, state) {
          const MethodChannel('asterix/window')
              .invokeMethod<void>('setFullscreen', state.settings.fullscreen)
              .catchError((_) {});
        },
        builder: (context, state) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Asterix & Obelix XXL',
          theme: AppTheme.dark,
          locale: Locale(state.settings.languageCode),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: assetPackage.isEmpty ? const _LaunchGate() : const GamePage(),
        ),
      ),
    );
  }
}

class _LaunchGate extends StatefulWidget {
  const _LaunchGate();

  @override
  State<_LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<_LaunchGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    child: _ready
        ? const HomePage(key: Key('main-menu'))
        : _LaunchScreen(key: const Key('launch-screen')),
  );
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.navy, AppTheme.ink],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ASTERIX & OBELIX XXL',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 18),
            Text(
              AppStrings.of(context).launchSubtitle,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 28),
            const SizedBox(width: 180, child: LinearProgressIndicator()),
          ],
        ),
      ),
    ),
  );
}
