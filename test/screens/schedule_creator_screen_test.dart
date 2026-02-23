import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/screens/schedule_creator_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

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
      await tester.dragUntilVisible(
        find.byKey(const Key('schedule_save_button')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
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
      expect(
        find.textContaining('You choose exactly which apps to block and when.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('schedule_block_all_card')));
      await tester.pump();
      expect(find.byKey(const Key('schedule_block_all_card')), findsOneWidget);
      expect(find.textContaining('Total lockout - only phone calls'),
          findsOneWidget);
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

      await tester.dragUntilVisible(
        find.byKey(const Key('schedule_remind_toggle')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule_remind_toggle')));
      await tester.pump();
      expect(find.byKey(const Key('schedule_remind_toggle')), findsOneWidget);
    });

    testWidgets('shows conflict dialog and blocks save on overlap',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final firestoreService = _FakeFirestoreService();
      final overlappingChild = testChild.copyWith(
        policy: Policy(
          blockedCategories: testChild.policy.blockedCategories,
          blockedDomains: testChild.policy.blockedDomains,
          safeSearchEnabled: testChild.policy.safeSearchEnabled,
          schedules: <Schedule>[
            Schedule(
              id: 'schedule-a',
              name: 'School Time',
              type: ScheduleType.school,
              days: const <Day>[
                Day.monday,
                Day.tuesday,
                Day.wednesday,
                Day.thursday,
                Day.friday,
              ],
              startTime: '09:00',
              endTime: '15:00',
              enabled: true,
              action: ScheduleAction.blockDistracting,
            ),
            Schedule(
              id: 'schedule-b',
              name: 'Homework Block',
              type: ScheduleType.homework,
              days: const <Day>[
                Day.monday,
                Day.tuesday,
                Day.wednesday,
                Day.thursday,
                Day.friday,
              ],
              startTime: '13:00',
              endTime: '16:00',
              enabled: true,
              action: ScheduleAction.blockDistracting,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleCreatorScreen(
            child: overlappingChild,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-test',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('schedule_save_button')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Schedule conflict'), findsOneWidget);
      expect(firestoreService.updateChildCalls, 0);
    });
  });
}

class _FakeFirestoreService extends FirestoreService {
  _FakeFirestoreService() : super(firestore: FakeFirebaseFirestore());

  int updateChildCalls = 0;

  @override
  Future<void> updateChild({
    required String parentId,
    required ChildProfile child,
  }) async {
    updateChildCalls += 1;
  }
}
