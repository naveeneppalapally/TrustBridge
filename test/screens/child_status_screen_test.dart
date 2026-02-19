import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_status_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('ChildStatusScreen', () {
    late ChildProfile testChild;
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Aarav',
        ageBand: AgeBand.young,
      );
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    testWidgets('renders greeting with child nickname', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Aarav'), findsOneWidget);
    });

    testWidgets('renders circular timer hero and blocked section',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('child_status_timer_ring')), findsOneWidget);
      expect(find.byKey(const Key('child_status_blocked_section')),
          findsOneWidget);
      expect(find.text("What's blocked?"), findsOneWidget);
    });

    testWidgets('shows Ask for Access button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      await tester.dragUntilVisible(
        find.byKey(const Key('child_status_request_access_button')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('child_status_request_access_button')),
        findsOneWidget,
      );
    });

    testWidgets('uses non-punitive wording', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.textContaining('BLOCKED'), findsNothing);
      expect(find.textContaining('DENIED'), findsNothing);
      expect(find.textContaining('FORBIDDEN'), findsNothing);
    });

    testWidgets('tap Ask for Access navigates to request screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      final askForAccessFinder =
          find.byKey(const Key('child_status_request_access_button'));
      await tester.dragUntilVisible(
        askForAccessFinder,
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pump();
      await tester.ensureVisible(askForAccessFinder);
      final requestButton = tester.widget<ElevatedButton>(askForAccessFinder);
      requestButton.onPressed!.call();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Which app?'), findsOneWidget);
    });

    testWidgets('shows active approved access card when request is approved',
        (tester) async {
      await fakeFirestore
          .collection('parents')
          .doc('parent-a')
          .collection('access_requests')
          .doc('request-1')
          .set({
        'childId': testChild.id,
        'parentId': 'parent-a',
        'childNickname': testChild.nickname,
        'appOrSite': 'youtube.com',
        'durationLabel': '30 min',
        'durationMinutes': 30,
        'reason': 'Need this for class',
        'status': 'approved',
        'parentReply': 'Use it for your project.',
        'requestedAt': Timestamp.fromDate(DateTime.now()),
        'respondedAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 1))),
        'expiresAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 20))),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(
            child: testChild,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-a',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.dragUntilVisible(
        find.byKey(const Key('child_status_active_access_card')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pump();

      expect(find.byKey(const Key('child_status_active_access_card')),
          findsOneWidget);
      expect(find.text('Access available now'), findsOneWidget);
      expect(find.text('youtube.com'), findsOneWidget);
      expect(find.textContaining('Ends in'), findsOneWidget);
    });
  });
}
