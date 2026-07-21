import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  static const viewType = 'asterix/metal-viewport';
  static const assetPackagePath = String.fromEnvironment(
    'ASTERIX_ASSET_PACKAGE',
  );

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return AppKitView(
        key: const Key('metal-viewport'),
        viewType: viewType,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        creationParams: const {'assetPackagePath': assetPackagePath},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

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

  static const _stats = EventChannel('asterix/metal-stats');

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'АСТЕРИКС',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const LinearProgressIndicator(value: 0.76, minHeight: 10),
                const SizedBox(height: 8),
                const Text(
                  'Шлемы:  0 / 10',
                  style: TextStyle(color: Colors.white70),
                ),
                const Divider(height: 20),
                StreamBuilder<dynamic>(
                  stream: _stats.receiveBroadcastStream(),
                  builder: (context, snapshot) {
                    final values = snapshot.data is Map
                        ? Map<Object?, Object?>.from(snapshot.data as Map)
                        : const <Object?, Object?>{};
                    final fps = (values['fps'] as num?)?.toDouble() ?? 0;
                    final cpu = (values['cpuMs'] as num?)?.toDouble() ?? 0;
                    final gpu = (values['gpuMs'] as num?)?.toDouble() ?? 0;
                    final bytes =
                        (values['allocatedBytes'] as num?)?.toInt() ?? 0;
                    final meshes =
                        (values['sceneMeshCount'] as num?)?.toInt() ?? 0;
                    final visible =
                        (values['visibleMeshCount'] as num?)?.toInt() ?? 0;
                    final batches =
                        (values['drawBatchCount'] as num?)?.toInt() ?? 0;
                    final sections =
                        (values['residentSectionCount'] as num?)?.toInt() ?? 0;
                    final sceneError = values['sceneError'] as String? ?? '';
                    return Text(
                      'FPS ${fps.toStringAsFixed(1)}  CPU ${cpu.toStringAsFixed(2)} ms\n'
                      'GPU ${gpu.toStringAsFixed(2)} ms  Metal ${(bytes / 1048576).toStringAsFixed(1)} MiB\n'
                      '${meshes > 0
                          ? 'Scene: $visible/$meshes meshes, $batches batches, $sections sections'
                          : sceneError.isEmpty
                          ? 'Scene: proof'
                          : 'Scene error: $sceneError'}',
                      key: const Key('renderer-stats'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
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
