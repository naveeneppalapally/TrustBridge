import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/child_tutorial_screen.dart';

void main() {
  group('ChildTutorialScreen', () {
    testWidgets('renders first step content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChildTutorialScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1. Ask for Permission'), findsOneWidget);
      expect(find.text('Step 1 of 3: The Basics'), findsOneWidget);
      expect(find.text('Next ->'), findsOneWidget);
      expect(
          find.byKey(const Key('child_tutorial_skip_button')), findsOneWidget);
    });

    testWidgets('next advances to second step', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChildTutorialScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('child_tutorial_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('2. Wait for Reply'), findsOneWidget);
      expect(find.text('Step 2 of 3: The Basics'), findsOneWidget);
    });

    testWidgets('last page shows final CTA', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChildTutorialScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('child_tutorial_next_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('child_tutorial_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('3. You are Protected'), findsOneWidget);
      expect(find.text('Let\'s Go!'), findsOneWidget);
    });

    testWidgets('skip triggers finish callback', (tester) async {
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ChildTutorialScreen(
            onFinished: () {
              finished = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('child_tutorial_skip_button')));
      await tester.pumpAndSettle();

      expect(finished, isTrue);
    });
  });
}
