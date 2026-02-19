import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/onboarding_screen.dart';

void main() {
  group('OnboardingScreen', () {
    testWidgets('renders welcome page first', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      expect(find.text('Welcome to TrustBridge'), findsOneWidget);
    });

    testWidgets('shows 3 step indicator dots', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      expect(find.byType(AnimatedContainer), findsNWidgets(3));
    });

    testWidgets('shows Skip button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('shows Next button on first page', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('Next advances to page 2', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Add your first child'), findsOneWidget);
    });

    testWidgets('Back button appears on page 2', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('shows Get Started on last page', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Get Started'), findsOneWidget);
    });

    testWidgets('skip completes onboarding then routes to dashboard',
        (WidgetTester tester) async {
      var completeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/dashboard': (_) => const Scaffold(body: Text('Dashboard Home')),
          },
          home: OnboardingScreen(
            parentId: 'parent-test',
            onCompleteOnboarding: (_) async {
              completeCalled = true;
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(completeCalled, isTrue);
      expect(find.text('Dashboard Home'), findsOneWidget);
    });
  });
}
