import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class _FakeVpnService implements VpnServiceBase {
  bool vpnRunning = true;
  bool updateSuccess = true;
  int updateCalls = 0;
  List<String> lastCategories = const <String>[];
  List<String> lastDomains = const <String>[];
  List<String> lastAllowedDomains = const <String>[];

  @override
  Future<bool> isVpnRunning() async => vpnRunning;

  @override
  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    List<String> temporaryAllowedDomains = const <String>[],
  }) async {
    updateCalls += 1;
    lastCategories = List<String>.from(blockedCategories)..sort();
    lastDomains = List<String>.from(blockedDomains)..sort();
    lastAllowedDomains = List<String>.from(temporaryAllowedDomains)..sort();
    return updateSuccess;
  }

  @override
  Future<bool> setUpstreamDns({String? upstreamDns}) async => true;

  @override
  Future<VpnStatus> getStatus() async => const VpnStatus.unsupported();

  @override
  Future<bool> hasVpnPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> startVpn({
    List<String> blockedCategories = const <String>[],
    List<String> blockedDomains = const <String>[],
    String? upstreamDns,
  }) async =>
      true;

  @override
  Future<bool> restartVpn({
    List<String> blockedCategories = const <String>[],
    List<String> blockedDomains = const <String>[],
    String? upstreamDns,
  }) async =>
      true;

  @override
  Future<bool> stopVpn() async => true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> openBatteryOptimizationSettings() async => true;

  @override
  Future<bool> openVpnSettings() async => true;

  @override
  Future<bool> openPrivateDnsSettings() async => true;

  @override
  Future<List<DnsQueryLogEntry>> getRecentDnsQueries({int limit = 100}) async =>
      const <DnsQueryLogEntry>[];

  @override
  Future<bool> clearDnsQueryLogs() async => true;

  @override
  Future<RuleCacheSnapshot> getRuleCacheSnapshot({int sampleLimit = 5}) async =>
      const RuleCacheSnapshot.empty();

  @override
  Future<bool> clearRuleCache() async => true;

  @override
  Future<DomainPolicyEvaluation> evaluateDomainPolicy(String domain) async =>
      const DomainPolicyEvaluation.empty();
}

class _FakeFirestoreService extends FirestoreService {
  _FakeFirestoreService() : super(firestore: FakeFirebaseFirestore());

  List<ChildProfile> children = <ChildProfile>[];
  List<String> exceptionDomains = <String>[];
  DateTime? nextExceptionExpiry;
  final StreamController<List<ChildProfile>> _streamController =
      StreamController<List<ChildProfile>>.broadcast();
  bool streamRequested = false;

  @override
  Future<List<ChildProfile>> getChildrenOnce(String parentId) async => children;

  @override
  Stream<List<ChildProfile>> getChildrenStream(String parentId) {
    streamRequested = true;
    return _streamController.stream;
  }

  @override
  Future<List<String>> getActiveApprovedExceptionDomains({
    required String parentId,
    String? childId,
    int limit = 200,
  }) async =>
      List<String>.from(exceptionDomains);

  @override
  Future<DateTime?> getNextApprovedExceptionExpiry({
    required String parentId,
    String? childId,
    int limit = 200,
  }) async =>
      nextExceptionExpiry;

  void emit(List<ChildProfile> nextChildren) {
    _streamController.add(nextChildren);
  }

  Future<void> disposeController() async {
    await _streamController.close();
  }
}

void main() {
  group('PolicyVpnSyncService', () {
    late _FakeVpnService fakeVpn;
    late _FakeFirestoreService fakeFirestore;
    late PolicyVpnSyncService syncService;

    setUp(() {
      fakeVpn = _FakeVpnService();
      fakeFirestore = _FakeFirestoreService();
      syncService = PolicyVpnSyncService(
        vpnService: fakeVpn,
        firestoreService: fakeFirestore,
        parentIdResolver: () => 'parent-test',
      );
    });

    tearDown(() async {
      syncService.dispose();
      await fakeFirestore.disposeController();
    });

    test('initial state starts idle', () {
      expect(syncService.isSyncing, isFalse);
      expect(syncService.lastSyncResult, isNull);
    });

    test('syncNow skips VPN update when VPN is not running', () async {
      fakeVpn.vpnRunning = false;
      fakeFirestore.children = <ChildProfile>[];

      final result = await syncService.syncNow();

      expect(result.success, isTrue);
      expect(result.childrenSynced, 0);
      expect(fakeVpn.updateCalls, 0);
    });

    test('syncNow merges categories and domains from all children', () async {
      fakeVpn.vpnRunning = true;

      final childA = ChildProfile.create(
        nickname: 'A',
        ageBand: AgeBand.young,
      );
      final childB = ChildProfile.create(
        nickname: 'B',
        ageBand: AgeBand.teen,
      );
      final customPolicy = childB.policy.copyWith(
        blockedCategories: <String>['social-networks', 'gambling'],
        blockedDomains: <String>['example.com', 'reddit.com'],
      );

      fakeFirestore.children = <ChildProfile>[
        childA,
        childB.copyWith(policy: customPolicy),
      ];

      final result = await syncService.syncNow();

      expect(result.success, isTrue);
      expect(result.childrenSynced, 2);
      expect(fakeVpn.updateCalls, 1);
      expect(fakeVpn.lastCategories.contains('social-networks'), isTrue);
      expect(fakeVpn.lastCategories.contains('gambling'), isTrue);
      expect(fakeVpn.lastDomains,
          containsAll(<String>['example.com', 'reddit.com']));
    });

    test('syncNow forwards active approved exception domains to VPN', () async {
      fakeVpn.vpnRunning = true;
      final child = ChildProfile.create(
        nickname: 'Child',
        ageBand: AgeBand.middle,
      );
      fakeFirestore.children = <ChildProfile>[child];
      fakeFirestore.exceptionDomains = <String>['instagram.com', 'youtube.com'];

      final result = await syncService.syncNow();

      expect(result.success, isTrue);
      expect(fakeVpn.updateCalls, 1);
      expect(
        fakeVpn.lastAllowedDomains,
        containsAll(<String>['instagram.com', 'youtube.com']),
      );
    });

    test('syncNow schedules a refresh when an exception has expiry', () async {
      fakeVpn.vpnRunning = true;
      fakeFirestore.children = <ChildProfile>[];
      fakeFirestore.nextExceptionExpiry =
          DateTime.now().add(const Duration(minutes: 5));

      await syncService.syncNow();

      expect(syncService.nextExceptionRefreshAt, isNotNull);
      expect(
        syncService.nextExceptionRefreshAt!
            .isAfter(DateTime.now().add(const Duration(minutes: 4))),
        isTrue,
      );
    });

    test('syncNow clears rules when children list is empty', () async {
      fakeVpn.vpnRunning = true;
      fakeFirestore.children = <ChildProfile>[];

      final result = await syncService.syncNow();

      expect(result.success, isTrue);
      expect(result.childrenSynced, 0);
      expect(fakeVpn.updateCalls, 1);
      expect(fakeVpn.lastCategories, isEmpty);
      expect(fakeVpn.lastDomains, isEmpty);
    });

    test('lastSyncResult updates after syncNow', () async {
      fakeVpn.vpnRunning = true;
      fakeFirestore.children = <ChildProfile>[];

      expect(syncService.lastSyncResult, isNull);
      await syncService.syncNow();

      expect(syncService.lastSyncResult, isNotNull);
      expect(syncService.lastSyncResult!.success, isTrue);
    });

    test('expiry timer triggers follow-up sync', () async {
      fakeVpn.vpnRunning = true;
      fakeFirestore.children = <ChildProfile>[];
      final triggerAt = DateTime.now().add(const Duration(milliseconds: 30));
      fakeFirestore.nextExceptionExpiry = triggerAt;
      syncService = PolicyVpnSyncService(
        vpnService: fakeVpn,
        firestoreService: fakeFirestore,
        parentIdResolver: () => 'parent-test',
        exceptionRefreshGrace: Duration.zero,
      );
      syncService.startListening();

      await syncService.syncNow();
      expect(fakeVpn.updateCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(fakeVpn.updateCalls, greaterThanOrEqualTo(2));
    });

    test('startListening auto-syncs when Firestore stream emits update',
        () async {
      fakeVpn.vpnRunning = true;

      final child = ChildProfile.create(
        nickname: 'Stream Child',
        ageBand: AgeBand.middle,
      ).copyWith(
        policy: Policy.presetForAgeBand(AgeBand.middle).copyWith(
          blockedDomains: <String>['facebook.com'],
        ),
      );

      syncService.startListening();
      expect(fakeFirestore.streamRequested, isTrue);

      fakeFirestore.emit(<ChildProfile>[child]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fakeVpn.updateCalls, 1);
      expect(fakeVpn.lastDomains, contains('facebook.com'));
    });
  });
}
