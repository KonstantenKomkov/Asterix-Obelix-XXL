import 'package:asterix_xxl/app/app.dart';
import 'package:asterix_xxl/core/di/injection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('main menu opens the game prototype', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      SharedPreferences.setMockInitialValues({});
      final fullscreenCalls = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('asterix/window'), (
            call,
          ) async {
            if (call.method == 'setFullscreen') {
              fullscreenCalls.add(call.arguments as bool);
            }
            return null;
          });
      await configureDependencies();
      await tester.pumpWidget(const AsterixXxlApp());

      expect(find.byKey(const Key('launch-screen')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('ASTERIX &\nOBELIX XXL'), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name-field')),
        'Vitalstatistix',
      );
      await tester.tap(find.byKey(const Key('save-profile-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vitalstatistix'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Полноэкранный режим'));
      await tester.pumpAndSettle();
      expect(fullscreenCalls, contains(true));
      await tester.tap(find.byKey(const Key('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Английский').last);
      await tester.pumpAndSettle();
      expect(find.text('SETTINGS'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('NEW GAME'), findsOneWidget);

      await tester.tap(find.byKey(const Key('new-game-button')));
      await tester.pumpAndSettle();

      expect(find.text('METAL VIEWPORT'), findsOneWidget);
      expect(find.text('ASTERIX'), findsOneWidget);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('asterix/window'),
            null,
          );
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
