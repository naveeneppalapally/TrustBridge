import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/nextdns_settings_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class _FakeVpnServiceForNextDnsScreen implements VpnServiceBase {
  _FakeVpnServiceForNextDnsScreen({this.running = false});

  bool running;
  String? lastUpstreamDns;

  @override
  Future<VpnStatus> getStatus() async {
    return VpnStatus(
      supported: true,
      permissionGranted: true,
      isRunning: running,
    );
  }

  @override
  Future<bool> hasVpnPermission() async => true;

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
  Future<bool> setUpstreamDns({String? upstreamDns}) async {
    lastUpstreamDns = upstreamDns;
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
  Future<bool> openVpnSettings() async {
    return true;
  }

  @override
  Future<bool> openPrivateDnsSettings() async {
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
    return DomainPolicyEvaluation(
      inputDomain: domain,
      normalizedDomain: domain.trim().toLowerCase(),
      blocked: false,
    );
  }
}

void main() {
  group('NextDnsSettingsScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    Future<void> seedParent(String parentId) async {
      await fakeFirestore.collection('parents').doc(parentId).set({
        'parentId': parentId,
        'preferences': {
          'nextDnsEnabled': false,
          'nextDnsProfileId': null,
        },
      });
    }

    testWidgets('renders nextdns settings content', (tester) async {
      const parentId = 'parent-nextdns-a';
      await seedParent(parentId);

      await tester.pumpWidget(
        MaterialApp(
          home: NextDnsSettingsScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
            vpnService: _FakeVpnServiceForNextDnsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NextDNS Integration'), findsOneWidget);
      expect(find.byKey(const Key('nextdns_enabled_switch')), findsOneWidget);
      expect(find.byKey(const Key('nextdns_profile_field')), findsOneWidget);
      expect(find.byKey(const Key('nextdns_save_button')), findsOneWidget);
    });

    testWidgets('shows validation when enabled without profile id',
        (tester) async {
      const parentId = 'parent-nextdns-b';
      await seedParent(parentId);

      await tester.pumpWidget(
        MaterialApp(
          home: NextDnsSettingsScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
            vpnService: _FakeVpnServiceForNextDnsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextdns_enabled_switch')));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nextdns_save_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Profile ID is required when NextDNS is enabled.'),
        findsOneWidget,
      );
    });

    testWidgets('saves normalized nextdns profile settings', (tester) async {
      const parentId = 'parent-nextdns-c';
      await seedParent(parentId);
      final fakeVpn = _FakeVpnServiceForNextDnsScreen(running: true);

      await tester.pumpWidget(
        MaterialApp(
          home: NextDnsSettingsScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
            vpnService: fakeVpn,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextdns_enabled_switch')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('nextdns_profile_field')),
        'ABC123',
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nextdns_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('NextDNS settings saved and applied to VPN.'),
          findsOneWidget);

      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;
      expect(preferences['nextDnsEnabled'], true);
      expect(preferences['nextDnsProfileId'], 'abc123');
      expect(fakeVpn.lastUpstreamDns, 'abc123.dns.nextdns.io');
    });
  });
}
