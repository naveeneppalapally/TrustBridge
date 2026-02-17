import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/beta_feedback_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('BetaFeedbackScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    testWidgets('renders beta feedback form', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackScreen(
            parentIdOverride: 'parent-beta-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Beta Feedback'), findsOneWidget);
      expect(find.text('Help shape TrustBridge Beta'), findsOneWidget);
      expect(find.byKey(const Key('beta_feedback_category_dropdown')),
          findsOneWidget);
      expect(
          find.byKey(const Key('beta_feedback_title_input')), findsOneWidget);
      expect(
          find.byKey(const Key('beta_feedback_details_input')), findsOneWidget);
    });

    testWidgets('shows validation when category is missing',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackScreen(
            parentIdOverride: 'parent-beta-b',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('beta_feedback_title_input')),
        'App lock opens twice',
      );
      await tester.enterText(
        find.byKey(const Key('beta_feedback_details_input')),
        'When opening parent settings quickly after dashboard load, '
        'the PIN dialog appears twice in a row.',
      );
      await tester.tap(find.byKey(const Key('beta_feedback_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please choose a feedback category.'), findsOneWidget);
    });

    testWidgets('submits beta feedback into supportTickets',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await fakeFirestore.collection('children').doc('child-beta-1').set({
        'nickname': 'Aarav',
        'ageBand': '10-13',
        'deviceIds': <String>[],
        'policy': {
          'blockedCategories': <String>[],
          'blockedDomains': <String>[],
          'safeSearchEnabled': true,
          'schedules': <Map<String, dynamic>>[],
          'quickMode': null,
        },
        'createdAt': DateTime(2026, 2, 17, 10, 0, 0),
        'updatedAt': DateTime(2026, 2, 17, 10, 0, 0),
        'parentId': 'parent-beta-c',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BetaFeedbackScreen(
            parentIdOverride: 'parent-beta-c',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('beta_feedback_category_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bug Report').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('beta_feedback_title_input')),
        'Schedule missed bedtime switch',
      );
      await tester.enterText(
        find.byKey(const Key('beta_feedback_details_input')),
        'Bedtime schedule at 9:00 PM did not activate until I opened the app. '
        'This happened on Pixel 7 during wifi.',
      );
      await tester.tap(find.byKey(const Key('beta_feedback_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Feedback submitted. Thank you!'), findsOneWidget);

      final snapshot = await fakeFirestore.collection('supportTickets').get();
      expect(snapshot.docs.length, 1);

      final ticket = snapshot.docs.first.data();
      expect(ticket['parentId'], 'parent-beta-c');
      expect((ticket['subject'] as String).startsWith('[Beta]['), isTrue);
      expect(ticket['message'], contains('Category: Bug Report'));
      expect(ticket['message'], contains('Severity: Medium'));
      expect(ticket['status'], 'open');
    });
  });
}
