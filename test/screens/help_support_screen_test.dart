import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/help_support_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('HelpSupportScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    testWidgets('renders support sections and FAQ', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: HelpSupportScreen(
            parentIdOverride: 'parent-help-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Get Help Quickly'), findsOneWidget);
      expect(find.text('Support Contact'), findsOneWidget);
      expect(find.text('Send Support Request'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Frequently Asked Questions'), findsOneWidget);
    });

    testWidgets('shows validation error when topic is missing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: HelpSupportScreen(
            parentIdOverride: 'parent-help-b',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('support_message_input')),
        'I need help with policy sync behavior.',
      );
      await tester
          .ensureVisible(find.byKey(const Key('support_submit_button')));
      await tester.tap(find.byKey(const Key('support_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please choose a support topic.'), findsOneWidget);
    });

    testWidgets('submits support request and writes Firestore ticket',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: HelpSupportScreen(
            parentIdOverride: 'parent-help-c',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('support_topic_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Policy Question').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('support_message_input')),
        'Policy updates are delayed in my dashboard after save.',
      );
      await tester
          .ensureVisible(find.byKey(const Key('support_submit_button')));
      await tester.tap(find.byKey(const Key('support_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Support request sent successfully'), findsOneWidget);

      final snapshot = await fakeFirestore.collection('supportTickets').get();
      expect(snapshot.docs.length, 1);
      final data = snapshot.docs.first.data();
      expect(data['parentId'], 'parent-help-c');
      expect(data['subject'], 'Policy Question');
      expect(
        data['message'],
        'Policy updates are delayed in my dashboard after save.',
      );
      expect(data['status'], 'open');
    });
  });
}
