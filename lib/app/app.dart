import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/di/injection.dart';
import '../core/theme/app_theme.dart';
import '../feature/main_menu/presentation/pages/home_page.dart';
import '../feature/settings/presentation/bloc/settings_bloc.dart';

class AsterixXxlApp extends StatelessWidget {
  const AsterixXxlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<SettingsBloc>()..add(const SettingsEvent.loadRequested()),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Asterix & Obelix XXL',
        theme: AppTheme.dark,
        home: const HomePage(),
      ),
    );
  }
}
