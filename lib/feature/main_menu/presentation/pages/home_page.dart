import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../game/presentation/pages/game_page.dart';
import '../../../save/data/save_game_store.dart';
import '../../../save/domain/save_game.dart';
import '../../../settings/presentation/pages/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _assetsChannel = MethodChannel('asterix/assets');
  static const _configuredAssetPackagePath = String.fromEnvironment(
    'ASTERIX_ASSET_PACKAGE',
  );
  String _profileId = 'default';
  String _profileName = '';
  SaveGame? _save;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((preferences) {
      if (!mounted) return;
      setState(() {
        _profileId = preferences.getString('activeProfileId') ?? 'default';
        _profileName = preferences.getString('activeProfileName') ?? '';
        _save = SaveGameStore(preferences).load();
        if (_profileName.isEmpty && _save != null) {
          _profileId = _save!.profileId;
          _profileName = _save!.profileName;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final profileName = _profileName.isEmpty ? strings.player : _profileName;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _MenuBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ASTERIX &\nOBELIX XXL',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: compact ? 38 : 58,
                        height: 0.9,
                        shadows: const [
                          Shadow(color: Colors.black54, offset: Offset(3, 4)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      strings.nativePrototype,
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                  ],
                );
                final menu = ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('profile-button'),
                        onPressed: () => _editProfile(context),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: Text('${strings.profile}: $profileName'),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        key: const Key('new-game-button'),
                        onPressed: () => _openGame(
                          context,
                          profileId: _profileId,
                          profileName: profileName,
                          restoreSavedGame: false,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(strings.newGame),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        key: const Key('continue-button'),
                        onPressed: _save == null
                            ? null
                            : () => _openGame(
                                context,
                                profileId: _save!.profileId,
                                profileName: _save!.profileName,
                                restoreSavedGame: true,
                              ),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: Text(strings.continueGame),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        key: const Key('settings-button'),
                        onPressed: () => _open(context, const SettingsPage()),
                        icon: const Icon(Icons.settings_rounded),
                        label: Text(strings.settings),
                      ),
                    ],
                  ),
                );
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 24 : 40,
                    24,
                    compact ? 24 : 40,
                    56,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 80,
                    ),
                    child: compact
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [title, const SizedBox(height: 36), menu],
                          )
                        : Row(
                            children: [
                              Expanded(flex: 3, child: title),
                              const SizedBox(width: 40),
                              Expanded(flex: 2, child: menu),
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
          const Positioned(
            right: 20,
            bottom: 14,
            child: Text(
              'VERTICAL SLICE · M4',
              style: TextStyle(color: Colors.white38, letterSpacing: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final strings = AppStrings.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _ProfileNameDialog(
        initialName: _profileName.isEmpty ? strings.player : _profileName,
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final preferences = await SharedPreferences.getInstance();
    final id = _profileId == 'default'
        ? 'profile-${DateTime.now().millisecondsSinceEpoch}'
        : _profileId;
    await Future.wait([
      preferences.setString('activeProfileId', id),
      preferences.setString('activeProfileName', name),
    ]);
    if (mounted) {
      setState(() {
        _profileId = id;
        _profileName = name;
      });
    }
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _openGame(
    BuildContext context, {
    required String profileId,
    required String profileName,
    required bool restoreSavedGame,
  }) async {
    var packagePath = _configuredAssetPackagePath;
    final preferences = await SharedPreferences.getInstance();
    packagePath = packagePath.isEmpty
        ? preferences.getString('assetPackagePath') ?? ''
        : packagePath;
    if (_configuredAssetPackagePath.isEmpty &&
        defaultTargetPlatform == TargetPlatform.macOS) {
      packagePath =
          await _assetsChannel.invokeMethod<String>(
            'resolveAssetPackage',
            packagePath,
          ) ??
          '';
      if (packagePath.isNotEmpty) {
        await preferences.setString('assetPackagePath', packagePath);
      }
    }
    if (packagePath.isEmpty && defaultTargetPlatform == TargetPlatform.macOS) {
      packagePath =
          await _assetsChannel.invokeMethod<String>('selectAssetPackage') ?? '';
      if (packagePath.isNotEmpty) {
        await preferences.setString('assetPackagePath', packagePath);
      }
    }
    if (!context.mounted) return;
    if (packagePath.isEmpty && defaultTargetPlatform == TargetPlatform.macOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).assetPackageRequired)),
      );
      return;
    }
    _open(
      context,
      GamePage(
        profileId: profileId,
        profileName: profileName,
        restoreSavedGame: restoreSavedGame,
        assetPackagePath: packagePath,
      ),
    );
  }
}

class _ProfileNameDialog extends StatefulWidget {
  const _ProfileNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.editProfile),
      content: TextField(
        key: const Key('profile-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 32,
        decoration: InputDecoration(labelText: strings.profileName),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const Key('save-profile-button'),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(strings.save),
        ),
      ],
    );
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
