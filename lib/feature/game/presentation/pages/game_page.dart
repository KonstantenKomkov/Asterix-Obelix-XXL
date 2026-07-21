import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../input/data/input_bindings_store.dart';
import '../../../input/domain/game_input.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const _controllerEvents = EventChannel('asterix/controller-events');
  static const _inputChannel = MethodChannel('asterix/game-input');
  bool _paused = false;
  final _router = GameInputRouter();
  StreamSubscription<dynamic>? _controllerSubscription;
  GameInputSnapshot? _input;

  @override
  void initState() {
    super.initState();
    _input = _router.snapshot();
    SharedPreferences.getInstance().then((preferences) {
      if (!mounted) return;
      _router.bindings = InputBindingsStore(preferences).load();
      _publish(_router.snapshot());
    });
    _controllerSubscription = _controllerEvents.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _publish(_router.handleController(Map<Object?, Object?>.from(event)));
        }
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _controllerSubscription?.cancel();
    _router.reset();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    _publish(_router.handleKey(event));
    return _router.bindings.keyboard.containsValue(event.logicalKey.keyId)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _publish(GameInputSnapshot snapshot) {
    if (_router.consumePauseEdge(snapshot)) _setPaused(!_paused);
    if (mounted) setState(() => _input = snapshot);
    _inputChannel
        .invokeMethod<void>('setSnapshot', {
          for (final action in GameAction.values)
            action.name: snapshot.value(action),
        })
        .catchError((_) {});
  }

  void _setPaused(bool value) {
    if (mounted) setState(() => _paused = value);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _EngineViewport(),
            const _Hud(),
            Positioned(
              left: 24,
              bottom: 20,
              child: Text(
                _input?.controllerConnected == true
                    ? 'Controller connected'
                    : 'Keyboard',
                key: const Key('input-device'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            const _DebugPanel(),
            if (_paused) _PauseOverlay(onResume: () => _setPaused(false)),
          ],
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
                    final collision =
                        (values['collisionTriangleCount'] as num?)?.toInt() ??
                        0;
                    return Text(
                      'FPS ${fps.toStringAsFixed(1)}  CPU ${cpu.toStringAsFixed(2)} ms\n'
                      'GPU ${gpu.toStringAsFixed(2)} ms  Metal ${(bytes / 1048576).toStringAsFixed(1)} MiB\n'
                      '${meshes > 0
                          ? 'Scene: $visible/$meshes meshes, $batches batches, $sections sections\n'
                                'Collision: $collision triangles'
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

class _DebugPanel extends StatefulWidget {
  const _DebugPanel();

  @override
  State<_DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<_DebugPanel> {
  static const _channel = MethodChannel('asterix/metal-debug');
  static const _modes = <(String, int)>[
    ('Wireframe', 1),
    ('Collision', 2),
    ('Triggers', 4),
    ('Navmesh', 8),
    ('Object IDs', 16),
  ];
  int _options = 0;

  Future<void> _toggle(int flag) async {
    final next = _options ^ flag;
    setState(() => _options = next);
    try {
      await _channel.invokeMethod<void>('setOptions', next);
    } on MissingPluginException {
      // Widget tests and non-macOS fallback do not register the native channel.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Container(
          key: const Key('debug-panel'),
          width: 180,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: .45)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'DEBUG',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              for (final mode in _modes)
                FilterChip(
                  key: Key('debug-${mode.$2}'),
                  label: Text(mode.$1),
                  selected: (_options & mode.$2) != 0,
                  onSelected: (_) => _toggle(mode.$2),
                ),
              const Text(
                'Triggers/Navmesh: 0',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
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
