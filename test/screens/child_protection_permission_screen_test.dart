import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/child_protection_permission_screen.dart';
import 'package:trustbridge_app/services/app_usage_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class _FakeVpnService implements VpnServiceBase {
  bool permissionGranted = false;
  bool running = false;

  @override
  Future<bool> clearDnsQueryLogs() async => true;

  @override
  Future<bool> clearRuleCache() async => true;

  @override
  Future<DomainPolicyEvaluation> evaluateDomainPolicy(String domain) async {
    return DomainPolicyEvaluation(
      inputDomain: domain,
      normalizedDomain: domain.trim().toLowerCase(),
      blocked: false,
    );
  }

  @override
  Future<RuleCacheSnapshot> getRuleCacheSnapshot({int sampleLimit = 5}) async {
    return const RuleCacheSnapshot.empty();
  }

  @override
  Future<VpnStatus> getStatus() async {
    return VpnStatus(
      supported: true,
      permissionGranted: permissionGranted,
      isRunning: running,
    );
  }

  @override
  Future<bool> hasVpnPermission() async => permissionGranted;

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
  Future<List<DnsQueryLogEntry>> getRecentDnsQueries({int limit = 100}) async {
    return const <DnsQueryLogEntry>[];
  }

  @override
  Future<bool> requestPermission() async {
    permissionGranted = true;
    return true;
  }

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
    running = true;
    return true;
  }

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
  }) async {
    running = true;
    return true;
  }

  @override
  Future<bool> stopVpn() async {
    running = false;
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
    return true;
  }
}

class _FakeAppUsageService extends AppUsageService {
  _FakeAppUsageService({required this.usageAccessGranted});

  bool usageAccessGranted;

  @override
  Future<bool> hasUsageAccessPermission() async => usageAccessGranted;

  @override
  Future<bool> openUsageAccessSettings() async => true;
}

void main() {
  testWidgets(
    'child setup requires usage access before device-admin step',
    (tester) async {
      final vpnService = _FakeVpnService();
      final appUsageService = _FakeAppUsageService(usageAccessGranted: false);

      await tester.pumpWidget(
        MaterialApp(
          home: ChildProtectionPermissionScreen(
            vpnService: vpnService,
            appUsageService: appUsageService,
          ),
        ),
      );

      expect(find.text('Setting up protection for your phone'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text('Allow app access for instant blocking'),
        findsOneWidget,
      );
      expect(find.text('Allow app access'), findsOneWidget);
    },
  );
}
