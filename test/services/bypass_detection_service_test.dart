import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/bypass_detection_service.dart';
import 'package:trustbridge_app/services/device_admin_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

void main() {
  group('BypassDetectionService', () {
    late FakeFirebaseFirestore firestore;
    late _FakePairingService pairingService;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      pairingService = _FakePairingService(
        childId: 'child-1',
        parentId: 'parent-1',
        deviceId: 'device-1',
      );
    });

    test('logBypassEvent(vpn_disabled) creates Firestore event doc', () async {
      final service = BypassDetectionService(
        firestore: firestore,
        pairingService: pairingService,
        vpnService: _FakeVpnService(),
      );

      await service.logBypassEvent('vpn_disabled');

      final snapshot = await firestore
          .collection('bypass_events')
          .doc('device-1')
          .collection('events')
          .get();

      expect(snapshot.docs.length, 1);
      expect(snapshot.docs.first.data()['type'], 'vpn_disabled');
      expect(snapshot.docs.first.data()['childId'], 'child-1');
    });

    test('alertParent(vpn_disabled) creates notification queue doc', () async {
      final service = BypassDetectionService(
        firestore: firestore,
        pairingService: pairingService,
        vpnService: _FakeVpnService(),
      );

      await service.alertParent('vpn_disabled');

      final snapshot = await firestore.collection('notification_queue').get();
      expect(snapshot.docs.length, 1);
      expect(snapshot.docs.first.data()['parentId'], 'parent-1');
      expect(snapshot.docs.first.data()['eventType'], 'vpn_disabled');
    });

    test('logBypassEvent stores local queue item when write fails', () async {
      final service = BypassDetectionService(
        firestore: firestore,
        pairingService: pairingService,
        vpnService: _FakeVpnService(),
        eventWriter: (_) async {
          throw const SocketException('offline');
        },
      );

      await service.logBypassEvent('vpn_disabled');
      expect(service.queuedEventCount, 1);
    });

    test('private DNS mode change logs private_dns_changed', () async {
      final loggedEvents = <Map<String, dynamic>>[];

      final fakeAdmin = _FakeDeviceAdminService(initialMode: 'off');
      final service = BypassDetectionService(
        firestore: firestore,
        pairingService: pairingService,
        vpnService: _FakeVpnService(),
        deviceAdminService: fakeAdmin,
        eventWriter: (payload) async {
          loggedEvents.add(payload);
        },
      );

      await service.startPrivateDnsMonitoring();
      fakeAdmin.mode = 'hostname';
      await service.runPrivateDnsCheckOnce();

      expect(
        loggedEvents.where((e) => e['type'] == 'private_dns_changed').isNotEmpty,
        isTrue,
      );
    });
  });
}

class _FakePairingService extends PairingService {
  _FakePairingService({
    required this.childId,
    required this.parentId,
    required this.deviceId,
  }) : super(
          firestore: FakeFirebaseFirestore(),
        );

  final String childId;
  final String parentId;
  final String deviceId;

  @override
  Future<String> getOrCreateDeviceId() async => deviceId;

  @override
  Future<String?> getPairedChildId() async => childId;

  @override
  Future<String?> getPairedParentId() async => parentId;
}

class _FakeDeviceAdminService extends DeviceAdminService {
  _FakeDeviceAdminService({required this.initialMode})
      : super(channel: const MethodChannel('test/device_admin'));

  final String initialMode;
  String? mode;

  @override
  Future<String?> getPrivateDnsMode() async {
    return mode ?? initialMode;
  }
}

class _FakeVpnService implements VpnServiceBase {
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
      const [];

  @override
  Future<VpnStatus> getStatus() async => const VpnStatus(
        supported: true,
        permissionGranted: true,
        isRunning: true,
      );

  @override
  Future<bool> hasVpnPermission() async => true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> isVpnRunning() async => true;

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
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
    String? upstreamDns,
  }) async =>
      true;

  @override
  Future<bool> setUpstreamDns({String? upstreamDns}) async => true;

  @override
  Future<bool> startVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
    String? upstreamDns,
  }) async =>
      true;

  @override
  Future<bool> stopVpn() async => true;

  @override
  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    List<String> temporaryAllowedDomains = const [],
  }) async =>
      true;
}
