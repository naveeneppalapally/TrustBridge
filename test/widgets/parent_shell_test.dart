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

    Widget buildTestShell({required String parentId}) {
      return ChangeNotifierProvider<PolicyVpnSyncService?>.value(
        value: null,
        child: MaterialApp(
          home: ParentShell(
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
    }

    testWidgets('renders 5 bottom navigation tabs', (tester) async {
      const parentId = 'parent-shell-a';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('parent_shell_bottom_nav')), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Modes'), findsWidgets);
      expect(find.text('Block Apps'), findsOneWidget);
      expect(find.text('Reports'), findsWidgets);
      expect(find.text('Settings'), findsOneWidget);
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

    testWidgets('switches tabs and requires explicit child selection',
        (tester) async {
      const parentId = 'parent-shell-b';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Modes'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Modes'), findsWidgets);
      expect(find.text('Selected child'), findsOneWidget);
      expect(find.text('Choose a child above to continue.'), findsOneWidget);
    });

    testWidgets('falls back to first child when explicit selection flag is off',
        (tester) async {
      RolloutFlags.setForTest('explicit_child_selection', false);
      const parentId = 'parent-shell-explicit-flag';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Modes'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Choose a child above to continue.'), findsNothing);
      expect(find.text('Open Mode Remote'), findsOneWidget);
    });

    testWidgets('reports tab opens usage reports screen', (tester) async {
      const parentId = 'parent-shell-b2';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Reports'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Reports'), findsWidgets);
      expect(find.text('Selected child'), findsOneWidget);
    });

    testWidgets('settings tab opens parent settings screen', (tester) async {
      const parentId = 'parent-shell-settings';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Settings'), findsWidgets);
      expect(find.byKey(const Key('settings_profile_card')), findsOneWidget);
    });

    testWidgets('shows dashboard badge when pending requests exist',
        (tester) async {
      const parentId = 'parent-shell-c';
      await seedChild(parentId);
      await seedPendingRequest(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('parent_shell_dashboard_badge')),
        findsOneWidget,
      );
    });

    testWidgets('bedtime quick action opens modes tab', (tester) async {
      const parentId = 'parent-shell-d';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.dragUntilVisible(
        find.byKey(const Key('dashboard_bedtime_schedule_button')),
        find.byType(CustomScrollView),
        const Offset(0, -240),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester
          .tap(find.byKey(const Key('dashboard_bedtime_schedule_button')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Modes'), findsWidgets);
      expect(find.text('Selected child'), findsOneWidget);
    });
  });
}
