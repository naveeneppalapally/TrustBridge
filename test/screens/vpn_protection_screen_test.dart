import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trustbridge_app/screens/domain_policy_tester_screen.dart';
import 'package:trustbridge_app/screens/vpn_protection_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';
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
  bool restartResult = true;
  bool stopResult = true;
  bool ignoringBatteryOptimizations = true;
  int startCalls = 0;
  int openBatterySettingsCalls = 0;
  int openVpnSettingsCalls = 0;
  int openPrivateDnsSettingsCalls = 0;
  int updateFilterRulesCalls = 0;
  int clearRuleCacheCalls = 0;
  List<String> lastUpdatedCategories = const [];
  List<String> lastUpdatedDomains = const [];
  String? lastStartUpstreamDns;
  String? lastRestartUpstreamDns;
  String? lastSetUpstreamDns;
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
    String? upstreamDns,
  }) async {
    startCalls += 1;
    if (startResult) {
      running = true;
    }
    lastStartUpstreamDns = upstreamDns;
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
  Future<bool> restartVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
    String? upstreamDns,
  }) async {
    if (restartResult) {
      running = true;
    }
    lastRestartUpstreamDns = upstreamDns;
    return restartResult;
  }

  @override
  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    List<String> temporaryAllowedDomains = const <String>[],
  }) async {
    updateFilterRulesCalls += 1;
    lastUpdatedCategories = List<String>.from(blockedCategories);
    lastUpdatedDomains = List<String>.from(blockedDomains);
    return true;
  }

  @override
  Future<bool> setUpstreamDns({String? upstreamDns}) async {
    lastSetUpstreamDns = upstreamDns;
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
  Future<bool> openVpnSettings() async {
    openVpnSettingsCalls += 1;
    return true;
  }

  @override
  Future<bool> openPrivateDnsSettings() async {
    openPrivateDnsSettingsCalls += 1;
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

    Future<void> seedParent(
      String parentId, {
      bool nextDnsEnabled = false,
      String? nextDnsProfileId,
    }) {
      return fakeFirestore.collection('parents').doc(parentId).set({
        'parentId': parentId,
        'preferences': {
          'vpnProtectionEnabled': false,
          'nextDnsEnabled': nextDnsEnabled,
          'nextDnsProfileId': nextDnsProfileId,
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

    testWidgets(
        'enable protection requires notification permission before VPN start',
        (tester) async {
      const parentId = 'parent-vpn-notification-permission';
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
            notificationPermissionRequester: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('vpn_primary_button')));
      await tester.pumpAndSettle();

      expect(fakeVpn.startCalls, 0);
      expect(
        find.text(
          'Notification permission is required for VPN to run in background.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'enable protection applies upstream DNS from parent NextDNS preference',
        (tester) async {
      const parentId = 'parent-vpn-nextdns-start';
      await seedParent(
        parentId,
        nextDnsEnabled: true,
        nextDnsProfileId: 'abc123',
      );

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

      await tester.tap(find.byKey(const Key('vpn_primary_button')));
      await tester.pumpAndSettle();

      expect(fakeVpn.lastStartUpstreamDns, 'abc123.dns.nextdns.io');
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
      final selfCheckButton =
          find.byKey(const Key('vpn_dns_self_check_button'));
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
            notificationPermissionChecker: () async => true,
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
      expect(
        find.text('POST_NOTIFICATIONS permission is granted.'),
        findsOneWidget,
      );
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

    testWidgets('restart button restarts vpn with latest rules',
        (tester) async {
      const parentId = 'parent-vpn-i';
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

      final restartButton = find.byKey(const Key('vpn_restart_button'));
      await tester.dragUntilVisible(
        restartButton,
        find.byType(ListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(restartButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('VPN service restarted with latest policy rules.'),
          findsOneWidget);
    });

    testWidgets('diagnostic shortcuts open VPN and Private DNS settings',
        (tester) async {
      const parentId = 'parent-vpn-j';
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

      final openVpnButton =
          find.byKey(const Key('vpn_open_vpn_settings_button'));
      await tester.dragUntilVisible(
        openVpnButton,
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      await tester.tap(openVpnButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      final openPrivateDnsButton =
          find.byKey(const Key('vpn_open_private_dns_button'));
      await tester.tap(openPrivateDnsButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(fakeVpn.openVpnSettingsCalls, 1);
      expect(fakeVpn.openPrivateDnsSettingsCalls, 1);
    });

    testWidgets('permission recovery card requests VPN permission',
        (tester) async {
      const parentId = 'parent-vpn-k';
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

      expect(find.byKey(const Key('vpn_permission_recovery_label')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('vpn_request_permission_button')));
      await tester.pumpAndSettle();

      expect(fakeVpn.permissionGranted, isTrue);
      expect(find.text('VPN permission granted'), findsOneWidget);
    });

    testWidgets('policy sync card syncs rules via PolicyVpnSyncService',
        (tester) async {
      const parentId = 'parent-vpn-sync';
      await seedParent(parentId);
      await fakeFirestore.collection('children').doc('child-sync-1').set({
        'parentId': parentId,
        'nickname': 'Sync Child',
        'ageBand': '6-9',
        'deviceIds': <String>[],
        'policy': {
          'blockedCategories': <String>['social-networks'],
          'blockedDomains': <String>['reddit.com'],
          'schedules': <Map<String, dynamic>>[],
          'safeSearchEnabled': true,
        },
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 17, 16, 0)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 17, 16, 0)),
      });

      final fakeVpn = _FakeVpnService(
        supported: true,
        permissionGranted: true,
        running: true,
      );
      final syncService = PolicyVpnSyncService(
        firestoreService: firestoreService,
        vpnService: fakeVpn,
        parentIdResolver: () => parentId,
      );
      addTearDown(syncService.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<PolicyVpnSyncService>.value(
          value: syncService,
          child: MaterialApp(
            home: VpnProtectionScreen(
              vpnService: fakeVpn,
              firestoreService: firestoreService,
              parentIdOverride: parentId,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vpn_policy_sync_card')), findsOneWidget);
      expect(find.text('Policy Sync'), findsOneWidget);

      await tester.tap(find.byKey(const Key('vpn_policy_sync_now_button')));
      await tester.pumpAndSettle();

      expect(fakeVpn.updateFilterRulesCalls, greaterThanOrEqualTo(1));
      expect(find.text('Children synced'), findsOneWidget);
      expect(find.text('Domains blocked'), findsOneWidget);
    });
  });
}
