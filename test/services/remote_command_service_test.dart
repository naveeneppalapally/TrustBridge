import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/pairing_service.dart';
import 'package:trustbridge_app/services/remote_command_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

void main() {
  group('RemoteCommandService', () {
    late FakeFirebaseFirestore firestore;
    late _FakePairingService pairingService;
    late _FakeVpnService vpnService;
    late RemoteCommandService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      pairingService = _FakePairingService(
        childId: 'child-1',
        parentId: 'parent-1',
        deviceId: 'device-1',
      );
      vpnService = _FakeVpnService(shouldRestartSucceed: true);
      service = RemoteCommandService(
        firestore: firestore,
        pairingService: pairingService,
        vpnService: vpnService,
      );
    });

    test('sendRestartVpnCommand creates pending command document', () async {
      final commandId = await service.sendRestartVpnCommand('device-1');

      final commandDoc = await firestore
          .collection('devices')
          .doc('device-1')
          .collection('pendingCommands')
          .doc(commandId)
          .get();

      expect(commandDoc.exists, isTrue);
      expect(commandDoc.data()?['command'], 'restartVpn');
      expect(commandDoc.data()?['status'], 'pending');
    });

    test('processPendingCommands executes restart and marks command executed',
        () async {
      final commandRef = firestore
          .collection('devices')
          .doc('device-1')
          .collection('pendingCommands')
          .doc('command-1');

      await commandRef.set(<String, dynamic>{
        'commandId': 'command-1',
        'parentId': 'parent-1',
        'command': 'restartVpn',
        'status': 'pending',
        'attempts': 0,
      });

      await service.processPendingCommands();

      final updated = await commandRef.get();
      expect(updated.data()?['status'], 'executed');
      expect(updated.data()?['attempts'], 1);
      expect(updated.data()?['executedAt'], isNotNull);
      expect(vpnService.lastRestartParentId, 'parent-1');
      expect(vpnService.lastRestartChildId, 'child-1');
      expect(vpnService.lastRestartUsedPersistedRules, isTrue);
    });

    test('processPendingCommands clears pairing and stops protection',
        () async {
      final commandRef = firestore
          .collection('devices')
          .doc('device-1')
          .collection('pendingCommands')
          .doc('command-clear');

      await commandRef.set(<String, dynamic>{
        'commandId': 'command-clear',
        'parentId': 'parent-1',
        'command': RemoteCommandService.commandClearPairingAndStopProtection,
        'childId': 'child-1',
        'reason': 'childProfileDeleted',
        'status': 'pending',
        'attempts': 0,
      });

      await service.processPendingCommands();

      final updated = await commandRef.get();
      expect(updated.data()?['status'], 'executed');
      expect(updated.data()?['attempts'], 1);
      expect(pairingService.clearLocalPairingCalls, 1);
      expect(vpnService.stopVpnCalls, 1);
      expect(vpnService.updateFilterRulesCalls, 1);
      expect(vpnService.restartVpnCalls, 0);
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
  _FakeVpnService({required this.shouldRestartSucceed});

  final bool shouldRestartSucceed;
  int restartVpnCalls = 0;
  int stopVpnCalls = 0;
  int updateFilterRulesCalls = 0;
  String? lastRestartParentId;
  String? lastRestartChildId;
  bool lastRestartUsedPersistedRules = false;

  @override
  Future<bool> restartVpn({
    List<String> blockedCategories = const <String>[],
    List<String> blockedDomains = const <String>[],
    List<String> temporaryAllowedDomains = const <String>[],
    String? parentId,
    String? childId,
    String? upstreamDns,
    bool usePersistedRules = false,
  }) async {
    restartVpnCalls += 1;
    lastRestartParentId = parentId;
    lastRestartChildId = childId;
    lastRestartUsedPersistedRules = usePersistedRules;
    return shouldRestartSucceed;
  }

  @override
  Future<VpnStatus> getStatus() async => const VpnStatus(
        supported: true,
        permissionGranted: true,
        isRunning: true,
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
