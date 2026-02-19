import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/domain_policy_tester_screen.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class _FakeVpnServiceForDomainTester implements VpnServiceBase {
  @override
  Future<bool> clearDnsQueryLogs() async => true;

  @override
  Future<bool> clearRuleCache() async => true;

  @override
  Future<DomainPolicyEvaluation> evaluateDomainPolicy(String domain) async {
    final normalized = domain.trim().toLowerCase();
    final blocked =
        normalized == 'facebook.com' || normalized.endsWith('.facebook.com');
    return DomainPolicyEvaluation(
      inputDomain: domain,
      normalizedDomain: normalized,
      blocked: blocked,
      matchedRule: blocked ? 'facebook.com' : null,
    );
  }

  @override
  Future<List<DnsQueryLogEntry>> getRecentDnsQueries({int limit = 100}) async =>
      const [];

  @override
  Future<RuleCacheSnapshot> getRuleCacheSnapshot({int sampleLimit = 5}) async =>
      const RuleCacheSnapshot.empty();

  @override
  Future<VpnStatus> getStatus() async => const VpnStatus(
        supported: true,
        permissionGranted: true,
        isRunning: false,
      );

  @override
  Future<bool> hasVpnPermission() async => true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> isVpnRunning() async => false;

  @override
  Future<bool> openBatteryOptimizationSettings() async => true;

  @override
  Future<bool> openVpnSettings() async => true;

  @override
  Future<bool> openPrivateDnsSettings() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> startVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
    String? upstreamDns,
  }) async =>
      true;

  @override
  Future<bool> restartVpn({
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
    List<String> temporaryAllowedDomains = const <String>[],
  }) async =>
      true;

  @override
  Future<bool> setUpstreamDns({String? upstreamDns}) async => true;
}

void main() {
  group('DomainPolicyTesterScreen', () {
    testWidgets('evaluates blocked domain from input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DomainPolicyTesterScreen(
            vpnService: _FakeVpnServiceForDomainTester(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('domain_tester_input')),
        'm.facebook.com',
      );
      await tester.tap(find.byKey(const Key('domain_tester_run_button')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('domain_tester_result_header')), findsOneWidget);
      expect(find.text('Blocked by Policy'), findsOneWidget);
      expect(find.text('facebook.com'), findsWidgets);
    });

    testWidgets('quick chip evaluates domain', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DomainPolicyTesterScreen(
            vpnService: _FakeVpnServiceForDomainTester(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('domain_tester_chip_google.com')));
      await tester.pumpAndSettle();

      expect(find.text('Allowed by Policy'), findsOneWidget);
    });
  });
}
