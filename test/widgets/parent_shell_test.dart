import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

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

    testWidgets('renders 4 bottom navigation tabs', (tester) async {
      const parentId = 'parent-shell-a';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('parent_shell_bottom_nav')), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Schedule'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
    });

    testWidgets('switches tabs and shows schedule screen', (tester) async {
      const parentId = 'parent-shell-b';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Schedule'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Schedule Editor'), findsOneWidget);
    });

    testWidgets('reports tab opens usage reports screen', (tester) async {
      const parentId = 'parent-shell-b2';
      await seedChild(parentId);

      await tester.pumpWidget(buildTestShell(parentId: parentId));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Reports'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Usage Reports'), findsOneWidget);
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

    testWidgets('bedtime quick action opens schedule tab', (tester) async {
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

      expect(find.text('Schedule Editor'), findsOneWidget);
    });
  });
}
