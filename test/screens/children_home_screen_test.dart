import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/dashboard_state.dart';
import 'package:trustbridge_app/screens/children_home_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('ChildrenHomeScreen status rendering', () {
    late FirestoreService firestoreService;

    setUp(() {
      firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
    });

    DashboardStateSnapshot buildDashboardState({
      required DashboardChildSummary child,
    }) {
      return DashboardStateSnapshot(
        parentId: 'parent-status-test',
        children: <DashboardChildSummary>[child],
        totalPendingRequests: 0,
        totalScreenTimeTodayMs: 0,
        generatedAtEpochMs: DateTime(2026, 3, 3, 12).millisecondsSinceEpoch,
        updatedAt: DateTime(2026, 3, 3, 12),
      );
    }

    Future<void> pumpHome(
      WidgetTester tester, {
      required DashboardStateSnapshot state,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildrenHomeScreen(
            firestoreService: firestoreService,
            parentIdOverride: 'parent-status-test',
            dashboardState: state,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'uses dashboard protectionStatus over raw online/vpn flags',
      (tester) async {
        final state = buildDashboardState(
          child: DashboardChildSummary(
            childId: 'child-a',
            name: 'Leo',
            protectionEnabled: true,
            protectionStatus: 'unprotected',
            activeMode: 'free_play',
            screenTimeTodayMs: 0,
            pendingRequestCount: 0,
            online: true,
            vpnActive: true,
            lastSeenEpochMs: DateTime(2026, 3, 3, 12).millisecondsSinceEpoch,
            updatedAtEpochMs: DateTime(2026, 3, 3, 12).millisecondsSinceEpoch,
          ),
        );

        await pumpHome(tester, state: state);

        expect(find.text('Unprotected'), findsOneWidget);
        expect(find.text('Protected'), findsNothing);
      },
    );

    testWidgets(
      'falls back to online/vpn flags when protectionStatus is unknown',
      (tester) async {
        final state = buildDashboardState(
          child: DashboardChildSummary(
            childId: 'child-b',
            name: 'Mia',
            protectionEnabled: true,
            protectionStatus: '',
            activeMode: 'free_play',
            screenTimeTodayMs: 0,
            pendingRequestCount: 0,
            online: true,
            vpnActive: true,
            lastSeenEpochMs: DateTime(2026, 3, 3, 12).millisecondsSinceEpoch,
            updatedAtEpochMs: DateTime(2026, 3, 3, 12).millisecondsSinceEpoch,
          ),
        );

        await pumpHome(tester, state: state);

        expect(find.text('Protected'), findsOneWidget);
      },
    );
  });
}
