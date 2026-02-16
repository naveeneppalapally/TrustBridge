import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/quick_modes_screen.dart';

void main() {
  group('QuickModesScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.middle,
      );
    });

    testWidgets('renders quick mode options', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: QuickModesScreen(child: testChild),
        ),
      );

      expect(find.text('Quick Modes'), findsOneWidget);
      expect(find.text('One-Tap Policy Presets'), findsOneWidget);
      expect(find.text('Strict Shield'), findsOneWidget);
      expect(find.text('Balanced'), findsOneWidget);
      expect(find.text('Relaxed'), findsOneWidget);
      expect(find.text('School Night'), findsOneWidget);
    });

    testWidgets('selecting mode updates preview and enables apply',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: QuickModesScreen(child: testChild),
        ),
      );

      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Apply Mode'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Apply Mode'), findsOneWidget);
      final applyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply Mode'),
      );
      expect(applyButton.onPressed, isNull);

      await tester.tap(find.text('Balanced'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Apply Mode'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final enabledButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply Mode'),
      );
      expect(enabledButton.onPressed, isNotNull);
      expect(find.text('Preview Changes'), findsOneWidget);
    });

    testWidgets('apply opens confirmation dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: QuickModesScreen(child: testChild),
        ),
      );

      await tester.tap(find.text('Strict Shield'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Apply Mode'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Apply Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Apply Quick Mode?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });
  });
}
