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
  });
}
