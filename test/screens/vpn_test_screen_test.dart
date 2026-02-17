import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/vpn_test_screen.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class _FakeVpnServiceForTest implements VpnServiceBase {
  bool permission = false;
  bool running = false;

  @override
  Future<VpnStatus> getStatus() async {
    return VpnStatus(
      supported: true,
      permissionGranted: permission,
      isRunning: running,
    );
  }

  @override
  Future<bool> hasVpnPermission() async => permission;

  @override
  Future<bool> isVpnRunning() async => running;

  @override
  Future<bool> requestPermission() async {
    permission = true;
    return true;
  }

  @override
  Future<bool> startVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
  }) async {
    if (!permission) {
      return false;
    }
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
  }) async {
    return true;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    return true;
  }

  @override
  Future<bool> openBatteryOptimizationSettings() async {
    return true;
  }

  @override
  Future<List<DnsQueryLogEntry>> getRecentDnsQueries({int limit = 100}) async {
    return const [];
  }

  @override
  Future<bool> clearDnsQueryLogs() async {
    return true;
  }

  @override
  Future<RuleCacheSnapshot> getRuleCacheSnapshot({int sampleLimit = 5}) async {
    return const RuleCacheSnapshot.empty();
  }

  @override
  Future<bool> clearRuleCache() async {
    return true;
  }

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
}

void main() {
  group('VpnTestScreen', () {
    testWidgets('renders request permission state', (tester) async {
      final fakeService = _FakeVpnServiceForTest();

      await tester.pumpWidget(
        MaterialApp(
          home: VpnTestScreen(vpnService: fakeService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vpn_test_request_permission_button')),
          findsOneWidget);
      expect(find.textContaining('Permission needed'), findsOneWidget);
    });

    testWidgets('permission then start flow updates status', (tester) async {
      final fakeService = _FakeVpnServiceForTest();

      await tester.pumpWidget(
        MaterialApp(
          home: VpnTestScreen(vpnService: fakeService),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('vpn_test_request_permission_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vpn_test_start_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('vpn_test_start_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vpn_test_stop_button')), findsOneWidget);
      expect(find.textContaining('VPN started'), findsOneWidget);
    });
  });
}
