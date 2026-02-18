import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    testWidgets('renders parent tickets and opens detail sheet',
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

      await tester
          .tap(find.byKey(const Key('feedback_history_ticket_ticket-a')));
      await tester.pumpAndSettle();

      expect(find.text('Ticket Details'), findsOneWidget);
      expect(find.textContaining('VPN did not reconnect automatically'),
          findsAtLeastNWidgets(1));
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
      expect(find.text('[Beta][High] Crash in dashboard'), findsOneWidget);
      expect(find.text('Policy Question'), findsNothing);

      await tester.tap(find.byKey(const Key('feedback_history_source_all')));
      await tester.pumpAndSettle();
      expect(find.text('Policy Question'), findsOneWidget);

      await tester
          .tap(find.byKey(const Key('feedback_history_status_resolved')));
      await tester.pumpAndSettle();
      expect(find.text('[Beta][High] Crash in dashboard'), findsNothing);
      expect(find.text('Policy Question'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('feedback_history_search_input')),
        'policy',
      );
      await tester.pumpAndSettle();
      expect(find.text('Policy Question'), findsOneWidget);
      expect(find.text('[Beta][Low] Minor spacing issue'), findsNothing);
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
      final criticalY = tester
          .getTopLeft(
              find.byKey(const Key('feedback_history_ticket_ticket-critical')))
          .dy;
      final highY = tester
          .getTopLeft(
              find.byKey(const Key('feedback_history_ticket_ticket-high')))
          .dy;
      expect(criticalY, lessThan(highY));

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
}
