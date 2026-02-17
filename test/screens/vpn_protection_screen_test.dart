import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/domain_policy_tester_screen.dart';
import 'package:trustbridge_app/screens/vpn_protection_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class _FakeVpnService implements VpnServiceBase {
  _FakeVpnService({
    required this.supported,
    required this.permissionGranted,
    required this.running,
  });

  bool supported;
  bool permissionGranted;
  bool running;
  bool permissionResult = true;
  bool startResult = true;
  bool stopResult = true;
  bool ignoringBatteryOptimizations = true;
  int openBatterySettingsCalls = 0;
  int updateFilterRulesCalls = 0;
  int clearRuleCacheCalls = 0;
  List<String> lastUpdatedCategories = const [];
  List<String> lastUpdatedDomains = const [];
  RuleCacheSnapshot ruleCacheSnapshot = const RuleCacheSnapshot(
    categoryCount: 2,
    domainCount: 8,
    sampleCategories: ['adult-content', 'social-networks'],
    sampleDomains: ['facebook.com', 'instagram.com'],
  );

  @override
  Future<VpnStatus> getStatus() async {
    return VpnStatus(
      supported: supported,
      permissionGranted: permissionGranted,
      isRunning: running,
    );
  }

  @override
  Future<bool> hasVpnPermission() async {
    return permissionGranted;
  }

  @override
  Future<bool> isVpnRunning() async {
    return running;
  }

  @override
  Future<bool> requestPermission() async {
    if (permissionResult) {
      permissionGranted = true;
    }
    return permissionResult;
  }

  @override
  Future<bool> startVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
  }) async {
    if (startResult) {
      running = true;
    }
    return startResult;
  }

  @override
  Future<bool> stopVpn() async {
    if (stopResult) {
      running = false;
    }
    return stopResult;
  }

  @override
  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
  }) async {
    updateFilterRulesCalls += 1;
    lastUpdatedCategories = List<String>.from(blockedCategories);
    lastUpdatedDomains = List<String>.from(blockedDomains);
    return true;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    return ignoringBatteryOptimizations;
  }

  @override
  Future<bool> openBatteryOptimizationSettings() async {
    openBatterySettingsCalls += 1;
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
    return ruleCacheSnapshot;
  }

  @override
  Future<bool> clearRuleCache() async {
    clearRuleCacheCalls += 1;
    ruleCacheSnapshot = const RuleCacheSnapshot.empty();
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
  group('VpnProtectionScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    Future<void> seedParent(String parentId) {
      return fakeFirestore.collection('parents').doc(parentId).set({
        'parentId': parentId,
        'preferences': {
          'vpnProtectionEnabled': false,
        },
      });
    }

    testWidgets('renders unsupported status on non-supported service',
        (tester) async {
      final fakeVpn = _FakeVpnService(
        supported: false,
        permissionGranted: false,
        running: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VpnProtectionScreen(
            vpnService: fakeVpn,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-vpn-a',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('VPN Protection Engine'), findsWidgets);
      expect(find.text('Unsupported on this platform'), findsOneWidget);
      expect(find.byKey(const Key('vpn_status_label')), findsOneWidget);
    });

    testWidgets('enable protection updates status and preference',
        (tester) async {
      const parentId = 'parent-vpn-b';
      await seedParent(parentId);

      final fakeVpn = _FakeVpnService(
        supported: true,
        permissionGranted: false,
        running: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VpnProtectionScreen(
            vpnService: fakeVpn,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('vpn_primary_button')));
      await tester.pumpAndSettle();

      expect(find.text('Protection running'), findsOneWidget);
      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;
      expect(preferences['vpnProtectionEnabled'], true);
    });

    testWidgets('disable protection updates status and preference',
        (tester) async {
      const parentId = 'parent-vpn-c';
      await seedParent(parentId);

      final fakeVpn = _FakeVpnService(
        supported: true,
        permissionGranted: true,
        running: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VpnProtectionScreen(
            vpnService: fakeVpn,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('vpn_primary_button')));
      await tester.pumpAndSettle();

      expect(find.text('Ready to start'), findsOneWidget);
      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;
      expect(preferences['vpnProtectionEnabled'], false);
    });

    testWidgets('dns self-check renders blocked decision message',
        (tester) async {
      final fakeVpn = _FakeVpnService(
        supported: true,
        permissionGranted: true,
        running: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VpnProtectionScreen(
            vpnService: fakeVpn,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-vpn-d',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selfCheckButton = find.byKey(const Key('vpn_dns_self_check_button'));
      await tester.dragUntilVisible(
        selfCheckButton,
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      await tester.tap(selfCheckButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('vpn_dns_self_check_result')), findsOneWidget);
      expect(find.textContaining('BLOCKED'), findsOneWidget);
    });

    testWidgets('sync rules button triggers vpn rule update when running',
        (tester) async {
      const parentId = 'parent-vpn-e';
      await seedParent(parentId);

      final fakeVpn = _FakeVpnService(
        supported: true,
        permissionGranted: true,
        running: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VpnProtectionScreen(
            vpnService: fakeVpn,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const Key('vpn_sync_rules_button')));
      await tester.tap(find.byKey(const Key('vpn_sync_rules_button')));
      await tester.pumpAndSettle();

      expect(fakeVpn.updateFilterRulesCalls, 1);
      expect(fakeVpn.lastUpdatedCategories, isNotEmpty);
      expect(find.text('Policy rules synced to active VPN.'), findsOneWidget);
    });

    testWidgets('run readiness test updates summary', (tester) async {
      const parentId = 'parent-vpn-f';
      await seedParent(parentId);

      final fakeVpn = _FakeVpnService(
        supported: true,
        permissionGranted: true,
        running: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VpnProtectionScreen(
            vpnService: fakeVpn,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final readinessButton =
          find.byKey(const Key('vpn_run_health_check_button'));
      await tester.dragUntilVisible(
        readinessButton,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(readinessButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vpn_readiness_summary')), findsOneWidget);
      expect(find.textContaining('checks passed'), findsOneWidget);
    });

    testWidgets('clear rule cache button clears persisted cache',
        (tester) async {
      const parentId = 'parent-vpn-g';
      await seedParent(parentId);

      final fakeVpn = _FakeVpnService(
        supported: true,
        permissionGranted: true,
        running: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VpnProtectionScreen(
            vpnService: fakeVpn,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final clearCacheButton =
          find.byKey(const Key('vpn_clear_rule_cache_button'));
      await tester.dragUntilVisible(
        clearCacheButton,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(clearCacheButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Clear VPN Rule Cache?'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(fakeVpn.clearRuleCacheCalls, 1);
      expect(find.text('Native rule cache cleared.'), findsOneWidget);
    });

    testWidgets('domain policy tester button navigates to tester screen',
        (tester) async {
      const parentId = 'parent-vpn-h';
      await seedParent(parentId);

      final fakeVpn = _FakeVpnService(
        supported: true,
        permissionGranted: true,
        running: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VpnProtectionScreen(
            vpnService: fakeVpn,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('vpn_domain_tester_button'));
      await tester.dragUntilVisible(
        button,
        find.byType(ListView),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(DomainPolicyTesterScreen), findsOneWidget);
    });
  });
}
