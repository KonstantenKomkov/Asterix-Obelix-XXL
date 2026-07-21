import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _PauseIntent(),
      },
      child: Actions(
        actions: {
          _PauseIntent: CallbackAction<_PauseIntent>(
            onInvoke: (_) {
              setState(() => _paused = !_paused);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                const _EngineViewport(),
                const _Hud(),
                if (_paused)
                  _PauseOverlay(
                    onResume: () => setState(() => _paused = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EngineViewport extends StatelessWidget {
  const _EngineViewport();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF16283A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.view_in_ar_rounded,
              size: 72,
              color: AppTheme.gold.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 20),
            const Text(
              'METAL VIEWPORT',
              style: TextStyle(fontSize: 22, letterSpacing: 3),
            ),
            const SizedBox(height: 8),
            const Text(
              'Точка интеграции нативного 3D-движка',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('АСТЕРИКС', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                LinearProgressIndicator(value: 0.76, minHeight: 10),
                SizedBox(height: 8),
                Text('Шлемы:  0 / 10', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ПАУЗА', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 28),
            FilledButton(onPressed: onResume, child: const Text('ПРОДОЛЖИТЬ')),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ВЫЙТИ В МЕНЮ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PauseIntent extends Intent {
  const _PauseIntent();
}
