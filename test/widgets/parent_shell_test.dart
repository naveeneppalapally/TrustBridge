import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';
import 'package:trustbridge_app/widgets/parent_shell.dart';

void main() {
  group('ParentShell', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      RolloutFlags.resetForTest();
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    tearDown(RolloutFlags.resetForTest);

    Future<void> seedChild(String parentId) {
      return fakeFirestore.collection('children').doc('child-shell-1').set({
        'parentId': parentId,
        'nickname': 'Leo',
        'ageBand': AgeBand.young.value,
        'deviceIds': <String>[],
        'policy': Policy.presetForAgeBand(AgeBand.young).toMap(),
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 20, 9)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 20, 9)),
      });
    }

    Future<void> seedPendingRequest(String parentId) {
      final request = AccessRequest.create(
        childId: 'child-shell-1',
        parentId: parentId,
        childNickname: 'Leo',
        appOrSite: 'instagram.com',
        duration: RequestDuration.thirtyMin,
      );
      return fakeFirestore
          .collection('parents')
          .doc(parentId)
          .collection('access_requests')
          .doc(request.id)
          .set(request.toFirestore());
    }

    Widget buildTestShell({
      required String parentId,
      int initialIndex = 0,
    }) {
      return ChangeNotifierProvider<PolicyVpnSyncService?>.value(
        value: null,
        child: MaterialApp(
          home: ParentShell(
            firestoreService: firestoreService,
            parentIdOverride: parentId,
            initialIndex: initialIndex,
          ),
        ),
      );
    }

    testWidgets('renders Children and Settings tabs', (tester) async {
      const parentId = 'parent-shell-a';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('parent_shell_bottom_nav')), findsOneWidget);
      expect(find.text('Children'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('Modes'), findsNothing);
      expect(find.text('Reports'), findsNothing);
    });

    testWidgets('hides advanced drawer button when adaptive nav flag is off',
        (tester) async {
      RolloutFlags.setForTest('adaptive_parent_nav', false);
      const parentId = 'parent-shell-nav-flag';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('parent_shell_advanced_drawer_button')),
        findsNothing,
      );
    });

    testWidgets('switches to Settings tab and shows settings screen',
        (tester) async {
      const parentId = 'parent-shell-settings';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('settings_profile_card')), findsOneWidget);
    });

    testWidgets('initialIndex clamps to available tabs', (tester) async {
      const parentId = 'parent-shell-index';
      await seedChild(parentId);

      await tester.pumpWidget(
        buildTestShell(
          parentId: parentId,
          initialIndex: 5,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('settings_profile_card')), findsOneWidget);
    });

    testWidgets('shows children badge when pending requests exist',
        (tester) async {
      const parentId = 'parent-shell-badge';
      await seedChild(parentId);
      await seedPendingRequest(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('parent_shell_dashboard_badge')),
        findsOneWidget,
      );
    });
  });
}
