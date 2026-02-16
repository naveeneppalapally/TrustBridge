import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    return true;
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
      expect(
          find.byKey(const Key('vpn_dns_self_check_button')), findsOneWidget);
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

      await tester
          .ensureVisible(find.byKey(const Key('vpn_dns_self_check_button')));
      await tester.tap(find.byKey(const Key('vpn_dns_self_check_button')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('vpn_dns_self_check_result')), findsOneWidget);
      expect(find.textContaining('BLOCKED'), findsOneWidget);
    });
  });
}
