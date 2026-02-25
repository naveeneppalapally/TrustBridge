import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/heartbeat_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

void main() {
  group('HeartbeatService', () {
    late FakeFirebaseFirestore firestore;
    late _FakePairingService pairingService;
    late _FakeVpnService vpnService;
    final now = DateTime(2026, 2, 20, 12, 0, 0);

    setUp(() {
      firestore = FakeFirebaseFirestore();
      pairingService = _FakePairingService(
        childId: 'child-1',
        parentId: 'parent-1',
        deviceId: 'device-1',
      );
      vpnService = _FakeVpnService(running: true);
      HeartbeatService.configureForTesting(
        firestore: firestore,
        pairingService: pairingService,
        vpnService: vpnService,
        nowProvider: () => now,
      );
    });

    test('sendHeartbeat updates devices/{deviceId}', () async {
      await firestore
          .collection('children')
          .doc('child-1')
          .set(<String, dynamic>{
        'parentId': 'parent-1',
        'nickname': 'Kid',
        'ageBand': 'middle',
        'deviceIds': <String>['device-1'],
        'policy': <String, dynamic>{
          'blockedCategories': <String>[],
          'blockedDomains': <String>[],
          'schedules': <Map<String, dynamic>>[],
        },
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      await HeartbeatService.sendHeartbeat();

      final snapshot =
          await firestore.collection('devices').doc('device-1').get();
      expect(snapshot.exists, isTrue);
      final data = snapshot.data()!;
      expect(data['vpnActive'], isTrue);
      expect(data['lastSeenEpochMs'], now.millisecondsSinceEpoch);
      expect(data['appVersion'], isNotNull);
    });

    test(
        'sendHeartbeat clears stale pairing and does not recreate deleted child',
        () async {
      await HeartbeatService.sendHeartbeat();

      final deviceSnapshot =
          await firestore.collection('devices').doc('device-1').get();
      expect(
        deviceSnapshot.exists,
        isFalse,
        reason:
            'Heartbeat must not recreate links for a deleted child profile.',
      );
      expect(pairingService.clearLocalPairingCalls, 1);
      expect(vpnService.stopVpnCalls, 1);
      expect(vpnService.updateFilterRulesCalls, 1);
    });

    test('isOffline returns true for 31 minutes ago', () {
      final lastSeen = now.subtract(const Duration(minutes: 31));
      expect(HeartbeatService.isOffline(lastSeen), isTrue);
    });

    test('isOffline returns false for 20 minutes ago', () {
      final lastSeen = now.subtract(const Duration(minutes: 20));
      expect(HeartbeatService.isOffline(lastSeen), isFalse);
    });

    test('isProbablyGone returns true for 25 hours ago', () {
      final lastSeen = now.subtract(const Duration(hours: 25));
      expect(HeartbeatService.isProbablyGone(lastSeen), isTrue);
    });

    test('isProbablyGone returns false for 23 hours ago', () {
      final lastSeen = now.subtract(const Duration(hours: 23));
      expect(HeartbeatService.isProbablyGone(lastSeen), isFalse);
    });
  });
}

class _FakePairingService extends PairingService {
  _FakePairingService({
    required this.childId,
    required this.parentId,
    required this.deviceId,
  }) : super();

  final String childId;
  final String parentId;
  final String deviceId;
  int clearLocalPairingCalls = 0;

  @override
  Future<String> getOrCreateDeviceId() async => deviceId;

  @override
  Future<String?> getPairedChildId() async => childId;

  @override
  Future<String?> getPairedParentId() async => parentId;

  @override
  Future<void> clearLocalPairing() async {
    clearLocalPairingCalls += 1;
  }
}

class _FakeVpnService implements VpnServiceBase {
  _FakeVpnService({required this.running});

  final bool running;
  int stopVpnCalls = 0;
  int updateFilterRulesCalls = 0;

  @override
  Future<VpnStatus> getStatus() async => VpnStatus(
        supported: true,
        permissionGranted: true,
        isRunning: running,
      );

  @override
  Future<bool> clearDnsQueryLogs() async => true;

  @override
  Future<bool> clearRuleCache() async => true;

  @override
  Future<DomainPolicyEvaluation> evaluateDomainPolicy(String domain) async =>
      const DomainPolicyEvaluation.empty();

  @override
  Future<RuleCacheSnapshot> getRuleCacheSnapshot({int sampleLimit = 5}) async =>
      const RuleCacheSnapshot.empty();

  @override
  Future<List<DnsQueryLogEntry>> getRecentDnsQueries({int limit = 100}) async =>
      const <DnsQueryLogEntry>[];

  @override
  Future<bool> hasVpnPermission() async => true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> isVpnRunning() async => running;

  @override
  Future<bool> openBatteryOptimizationSettings() async => true;

  @override
  Future<bool> openPrivateDnsSettings() async => true;

  @override
  Future<bool> openVpnSettings() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> restartVpn({
    List<String> blockedCategories = const <String>[],
    List<String> blockedDomains = const <String>[],
    List<String> temporaryAllowedDomains = const <String>[],
    String? parentId,
    String? childId,
    String? upstreamDns,
  }) async =>
      true;

  @override
  Future<bool> setUpstreamDns({String? upstreamDns}) async => true;

  @override
  Future<bool> startVpn({
    List<String> blockedCategories = const <String>[],
    List<String> blockedDomains = const <String>[],
    List<String> temporaryAllowedDomains = const <String>[],
    String? parentId,
    String? childId,
    String? upstreamDns,
  }) async =>
      true;

  @override
  Future<bool> stopVpn() async {
    stopVpnCalls += 1;
    return true;
  }

  @override
  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    List<String> temporaryAllowedDomains = const <String>[],
    String? parentId,
    String? childId,
  }) async {
    updateFilterRulesCalls += 1;
    return true;
  }
}
