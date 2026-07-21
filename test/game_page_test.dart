import 'package:asterix_xxl/feature/game/presentation/pages/game_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('macOS game page embeds Metal platform view below HUD', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (_) async => 1,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null),
    );
    final pauseCalls = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('asterix/game-input'), (
          call,
        ) async {
          if (call.method == 'setPaused') {
            pauseCalls.add(call.arguments as bool);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('asterix/game-input'),
            null,
          ),
    );

    try {
      await tester.pumpWidget(const MaterialApp(home: GamePage()));
      await tester.pump();

      expect(find.byType(AppKitView), findsOneWidget);
      expect(find.byKey(const Key('metal-viewport')), findsOneWidget);
      expect(find.text('АСТЕРИКС'), findsOneWidget);
      expect(find.byKey(const Key('renderer-stats')), findsOneWidget);
      expect(find.textContaining('FPS 0.0'), findsOneWidget);
      expect(find.byKey(const Key('debug-panel')), findsOneWidget);
      expect(find.text('Wireframe'), findsOneWidget);
      await tester.tap(find.byKey(const Key('debug-1')));
      await tester.pump();
      expect(
        tester.widget<FilterChip>(find.byKey(const Key('debug-1'))).selected,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('ПАУЗА'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('ПАУЗА'), findsNothing);
      expect(pauseCalls, containsAllInOrder(<bool>[true, false]));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
