import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../input/data/input_bindings_store.dart';
import '../../../input/domain/game_input.dart';
import '../../../save/data/save_game_store.dart';
import '../../../save/domain/save_game.dart';
import '../../../settings/presentation/pages/settings_page.dart';

class GamePage extends StatefulWidget {
  const GamePage({
    super.key,
    this.profileId = 'default',
    this.profileName = '',
    this.restoreSavedGame = true,
  });

  final String profileId;
  final String profileName;
  final bool restoreSavedGame;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const _controllerEvents = EventChannel('asterix/controller-events');
  static const _inputChannel = MethodChannel('asterix/game-input');
  static const _statsChannel = EventChannel('asterix/metal-stats');
  bool _paused = false;
  final _router = GameInputRouter();
  StreamSubscription<dynamic>? _controllerSubscription;
  StreamSubscription<dynamic>? _statsSubscription;
  late final Stream<dynamic> _statsStream;
  GameInputSnapshot? _input;
  SaveGameStore? _saveStore;
  String _profileId = 'default';
  String _profileName = 'Игрок';
  int _lastSavedCheckpoint = 0;
  bool _saving = false;
  bool _subtitlesEnabled = true;

  @override
  void initState() {
    super.initState();
    _profileId = widget.profileId;
    _profileName = widget.profileName.isEmpty ? 'Игрок' : widget.profileName;
    _statsStream = _statsChannel.receiveBroadcastStream().asBroadcastStream();
    _statsSubscription = _statsStream.listen(_onStats);
    _input = _router.snapshot();
    SharedPreferences.getInstance().then((preferences) {
      if (!mounted) return;
      _router.bindings = InputBindingsStore(preferences).load();
      _subtitlesEnabled = preferences.getBool('subtitles') ?? true;
      _applyAudioVolumes(preferences);
      _saveStore = SaveGameStore(preferences);
      final saved = _saveStore!.load();
      if (saved != null && widget.restoreSavedGame) {
        if (widget.profileId == 'default') {
          _profileId = saved.profileId;
          _profileName = saved.profileName;
        }
        _lastSavedCheckpoint = saved.checkpointId;
        unawaited(
          _inputChannel
              .invokeMethod<void>('restoreState', saved.gameplayState)
              .catchError((_) {}),
        );
      }
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
    unawaited(
      _inputChannel.invokeMethod<void>('setPaused', false).catchError((_) {}),
    );
    _controllerSubscription?.cancel();
    _statsSubscription?.cancel();
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
    if (value) unawaited(_saveGame(_lastSavedCheckpoint));
    if (mounted) setState(() => _paused = value);
    unawaited(
      _inputChannel.invokeMethod<void>('setPaused', value).catchError((_) {}),
    );
    if (!value) {
      SharedPreferences.getInstance().then(_applyAudioVolumes);
    }
  }

  void _applyAudioVolumes(SharedPreferences preferences) {
    unawaited(
      _inputChannel
          .invokeMethod<void>('setAudioVolumes', {
            'music': (preferences.getDouble('musicVolume') ?? 0.8).clamp(0, 1),
            'effects': (preferences.getDouble('effectsVolume') ?? 0.8).clamp(
              0,
              1,
            ),
          })
          .catchError((_) {}),
    );
  }

  void _onStats(dynamic event) {
    if (event is! Map || _saveStore == null) return;
    final checkpoint = (event['activeCheckpoint'] as num?)?.toInt() ?? 0;
    if (checkpoint > 0 && checkpoint != _lastSavedCheckpoint) {
      _lastSavedCheckpoint = checkpoint;
      unawaited(_saveGame(checkpoint));
    }
  }

  Future<void> _saveGame(int checkpoint) async {
    if (_saving || _saveStore == null || checkpoint <= 0) return;
    _saving = true;
    try {
      final raw = await _inputChannel.invokeMapMethod<String, Object?>(
        'captureState',
      );
      if (raw == null || raw.isEmpty) return;
      await _saveStore!.save(
        SaveGame(
          profileId: _profileId,
          profileName: _profileName,
          checkpointId: checkpoint,
          savedAt: DateTime.now().toUtc(),
          gameplayState: Map<String, Object?>.from(raw),
        ),
      );
    } on MissingPluginException {
      // Non-macOS/widget tests have no native persistence endpoint.
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _EngineViewport(),
            _Hud(stream: _statsStream),
            _OpeningSubtitle(enabled: _subtitlesEnabled),
            Positioned(
              left: 24,
              bottom: 20,
              child: Text(
                _input?.controllerConnected == true
                    ? strings.controllerConnected
                    : strings.keyboard,
                key: const Key('input-device'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 760) const _DebugPanel(),
            if (_paused)
              _PauseOverlay(
                onResume: () => _setPaused(false),
                onSettings: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                  final preferences = await SharedPreferences.getInstance();
                  if (mounted) {
                    setState(() {
                      _subtitlesEnabled =
                          preferences.getBool('subtitles') ?? true;
                    });
                  }
                },
              ),
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
  const _Hud({required this.stream});
  final Stream<dynamic> stream;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return StreamBuilder<dynamic>(
      stream: stream,
      builder: (context, snapshot) {
        final values = snapshot.data is Map
            ? Map<Object?, Object?>.from(snapshot.data as Map)
            : const <Object?, Object?>{};
        final fps = (values['fps'] as num?)?.toDouble() ?? 0;
        final cpu = (values['cpuMs'] as num?)?.toDouble() ?? 0;
        final gpu = (values['gpuMs'] as num?)?.toDouble() ?? 0;
        final bytes = (values['allocatedBytes'] as num?)?.toInt() ?? 0;
        final meshes = (values['sceneMeshCount'] as num?)?.toInt() ?? 0;
        final visible = (values['visibleMeshCount'] as num?)?.toInt() ?? 0;
        final batches = (values['drawBatchCount'] as num?)?.toInt() ?? 0;
        final sections = (values['residentSectionCount'] as num?)?.toInt() ?? 0;
        final sceneError = values['sceneError'] as String? ?? '';
        final collision =
            (values['collisionTriangleCount'] as num?)?.toInt() ?? 0;
        final playerState = values['playerState'] as String? ?? 'unavailable';
        final playerHealth = (values['playerHealth'] as num?)?.toInt() ?? 0;
        final playerMaximumHealth =
            (values['playerMaximumHealth'] as num?)?.toInt() ?? 3;
        final enemyState = values['enemyState'] as String? ?? 'unavailable';
        final enemyHealth = (values['enemyHealth'] as num?)?.toInt() ?? 0;
        final rewards = (values['rewardCount'] as num?)?.toInt() ?? 0;
        final checkpoint = (values['activeCheckpoint'] as num?)?.toInt() ?? 0;
        final lever = values['leverActivated'] == true;
        final destroyed = values['destructibleDestroyed'] == true;
        final cameraFov = (values['cameraFov'] as num?)?.toDouble() ?? 70;
        final cameraLimited = values['cameraCollisionLimited'] == true;
        final combatActive = values['combatActive'] == true;
        final comboStage = (values['comboStage'] as num?)?.toInt() ?? 0;
        final hitWindow = values['combatHitWindow'] == true;
        final hint = values['interactionHint'] as String? ?? '';
        final hintText = switch (hint) {
          'activate_lever' => strings.activateLever,
          'collect_reward' => strings.collectReward,
          'respawn' => strings.respawn,
          _ => '',
        };
        final healthValue = playerMaximumHealth <= 0
            ? 0.0
            : (playerHealth / playerMaximumHealth).clamp(0.0, 1.0);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                width: 270,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTheme.gold.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.asterix,
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      key: const Key('player-health'),
                      value: healthValue,
                      minHeight: 10,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${strings.health}: $playerHealth / $playerMaximumHealth',
                    ),
                    Text('${strings.rewards}: $rewards'),
                    if (hintText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'E / B · $hintText',
                        key: const Key('interaction-hint'),
                        style: const TextStyle(color: AppTheme.gold),
                      ),
                    ],
                    const Divider(height: 20),
                    Text(
                      'FPS ${fps.toStringAsFixed(1)}  CPU ${cpu.toStringAsFixed(2)} ms\n'
                      'GPU ${gpu.toStringAsFixed(2)} ms  Metal ${(bytes / 1048576).toStringAsFixed(1)} MiB\n'
                      '${meshes > 0
                          ? 'Scene: $visible/$meshes meshes, $batches batches, $sections sections\n'
                                'Collision: $collision triangles\n'
                                'Player: $playerState, HP $playerHealth\n'
                                'Enemy: $enemyState, HP $enemyHealth\n'
                                'World: reward $rewards, checkpoint $checkpoint\n'
                                'Lever: ${lever ? 'on' : 'off'}, object: ${destroyed ? 'destroyed' : 'intact'}\n'
                                'Camera: ${cameraFov.toStringAsFixed(0)}°${cameraLimited ? ' collision' : ''}\n'
                                'Combat: ${combatActive ? 'combo $comboStage${hitWindow ? ' HIT' : ''}' : 'ready'}'
                          : sceneError.isEmpty
                          ? 'Scene: proof'
                          : 'Scene error: $sceneError'}',
                      key: const Key('renderer-stats'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
  const _PauseOverlay({required this.onResume, required this.onSettings});

  final VoidCallback onResume;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.pause,
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 28),
            FilledButton(onPressed: onResume, child: Text(strings.resume)),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('pause-settings'),
              onPressed: onSettings,
              child: Text(strings.settings),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.exitToMenu),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningSubtitle extends StatefulWidget {
  const _OpeningSubtitle({required this.enabled});

  final bool enabled;

  @override
  State<_OpeningSubtitle> createState() => _OpeningSubtitleState();
}

class _OpeningSubtitleState extends State<_OpeningSubtitle> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_visible) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          key: const Key('opening-subtitle'),
          margin: const EdgeInsets.only(bottom: 54, left: 24, right: 24),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            AppStrings.of(context).openingSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
