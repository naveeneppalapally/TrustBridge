import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_detail_screen.dart';

void main() {
  group('ChildDetailScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Leo',
        ageBand: AgeBand.young,
      );
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(child: testChild),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders profile header and status card', (tester) async {
      await pumpScreen(tester);

      expect(find.text('CHILD PROFILE'), findsOneWidget);
      expect(find.text('Leo'), findsWidgets);
      expect(find.byKey(const Key('child_detail_status_card')), findsOneWidget);
      expect(find.textContaining('Mode'), findsWidgets);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('renders circular ring and quick actions grid', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('child_detail_timer_ring')), findsOneWidget);
      expect(find.text('REMAINING'), findsOneWidget);
      expect(
        find.byKey(const Key('child_detail_quick_actions_grid')),
        findsOneWidget,
      );
      expect(find.text('Pause All'), findsOneWidget);
      expect(find.text('Homework'), findsOneWidget);
      expect(find.text('Bedtime'), findsWidgets);
      expect(find.text('Free Play'), findsOneWidget);
    });

    testWidgets('shows today activity and active schedules sections',
        (tester) async {
      await pumpScreen(tester);

      expect(
          find.byKey(const Key('child_detail_activity_card')), findsOneWidget);
      expect(find.textContaining('Today\'s Activity'), findsOneWidget);
      expect(find.text('Education'), findsOneWidget);
      expect(find.text('Entertainment'), findsOneWidget);
      expect(find.text('Social'), findsOneWidget);

      expect(
          find.byKey(const Key('child_detail_schedules_card')), findsOneWidget);
      expect(find.text('Active Schedules'), findsOneWidget);
      expect(find.text('View All'), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);
    });

    testWidgets('overflow menu exposes edit activity policy and delete',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('child_detail_overflow_menu')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('View Activity Log'), findsOneWidget);
      expect(find.text('Manage Policy'), findsOneWidget);
      expect(find.text('Delete Profile'), findsOneWidget);
    });

    testWidgets('delete option opens confirmation dialog', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('child_detail_overflow_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Child Profile'), findsOneWidget);
      expect(find.text('This action cannot be undone'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
          find.widgetWithText(FilledButton, 'Delete Profile'), findsOneWidget);
    });
  });
}
