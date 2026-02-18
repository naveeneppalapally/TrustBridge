import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/support_ticket.dart';
import 'package:trustbridge_app/screens/beta_feedback_history_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('BetaFeedbackHistoryScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    testWidgets('shows empty state when no tickets exist',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-empty',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Feedback History'), findsOneWidget);
      expect(find.text('No feedback yet'), findsOneWidget);
      expect(
          find.byKey(const Key('feedback_history_empty_cta')), findsOneWidget);
    });

    testWidgets('renders parent tickets for selected parent',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await fakeFirestore.collection('supportTickets').doc('ticket-a').set({
        'parentId': 'parent-history-a',
        'subject': '[Beta][High] VPN issue',
        'message': 'VPN did not reconnect automatically after reboot once.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 17, 12, 30),
        'updatedAt': DateTime(2026, 2, 17, 12, 45),
      });
      await fakeFirestore.collection('supportTickets').doc('ticket-b').set({
        'parentId': 'parent-history-b',
        'subject': '[Beta][Low] Other parent ticket',
        'message': 'This should not be visible in another parent view.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 17, 13, 30),
        'updatedAt': DateTime(2026, 2, 17, 13, 45),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('[Beta][High] VPN issue'), findsOneWidget);
      expect(find.text('[Beta][Low] Other parent ticket'), findsNothing);
      expect(find.text('Open'), findsWidgets);

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-a')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-a')),
          findsOneWidget);
    });

    testWidgets('floating action button opens beta feedback form',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-c',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('feedback_history_new_button')));
      await tester.pumpAndSettle();

      expect(find.text('Help shape TrustBridge Beta'), findsOneWidget);
      expect(
          find.byKey(const Key('beta_feedback_submit_button')), findsOneWidget);
    });

    testWidgets('analytics app bar action opens duplicate analytics screen',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-analytics-nav',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('feedback_history_analytics_button')));
      await tester.pumpAndSettle();

      expect(find.text('Duplicate Analytics'), findsOneWidget);
    });

    testWidgets('applies source, status, and search filters',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-beta-open')
          .set({
        'parentId': 'parent-history-filters',
        'subject': '[Beta][High] Crash in dashboard',
        'message': 'Dashboard crashed after toggling mode quickly.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 17, 10, 0),
        'updatedAt': DateTime(2026, 2, 17, 10, 5),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-support-resolved')
          .set({
        'parentId': 'parent-history-filters',
        'subject': 'Policy Question',
        'message': 'Need help with schedule overlap behavior.',
        'status': 'resolved',
        'createdAt': DateTime(2026, 2, 17, 11, 0),
        'updatedAt': DateTime(2026, 2, 17, 11, 15),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-beta-resolved')
          .set({
        'parentId': 'parent-history-filters',
        'subject': '[Beta][Low] Minor spacing issue',
        'message': 'Padding is slightly off in request details card.',
        'status': 'resolved',
        'createdAt': DateTime(2026, 2, 17, 12, 0),
        'updatedAt': DateTime(2026, 2, 17, 12, 10),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-filters',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default source filter is Beta.
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-beta-open')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-beta-open')),
          findsOneWidget);
      expect(
          find.byKey(
              const Key('feedback_history_ticket_ticket-support-resolved')),
          findsNothing);

      await tester.tap(find.byKey(const Key('feedback_history_source_all')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(
            const Key('feedback_history_ticket_ticket-support-resolved')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
          find.byKey(
              const Key('feedback_history_ticket_ticket-support-resolved')),
          findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('feedback_history_search_input')),
        'policy',
      );
      await tester.pumpAndSettle();
      expect(
          find.byKey(
              const Key('feedback_history_ticket_ticket-support-resolved')),
          findsOneWidget);
      expect(
          find.byKey(const Key('feedback_history_ticket_ticket-beta-resolved')),
          findsNothing);
    });

    testWidgets('applies severity filter and severity sort',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await fakeFirestore.collection('supportTickets').doc('ticket-low').set({
        'parentId': 'parent-history-priority',
        'subject': '[Beta][Low] Minor copy issue',
        'message': 'Text typo in settings subtitle.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 17, 12, 0),
        'updatedAt': DateTime(2026, 2, 17, 12, 5),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-critical')
          .set({
        'parentId': 'parent-history-priority',
        'subject': '[Beta][Critical] VPN crash',
        'message': 'VPN crashes when enabling from onboarding.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 17, 11, 0),
        'updatedAt': DateTime(2026, 2, 17, 11, 5),
      });
      await fakeFirestore.collection('supportTickets').doc('ticket-high').set({
        'parentId': 'parent-history-priority',
        'subject': '[Beta][High] Sync delay',
        'message': 'Policy sync takes too long after save.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 17, 13, 0),
        'updatedAt': DateTime(2026, 2, 17, 13, 5),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-priority',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('feedback_history_severity_critical')));
      await tester.pumpAndSettle();
      expect(find.text('[Beta][Critical] VPN crash'), findsOneWidget);
      expect(find.text('[Beta][Low] Minor copy issue'), findsNothing);

      await tester.tap(find.byKey(const Key('feedback_history_severity_all')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('feedback_history_sort_highestSeverity')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-critical')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-critical')),
          findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-low')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-low')),
          findsOneWidget);
    });

    testWidgets('applies attention and stale filters',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();

      await fakeFirestore.collection('supportTickets').doc('ticket-fresh').set({
        'parentId': 'parent-history-aging',
        'subject': '[Beta][Medium] Fresh report',
        'message': 'Just submitted and should not be marked stale.',
        'status': 'open',
        'createdAt': now.subtract(const Duration(hours: 2)),
        'updatedAt': now.subtract(const Duration(hours: 2)),
      });
      await fakeFirestore.collection('supportTickets').doc('ticket-attn').set({
        'parentId': 'parent-history-aging',
        'subject': '[Beta][High] Waiting reply',
        'message': 'Open for over a day, should need attention.',
        'status': 'open',
        'createdAt': now.subtract(const Duration(hours: 30)),
        'updatedAt': now.subtract(const Duration(hours: 30)),
      });
      await fakeFirestore.collection('supportTickets').doc('ticket-stale').set({
        'parentId': 'parent-history-aging',
        'subject': '[Beta][High] Stale unresolved issue',
        'message': 'Open for multiple days.',
        'status': 'open',
        'createdAt': now.subtract(const Duration(hours: 90)),
        'updatedAt': now.subtract(const Duration(hours: 60)),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-resolved-old')
          .set({
        'parentId': 'parent-history-aging',
        'subject': '[Beta][Low] Old but resolved',
        'message': 'Resolved tickets should not count as attention.',
        'status': 'resolved',
        'createdAt': now.subtract(const Duration(hours: 120)),
        'updatedAt': now.subtract(const Duration(hours: 110)),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-aging',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('feedback_history_attention_attention')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feedback_history_ticket_ticket-attn')),
          findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-stale')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-stale')),
          findsOneWidget);
      expect(find.byKey(const Key('feedback_history_ticket_ticket-fresh')),
          findsNothing);
      expect(
          find.byKey(const Key('feedback_history_ticket_ticket-resolved-old')),
          findsNothing);

      await tester
          .tap(find.byKey(const Key('feedback_history_attention_stale')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-stale')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-stale')),
          findsOneWidget);
      expect(find.byKey(const Key('feedback_history_ticket_ticket-attn')),
          findsNothing);
    });

    testWidgets('sorts by highest duplicate cluster first',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-cluster-a1')
          .set({
        'parentId': 'parent-history-dup-sort',
        'subject': '[Beta][High] VPN crash on enable',
        'message': 'Cluster A first report.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 0),
        'updatedAt': DateTime(2026, 2, 18, 8, 1),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-cluster-a2')
          .set({
        'parentId': 'parent-history-dup-sort',
        'subject': '[Beta][Medium] vpn crash on enable!',
        'message': 'Cluster A second report.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 5),
        'updatedAt': DateTime(2026, 2, 18, 8, 6),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-cluster-a3')
          .set({
        'parentId': 'parent-history-dup-sort',
        'subject': '[Beta][Low] VPN crash on enable??',
        'message': 'Cluster A third report.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 10),
        'updatedAt': DateTime(2026, 2, 18, 8, 11),
      });

      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-cluster-b1')
          .set({
        'parentId': 'parent-history-dup-sort',
        'subject': '[Beta][Critical] Schedule confusion',
        'message': 'Cluster B first report.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 9, 0),
        'updatedAt': DateTime(2026, 2, 18, 9, 1),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-cluster-b2')
          .set({
        'parentId': 'parent-history-dup-sort',
        'subject': '[Beta][High] schedule confusion',
        'message': 'Cluster B second report.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 9, 5),
        'updatedAt': DateTime(2026, 2, 18, 9, 6),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-dup-sort',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Largest cluster: 3'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('feedback_history_sort_highestDuplicateCluster')),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-cluster-a3')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-cluster-a3')),
          findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-cluster-b2')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-cluster-b2')),
          findsOneWidget);
    });

    testWidgets('top duplicate cluster chip applies focused duplicate search',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-top-dup-a')
          .set({
        'parentId': 'parent-history-top-cluster',
        'subject': '[Beta][High] VPN crash on enable',
        'message': 'Crash appears on child tablet.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 0),
        'updatedAt': DateTime(2026, 2, 18, 8, 1),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-top-dup-b')
          .set({
        'parentId': 'parent-history-top-cluster',
        'subject': '[Beta][Low] vpn crash on enable!!',
        'message': 'Same issue on second child phone.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 2),
        'updatedAt': DateTime(2026, 2, 18, 8, 3),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-top-unique')
          .set({
        'parentId': 'parent-history-top-cluster',
        'subject': '[Beta][Medium] Notification badge mismatch',
        'message': 'Unread badge count seems off by one.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 4),
        'updatedAt': DateTime(2026, 2, 18, 8, 5),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-top-cluster',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_top_cluster_0')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('feedback_history_top_cluster_0')));
      await tester.pumpAndSettle();

      expect(find.text('Showing 2 of 3 tickets'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-top-dup-a')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const Key('feedback_history_ticket_ticket-top-dup-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('feedback_history_ticket_ticket-top-unique')),
        findsNothing,
      );
    });

    testWidgets('applies duplicate-only filter and shows duplicate badge',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await fakeFirestore.collection('supportTickets').doc('ticket-dup-a').set({
        'parentId': 'parent-history-duplicates',
        'subject': '[Beta][High] VPN crash on enable',
        'message': 'Crashes right after I enable protection.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 0),
        'updatedAt': DateTime(2026, 2, 18, 8, 5),
      });
      await fakeFirestore.collection('supportTickets').doc('ticket-dup-b').set({
        'parentId': 'parent-history-duplicates',
        'subject': '[Beta][Low] vpn crash on enable!!!',
        'message': 'Same crash issue seen on another phone.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 10),
        'updatedAt': DateTime(2026, 2, 18, 8, 12),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-unique')
          .set({
        'parentId': 'parent-history-duplicates',
        'subject': '[Beta][Medium] Schedule overlap confusion',
        'message': 'Unsure which rule wins during overlaps.',
        'status': 'open',
        'createdAt': DateTime(2026, 2, 18, 8, 20),
        'updatedAt': DateTime(2026, 2, 18, 8, 21),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-history-duplicates',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dup clusters: 1'), findsOneWidget);
      expect(find.text('Dup reports: 2'), findsOneWidget);

      await tester
          .tap(find.byKey(const Key('feedback_history_duplicate_duplicates')));
      await tester.pumpAndSettle();

      expect(find.text('Showing 2 of 3 tickets'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-dup-a')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-dup-a')),
          findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_ticket-dup-b')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('feedback_history_ticket_ticket-dup-b')),
          findsOneWidget);
      expect(find.byKey(const Key('feedback_history_ticket_ticket-unique')),
          findsNothing);
    });
  });

  group('BetaFeedbackHistoryScreen Day 69 bulk actions', () {
    testWidgets(
        'resolve cluster FAB appears when focused cluster has duplicates',
        (tester) async {
      final fakeService = FakeFirestoreService();
      fakeService.tickets = [
        _ticket(id: 'a', parentId: 'parent-1', subject: '[Beta] Bug A'),
        _ticket(id: 'b', parentId: 'parent-1', subject: '[Beta] Bug A'),
        _ticket(id: 'c', parentId: 'parent-1', subject: '[Beta] Other'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-1',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('feedback_history_top_cluster_0')));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FloatingActionButton, 'Resolve Cluster (2)'),
        findsOneWidget,
      );
    });

    testWidgets('bulk resolve updates all matching tickets', (tester) async {
      final fakeService = FakeFirestoreService();
      fakeService.tickets = [
        _ticket(id: 'a', parentId: 'parent-1', subject: '[Beta] Bug A'),
        _ticket(id: 'b', parentId: 'parent-1', subject: '[Beta] Bug A'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-1',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('feedback_history_top_cluster_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve Cluster (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resolve All'));
      await tester.pumpAndSettle();

      expect(fakeService.bulkResolveCallCount, 1);
      expect(fakeService.tickets.where((t) => !t.isResolved), isEmpty);
      await tester.scrollUntilVisible(
        find.text('Recent bulk actions'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recent bulk actions'), findsOneWidget);
      expect(find.textContaining('resolved 2'), findsOneWidget);
    });

    testWidgets('undo latest button appears after a bulk resolve',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeService = FakeFirestoreService();
      fakeService.tickets = [
        _ticket(id: 'a', parentId: 'parent-1', subject: '[Beta] Bug A'),
        _ticket(id: 'b', parentId: 'parent-1', subject: '[Beta] Bug A'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-1',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('feedback_history_top_cluster_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve Cluster (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve All'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_undo_bulk_resolve_button')),
        240,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.byKey(const Key('feedback_history_undo_bulk_resolve_button')),
        findsOneWidget,
      );
      expect(fakeService.bulkReopenCallCount, 0);
    });

    testWidgets('activity entry tap refocuses duplicate cluster filters',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeService = FakeFirestoreService();
      fakeService.tickets = [
        _ticket(id: 'a', parentId: 'parent-1', subject: '[Beta] Bug A'),
        _ticket(id: 'b', parentId: 'parent-1', subject: '[Beta] Bug A'),
        _ticket(
            id: 'c', parentId: 'parent-1', subject: '[Beta] Different issue'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-1',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('feedback_history_top_cluster_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve Cluster (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve All'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_activity_entry_0')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      final activityEntryFinder =
          find.byKey(const Key('feedback_history_activity_entry_0'));
      await tester.ensureVisible(activityEntryFinder);
      await tester.tap(activityEntryFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Showing 2 of 3 tickets'), findsOneWidget);
      expect(find.byKey(const Key('feedback_history_ticket_c')), findsNothing);
    });

    testWidgets('focus latest button reapplies duplicate cluster focus',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeService = FakeFirestoreService();
      fakeService.tickets = [
        _ticket(id: 'a', parentId: 'parent-1', subject: '[Beta] Bug A'),
        _ticket(id: 'b', parentId: 'parent-1', subject: '[Beta] Bug A'),
        _ticket(
            id: 'c', parentId: 'parent-1', subject: '[Beta] Different issue'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-1',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('feedback_history_top_cluster_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve Cluster (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve All'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_focus_latest_activity_button')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      final focusLatestFinder = find
          .byKey(const Key('feedback_history_focus_latest_activity_button'));
      await tester.ensureVisible(focusLatestFinder);
      await tester.tap(focusLatestFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Showing 2 of 3 tickets'), findsOneWidget);
      expect(find.byKey(const Key('feedback_history_ticket_c')), findsNothing);
    });

    testWidgets('hide resolved toggle filters out resolved tickets',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeService = FakeFirestoreService();
      fakeService.tickets = [
        _ticket(
          id: 'a',
          parentId: 'parent-1',
          subject: '[Beta] Pending',
          status: SupportTicketStatus.open,
        ),
        _ticket(
          id: 'b',
          parentId: 'parent-1',
          subject: '[Beta] Resolved',
          status: SupportTicketStatus.resolved,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackHistoryScreen(
            parentIdOverride: 'parent-1',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_a')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
          find.byKey(const Key('feedback_history_ticket_a')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_b')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
          find.byKey(const Key('feedback_history_ticket_b')), findsOneWidget);

      await tester
          .tap(find.byKey(const Key('feedback_history_hide_resolved_switch')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback_history_ticket_a')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
          find.byKey(const Key('feedback_history_ticket_a')), findsOneWidget);
      expect(find.byKey(const Key('feedback_history_ticket_b')), findsNothing);
    });
  });
}

SupportTicket _ticket({
  required String id,
  required String parentId,
  required String subject,
  SupportTicketStatus status = SupportTicketStatus.open,
}) {
  final now = DateTime(2026, 2, 19, 10, 0);
  return SupportTicket(
    id: id,
    parentId: parentId,
    subject: subject,
    message: 'Issue',
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

class FakeFirestoreService extends FirestoreService {
  FakeFirestoreService() : super(firestore: FakeFirebaseFirestore());

  List<SupportTicket> tickets = [];
  int bulkResolveCallCount = 0;
  int bulkReopenCallCount = 0;

  @override
  Stream<List<SupportTicket>> getSupportTicketsStream(
    String parentId, {
    int limit = 50,
  }) {
    final filtered = tickets
        .where((t) => t.parentId == parentId)
        .take(limit)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(filtered);
  }

  @override
  Future<int> bulkResolveDuplicates({
    required String parentId,
    required String duplicateKey,
  }) async {
    bulkResolveCallCount++;
    var count = 0;

    tickets = tickets.map((ticket) {
      if (ticket.parentId == parentId &&
          ticket.duplicateKey == duplicateKey &&
          !ticket.isResolved) {
        count += 1;
        return SupportTicket(
          id: ticket.id,
          parentId: ticket.parentId,
          subject: ticket.subject,
          message: ticket.message,
          childId: ticket.childId,
          status: SupportTicketStatus.resolved,
          createdAt: ticket.createdAt,
          updatedAt: DateTime(2026, 2, 19, 11, 0),
        );
      }
      return ticket;
    }).toList();

    return count;
  }

  @override
  Future<int> bulkReopenDuplicates({
    required String parentId,
    required String duplicateKey,
    int limit = 50,
  }) async {
    bulkReopenCallCount++;
    var reopened = 0;

    tickets = tickets.map((ticket) {
      if (ticket.parentId == parentId &&
          ticket.duplicateKey == duplicateKey &&
          ticket.isResolved &&
          reopened < limit) {
        reopened += 1;
        return SupportTicket(
          id: ticket.id,
          parentId: ticket.parentId,
          subject: ticket.subject,
          message: ticket.message,
          childId: ticket.childId,
          status: SupportTicketStatus.open,
          createdAt: ticket.createdAt,
          updatedAt: DateTime(2026, 2, 19, 12, 0),
        );
      }
      return ticket;
    }).toList();

    return reopened;
  }

  @override
  Future<int> getDuplicateClusterSize({
    required String parentId,
    required String duplicateKey,
  }) async {
    return tickets
        .where(
          (t) =>
              t.parentId == parentId &&
              t.duplicateKey == duplicateKey &&
              !t.isResolved,
        )
        .length;
  }
}
