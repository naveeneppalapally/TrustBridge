import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/usage_reports_screen.dart';

void main() {
  group('UsageReportsScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: UsageReportsScreen(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders app bar title and date chip', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Usage Reports'), findsOneWidget);
      expect(find.text('This Week'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    });

    testWidgets('shows hero card and category section', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('usage_reports_hero_card')), findsOneWidget);
      expect(find.text('Total Screen Time'), findsOneWidget);
      expect(find.text('5h 47m'), findsOneWidget);

      expect(
        find.byKey(const Key('usage_reports_category_card')),
        findsOneWidget,
      );
      expect(find.text('By Category'), findsOneWidget);
      expect(find.text('Social Media'), findsOneWidget);
      expect(find.text('Education'), findsWidgets);
      expect(find.text('Games'), findsWidgets);
    });

    testWidgets('shows trend and most used apps sections', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('usage_reports_trend_card')), findsOneWidget);
      expect(find.text('7-Day Trend'), findsOneWidget);
      expect(find.textContaining('Weekend screen time is 24%'), findsOneWidget);

      expect(find.byKey(const Key('usage_reports_apps_card')), findsOneWidget);
      expect(find.text('Most Used Apps'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Chrome'), findsOneWidget);
      expect(find.text('Roblox'), findsOneWidget);
      expect(find.text('View All App Usage'), findsOneWidget);
    });
  });
}
