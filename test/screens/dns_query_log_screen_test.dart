import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/dns_query_log_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class _FakeVpnServiceForDnsLogs implements VpnServiceBase {
  _FakeVpnServiceForDnsLogs({
    this.entries = const [],
    this.running = true,
    this.permissionGranted = true,
  });

  List<DnsQueryLogEntry> entries;
  bool running;
  bool permissionGranted;
  int clearCalls = 0;

  @override
  Future<VpnStatus> getStatus() async {
    return VpnStatus(
      supported: true,
      permissionGranted: permissionGranted,
      isRunning: running,
      queriesProcessed: entries.length,
      queriesBlocked: entries.where((entry) => entry.blocked).length,
      queriesAllowed: entries.where((entry) => !entry.blocked).length,
      blockedCategoryCount: 2,
      blockedDomainCount: 10,
      startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      lastRuleUpdateAt: DateTime.now().subtract(const Duration(seconds: 20)),
    );
  }

  @override
  Future<bool> hasVpnPermission() async => permissionGranted;

  @override
  Future<bool> isVpnRunning() async => running;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> startVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
  }) async {
    running = true;
    return true;
  }

  @override
  Future<bool> restartVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
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
    return entries.take(limit).toList();
  }

  @override
  Future<bool> clearDnsQueryLogs() async {
    clearCalls += 1;
    entries = const [];
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
    return DomainPolicyEvaluation(
      inputDomain: domain,
      normalizedDomain: domain.trim().toLowerCase(),
      blocked: false,
    );
  }
}

void main() {
  group('DnsQueryLogScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    Future<void> seedParent({
      required String parentId,
      required bool incognitoEnabled,
    }) async {
      await fakeFirestore.collection('parents').doc(parentId).set({
        'parentId': parentId,
        'preferences': {
          'incognitoModeEnabled': incognitoEnabled,
        },
      });
    }

    testWidgets('renders DNS entries when incognito mode is off',
        (tester) async {
      const parentId = 'parent-log-a';
      await seedParent(parentId: parentId, incognitoEnabled: false);
      final fakeVpn = _FakeVpnServiceForDnsLogs(
        running: true,
        permissionGranted: true,
        entries: [
          DnsQueryLogEntry(
            domain: 'reddit.com',
            blocked: true,
            timestamp: DateTime.now().subtract(const Duration(seconds: 8)),
          ),
          DnsQueryLogEntry(
            domain: 'google.com',
            blocked: false,
            timestamp: DateTime.now().subtract(const Duration(seconds: 4)),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DnsQueryLogScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
            vpnService: fakeVpn,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DNS Query Log'), findsOneWidget);
      expect(find.text('Session Overview'), findsOneWidget);
      expect(find.text('reddit.com'), findsOneWidget);
      expect(find.text('google.com'), findsOneWidget);
    });

    testWidgets('shows privacy message and hides logs in incognito mode',
        (tester) async {
      const parentId = 'parent-log-b';
      await seedParent(parentId: parentId, incognitoEnabled: true);
      final fakeVpn = _FakeVpnServiceForDnsLogs(
        running: true,
        permissionGranted: true,
        entries: [
          DnsQueryLogEntry(
            domain: 'youtube.com',
            blocked: true,
            timestamp: DateTime.now(),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DnsQueryLogScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
            vpnService: fakeVpn,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dns_log_privacy_mode_message')),
          findsOneWidget);
      expect(find.text('youtube.com'), findsNothing);
    });

    testWidgets('clear button clears query logs', (tester) async {
      const parentId = 'parent-log-c';
      await seedParent(parentId: parentId, incognitoEnabled: false);
      final fakeVpn = _FakeVpnServiceForDnsLogs(
        running: true,
        permissionGranted: true,
        entries: [
          DnsQueryLogEntry(
            domain: 'facebook.com',
            blocked: true,
            timestamp: DateTime.now(),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DnsQueryLogScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
            vpnService: fakeVpn,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dns_log_clear_button')));
      await tester.pumpAndSettle();

      expect(find.text('Clear DNS Query Logs?'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(fakeVpn.clearCalls, 1);
      expect(find.byKey(const Key('dns_log_empty_state')), findsOneWidget);
    });
  });
}
