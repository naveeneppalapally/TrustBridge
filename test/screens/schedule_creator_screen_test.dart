import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/schedule_creator_screen.dart';

void main() {
  group('ScheduleCreatorScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('renders schedule creator with existing schedules',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleCreatorScreen(child: testChild),
        ),
      );

      expect(find.text('Schedule Creator'), findsOneWidget);
      expect(find.text('Time Restrictions'), findsOneWidget);
      expect(find.textContaining('2 schedules configured'), findsOneWidget);
      expect(find.text('Quick Templates'), findsOneWidget);
      expect(find.text('Bedtime'), findsOneWidget);
      expect(find.text('School Time'), findsOneWidget);
    });

    testWidgets('quick template add shows save action', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleCreatorScreen(child: testChild),
        ),
      );

      expect(find.text('SAVE'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Add Homework'));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 schedules configured'), findsOneWidget);
      expect(find.text('SAVE'), findsOneWidget);
      expect(find.text('Homework Time'), findsOneWidget);
    });

    testWidgets('delete action opens confirmation dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleCreatorScreen(child: testChild),
        ),
      );

      await tester.tap(find.byTooltip('Delete schedule').first);
      await tester.pumpAndSettle();

      expect(find.text('Delete Schedule'), findsOneWidget);
      expect(find.textContaining('Remove "'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
