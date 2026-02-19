import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';

void main() {
  group('AddChildScreen', () {
    testWidgets('renders form correctly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AddChildScreen(),
        ),
      );

      expect(find.text('Add Child · STEP 1 OF 2'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byKey(const Key('add_child_avatar_picker_button')),
          findsOneWidget);
      expect(find.byKey(const Key('add_child_submit')), findsOneWidget);
    });

    testWidgets('shows validation error for empty nickname', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AddChildScreen(),
        ),
      );

      final submitButton = find.byKey(const Key('add_child_submit'));
      await tester.scrollUntilVisible(
        submitButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Please enter a nickname'), findsOneWidget);
    });

    testWidgets('shows validation error for short nickname', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AddChildScreen(),
        ),
      );

      await tester.enterText(find.byKey(const Key('add_child_nickname_input')), 'A');
      final submitButton = find.byKey(const Key('add_child_submit'));
      await tester.scrollUntilVisible(
        submitButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Nickname must be at least 2 characters'), findsOneWidget);
    });

    testWidgets('shows validation error for long nickname', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AddChildScreen(),
        ),
      );

      await tester.enterText(
          find.byKey(const Key('add_child_nickname_input')), 'ABCDEFGHIJKLMNOPQRSTU');
      final submitButton = find.byKey(const Key('add_child_submit'));
      await tester.scrollUntilVisible(
        submitButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Nickname must be less than 20 characters'), findsOneWidget);
    });

    testWidgets('renders protection level cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AddChildScreen(),
        ),
      );

      expect(find.text('Strict'), findsOneWidget);
      expect(find.text('Moderate'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_child_level_light')));
      await tester.pump();

      expect(find.byKey(const Key('add_child_level_light')), findsOneWidget);
      expect(find.text('Continue to Pairing ->'), findsOneWidget);
    });
  });
}
