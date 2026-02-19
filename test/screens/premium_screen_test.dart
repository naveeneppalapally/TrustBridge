import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/premium_screen.dart';

void main() {
  group('PremiumScreen', () {
    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
    }

    testWidgets('renders header and feature list', (tester) async {
      await pumpScreen(tester, const PremiumScreen());

      expect(find.byKey(const Key('premium_header_card')), findsOneWidget);
      expect(find.text('TrustBridge '), findsNothing);
      expect(find.textContaining('TrustBridge'), findsOneWidget);
      expect(find.byKey(const Key('premium_features_card')), findsOneWidget);
      expect(find.text('Unlimited Children'), findsOneWidget);
      expect(find.text('Advanced Analytics'), findsOneWidget);
      expect(find.text('Custom Categories'), findsOneWidget);
      expect(find.text('Priority Support'), findsOneWidget);
    });

    testWidgets('switches between yearly and monthly plans', (tester) async {
      await pumpScreen(tester, const PremiumScreen());

      expect(find.byKey(const Key('premium_yearly_plan_card')), findsOneWidget);
      expect(
          find.byKey(const Key('premium_monthly_plan_card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('premium_monthly_plan_card')));
      await tester.pumpAndSettle();

      expect(find.text('INR 299 / month'), findsOneWidget);
    });

    testWidgets('close button triggers callback', (tester) async {
      var closed = false;
      await pumpScreen(
        tester,
        PremiumScreen(
          onClose: () {
            closed = true;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('premium_close_button')));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
    });
  });
}
