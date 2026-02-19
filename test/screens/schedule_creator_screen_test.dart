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

    testWidgets('renders schedule editor sections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleCreatorScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.text('Schedule Editor'), findsOneWidget);
      expect(find.text('ROUTINE TYPE'), findsOneWidget);
      expect(find.text('RESTRICTION LEVEL'), findsOneWidget);
      expect(find.byKey(const Key('schedule_save_button')), findsOneWidget);
    });

    testWidgets('routine type and restriction selections are interactive',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleCreatorScreen(child: testChild),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('schedule_type_custom')));
      await tester.pump();
      expect(find.byKey(const Key('schedule_type_custom')), findsOneWidget);

      await tester.tap(find.byKey(const Key('schedule_block_all_card')));
      await tester.pump();
      expect(find.byKey(const Key('schedule_block_all_card')), findsOneWidget);
    });

    testWidgets('day selector and reminder toggle work', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleCreatorScreen(child: testChild),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('schedule_day_saturday')));
      await tester.pump();
      expect(find.byKey(const Key('schedule_day_saturday')), findsOneWidget);

      await tester.tap(find.byKey(const Key('schedule_remind_toggle')));
      await tester.pump();
      expect(find.byKey(const Key('schedule_remind_toggle')), findsOneWidget);
    });
  });
}
