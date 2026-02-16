import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
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

      expect(find.text('Add a new child profile'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(Radio<AgeBand>), findsNWidgets(3));
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

      await tester.enterText(find.byType(TextFormField), 'A');
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

      await tester.enterText(find.byType(TextFormField), 'ABCDEFGHIJKLMNOPQRSTU');
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

    testWidgets('age band selection updates policy preview', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AddChildScreen(),
        ),
      );

      expect(find.text('Social Networks'), findsOneWidget);

      await tester.tap(find.text('14-17 years'));
      await tester.pump();

      expect(find.text('Social Networks'), findsNothing);
      expect(find.text('What will be blocked?'), findsOneWidget);
    });
  });
}
