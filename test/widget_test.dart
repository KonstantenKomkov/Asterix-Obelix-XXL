import 'package:asterix_xxl/app/app.dart';
import 'package:asterix_xxl/core/di/injection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('main menu opens the game prototype', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      SharedPreferences.setMockInitialValues({});
      await configureDependencies();
      await tester.pumpWidget(const AsterixXxlApp());

      expect(find.text('ASTERIX &\nOBELIX XXL'), findsOneWidget);
      await tester.tap(find.byKey(const Key('new-game-button')));
      await tester.pumpAndSettle();

      expect(find.text('METAL VIEWPORT'), findsOneWidget);
      expect(find.text('АСТЕРИКС'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
