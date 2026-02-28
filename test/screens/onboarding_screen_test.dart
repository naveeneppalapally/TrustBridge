import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/onboarding_screen.dart';

void main() {
  group('OnboardingScreen', () {
    testWidgets('renders quick setup single-step screen', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      expect(find.text('Quick Setup'), findsOneWidget);
      expect(find.text('Set up in one step'), findsOneWidget);
      expect(find.text('Child name'), findsOneWidget);
      expect(find.text('Generate Pairing Code'), findsOneWidget);
    });

    testWidgets('shows 3 age-band chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      expect(find.text('6-9 years'), findsOneWidget);
      expect(find.text('10-13 years'), findsOneWidget);
      expect(find.text('14-17 years'), findsOneWidget);
    });

    testWidgets('shows validation when child name is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Generate Pairing Code'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your child\'s name.'), findsOneWidget);
    });

    testWidgets('Skip routes to dashboard', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/dashboard': (_) => const Scaffold(body: Text('Dashboard Home')),
          },
          home: const OnboardingScreen(parentId: 'parent-test'),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Home'), findsOneWidget);
    });
  });
}
