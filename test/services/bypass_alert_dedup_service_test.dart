import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/bypass_alert_dedup_service.dart';

void main() {
  group('BypassAlertDedupService', () {
    late FakeFirebaseFirestore firestore;
    late DateTime now;
    late BypassAlertDedupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      now = DateTime(2026, 2, 20, 12, 0, 0);
      service = BypassAlertDedupService(
        firestore: firestore,
        nowProvider: () => now,
      );
    });

    test('first alert of type should send', () async {
      final shouldSend = await service.shouldAlert('device-1', 'vpn_disabled');
      expect(shouldSend, isTrue);
    });

    test('second alert within 10 min should be skipped', () async {
      await service.recordAlert('device-1', 'vpn_disabled');
      final shouldSend = await service.shouldAlert('device-1', 'vpn_disabled');
      expect(shouldSend, isFalse);
    });

    test('alert after 11 min should send again', () async {
      await service.recordAlert('device-1', 'vpn_disabled');
      now = now.add(const Duration(minutes: 11));
      final shouldSend = await service.shouldAlert('device-1', 'vpn_disabled');
      expect(shouldSend, isTrue);
    });

    test('3 alerts in last hour should escalate', () async {
      await _seedEvent(
        firestore: firestore,
        deviceId: 'device-1',
        type: 'vpn_disabled',
        timestampEpochMs:
            now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
      await _seedEvent(
        firestore: firestore,
        deviceId: 'device-1',
        type: 'vpn_disabled',
        timestampEpochMs:
            now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
      );
      await _seedEvent(
        firestore: firestore,
        deviceId: 'device-1',
        type: 'vpn_disabled',
        timestampEpochMs:
            now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
      );

      final decision =
          await service.getAlertDecision('device-1', 'vpn_disabled');
      expect(decision.shouldSend, isTrue);
      expect(decision.isEscalated, isTrue);
      expect(decision.escalationMessage, isNotNull);
    });

    test('2 alerts in last hour should not escalate', () async {
      await _seedEvent(
        firestore: firestore,
        deviceId: 'device-1',
        type: 'vpn_disabled',
        timestampEpochMs:
            now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
      await _seedEvent(
        firestore: firestore,
        deviceId: 'device-1',
        type: 'vpn_disabled',
        timestampEpochMs:
            now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
      );

      final decision =
          await service.getAlertDecision('device-1', 'vpn_disabled');
      expect(decision.shouldSend, isTrue);
      expect(decision.isEscalated, isFalse);
      expect(decision.escalationMessage, isNull);
    });
  });
}

Future<void> _seedEvent({
  required FakeFirebaseFirestore firestore,
  required String deviceId,
  required String type,
  required int timestampEpochMs,
}) async {
  await firestore
      .collection('bypass_events')
      .doc(deviceId)
      .collection('events')
      .add(<String, dynamic>{
    'type': type,
    'timestampEpochMs': timestampEpochMs,
  });
}
