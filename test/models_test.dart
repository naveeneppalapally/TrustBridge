import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/schedule.dart';

void main() {
  group('ChildProfile', () {
    test('creates child with preset policy', () {
      final child = ChildProfile.create(
        nickname: 'Alex',
        ageBand: AgeBand.young,
      );

      expect(child.nickname, 'Alex');
      expect(child.ageBand, AgeBand.young);
      expect(child.id.length, greaterThan(0));
      expect(child.policy.blockedCategories.length, greaterThan(0));
    });

    test('toFirestore and back works', () {
      final child = ChildProfile.create(
        nickname: 'Sam',
        ageBand: AgeBand.middle,
      );

      final map = child.toFirestore();
      expect(map['nickname'], 'Sam');
      expect(map['ageBand'], '10-13');
      expect(map['policy'], isA<Map<String, dynamic>>());
    });
  });

  group('Policy', () {
    test('young preset is strictest', () {
      final policy = Policy.presetForAgeBand(AgeBand.young);

      expect(policy.blockedCategories, contains('social-networks'));
      expect(policy.safeSearchEnabled, isTrue);
      expect(policy.schedules.length, 2);
    });

    test('teen preset is lenient', () {
      final policy = Policy.presetForAgeBand(AgeBand.teen);

      expect(policy.blockedCategories, isNot(contains('social-networks')));
      expect(policy.safeSearchEnabled, isFalse);
      expect(policy.schedules.length, 1);
    });
  });

  group('Schedule', () {
    test('bedtime schedule created correctly', () {
      final schedule = Schedule.bedtime(
        startTime: '20:00',
        endTime: '07:00',
      );

      expect(schedule.type, ScheduleType.bedtime);
      expect(schedule.action, ScheduleAction.blockAll);
      expect(schedule.days.length, 7);
    });

    test('school schedule created correctly', () {
      final schedule = Schedule.schoolTime(
        startTime: '09:00',
        endTime: '15:00',
      );

      expect(schedule.type, ScheduleType.school);
      expect(schedule.days.length, 5);
    });
  });
}
