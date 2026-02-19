import 'package:flutter/material.dart';
import 'package:trustbridge_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Localization', () {
    test('English locale is supported', () {
      const locale = Locale('en');
      expect(AppLocalizations.supportedLocales.contains(locale), isTrue);
    });

    test('Hindi locale is supported', () {
      const locale = Locale('hi');
      expect(AppLocalizations.supportedLocales.contains(locale), isTrue);
    });

    testWidgets('English strings load correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(body: Text('Test')),
        ),
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold)),
      )!;

      expect(l10n.dashboardTitle, 'Dashboard');
      expect(l10n.addChildButton, 'Add Child');
      expect(l10n.saveButton, 'Save');
    });

    testWidgets('Hindi strings load correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('hi'),
          home: Scaffold(body: Text('Test')),
        ),
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold)),
      )!;

      expect(l10n.dashboardTitle, 'डैशबोर्ड');
      expect(l10n.addChildButton, 'बच्चा जोड़ें');
      expect(l10n.saveButton, 'सहेजें');
    });
  });
}

