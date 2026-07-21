import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../game/presentation/pages/game_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _MenuBackdrop(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ASTERIX &\nOBELIX XXL',
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(
                                fontSize: 58,
                                height: 0.9,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black54,
                                    offset: Offset(3, 4),
                                  ),
                                ],
                              ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Нативный прототип для macOS',
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          key: const Key('new-game-button'),
                          onPressed: () => _open(context, const GamePage()),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('НОВАЯ ИГРА'),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('ПРОДОЛЖИТЬ'),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          key: const Key('settings-button'),
                          onPressed: () => _open(context, const SettingsPage()),
                          icon: const Icon(Icons.settings_rounded),
                          label: const Text('НАСТРОЙКИ'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            right: 20,
            bottom: 14,
            child: Text(
              'TECHNICAL PROTOTYPE · M2',
              style: TextStyle(color: Colors.white38, letterSpacing: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _MenuBackdrop extends StatelessWidget {
  const _MenuBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF284B68), AppTheme.ink, Color(0xFF431F24)],
        ),
      ),
      child: CustomPaint(painter: _SunPainter()),
    );
  }
}

class _SunPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.28),
      size.shortestSide * 0.16,
      Paint()..color = AppTheme.gold.withValues(alpha: 0.22),
    );
    final hill = Path()
      ..moveTo(0, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.30,
        size.height * 0.54,
        size.width * 0.56,
        size.height * 0.82,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.65,
        size.width,
        size.height * 0.76,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill, Paint()..color = const Color(0xFF152F2A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
