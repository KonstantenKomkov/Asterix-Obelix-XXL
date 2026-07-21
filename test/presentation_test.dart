import 'package:asterix_xxl/core/localization/app_strings.dart';
import 'package:asterix_xxl/feature/main_menu/presentation/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [const Size(560, 420), const Size(1440, 900)]) {
    testWidgets('main menu fits ${size.width}x${size.height}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('ru'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-game-button')), findsOneWidget);
      expect(find.byKey(const Key('profile-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
