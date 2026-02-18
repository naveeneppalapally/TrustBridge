import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/models/support_ticket.dart';

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

  group('SupportTicket', () {
    test('status parser handles known and unknown values', () {
      expect(SupportTicketStatus.fromRaw('open'), SupportTicketStatus.open);
      expect(
        SupportTicketStatus.fromRaw('in_progress'),
        SupportTicketStatus.inProgress,
      );
      expect(
        SupportTicketStatus.fromRaw('resolved'),
        SupportTicketStatus.resolved,
      );
      expect(
        SupportTicketStatus.fromRaw('invalid'),
        SupportTicketStatus.unknown,
      );
    });

    test('source detects beta feedback by subject prefix', () {
      final betaTicket = SupportTicket(
        id: '1',
        parentId: 'parent',
        subject: '[Beta][High] VPN issue',
        message: 'details',
        status: SupportTicketStatus.open,
        createdAt: DateTime(2026, 2, 17),
        updatedAt: DateTime(2026, 2, 17),
      );
      final supportTicket = SupportTicket(
        id: '2',
        parentId: 'parent',
        subject: 'Policy Question',
        message: 'details',
        status: SupportTicketStatus.open,
        createdAt: DateTime(2026, 2, 17),
        updatedAt: DateTime(2026, 2, 17),
      );

      expect(betaTicket.source, SupportTicketSource.betaFeedback);
      expect(supportTicket.source, SupportTicketSource.helpSupport);
    });

    test('severity parser detects beta severity token', () {
      final criticalTicket = SupportTicket(
        id: '1',
        parentId: 'parent',
        subject: '[Beta][Critical] VPN crash on enable',
        message: 'details',
        status: SupportTicketStatus.open,
        createdAt: DateTime(2026, 2, 17),
        updatedAt: DateTime(2026, 2, 17),
      );
      final supportTicket = SupportTicket(
        id: '2',
        parentId: 'parent',
        subject: 'Need help with onboarding',
        message: 'details',
        status: SupportTicketStatus.open,
        createdAt: DateTime(2026, 2, 17),
        updatedAt: DateTime(2026, 2, 17),
      );

      expect(criticalTicket.severity, SupportTicketSeverity.critical);
      expect(supportTicket.severity, SupportTicketSeverity.unknown);
    });

    test('attention and stale helpers are derived from age and status', () {
      final staleOpenTicket = SupportTicket(
        id: '1',
        parentId: 'parent',
        subject: '[Beta][High] Old unresolved ticket',
        message: 'details',
        status: SupportTicketStatus.open,
        createdAt: DateTime(2026, 2, 10, 8, 0),
        updatedAt: DateTime(2026, 2, 10, 8, 0),
      );
      final resolvedTicket = SupportTicket(
        id: '2',
        parentId: 'parent',
        subject: '[Beta][High] Already fixed',
        message: 'details',
        status: SupportTicketStatus.resolved,
        createdAt: DateTime(2026, 2, 10, 8, 0),
        updatedAt: DateTime(2026, 2, 10, 8, 0),
      );
      final referenceNow = DateTime(2026, 2, 17, 8, 0);

      expect(staleOpenTicket.needsAttention(now: referenceNow), isTrue);
      expect(staleOpenTicket.isStale(now: referenceNow), isTrue);
      expect(resolvedTicket.needsAttention(now: referenceNow), isFalse);
      expect(resolvedTicket.isStale(now: referenceNow), isFalse);
    });

    test('duplicate key normalizes beta prefix, punctuation, and spacing', () {
      final a = SupportTicket(
        id: '1',
        parentId: 'parent',
        subject: '[Beta][High] VPN crash on enable!!!',
        message: 'details',
        status: SupportTicketStatus.open,
        createdAt: DateTime(2026, 2, 17),
        updatedAt: DateTime(2026, 2, 17),
      );
      final b = SupportTicket(
        id: '2',
        parentId: 'parent',
        subject: 'vpn   crash on enable',
        message: 'details',
        status: SupportTicketStatus.open,
        createdAt: DateTime(2026, 2, 17),
        updatedAt: DateTime(2026, 2, 17),
      );

      expect(a.duplicateKey, equals('vpn crash on enable'));
      expect(b.duplicateKey, equals('vpn crash on enable'));
      expect(a.duplicateKey, equals(b.duplicateKey));
    });
  });
}
