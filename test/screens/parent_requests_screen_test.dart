import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/parent_requests_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('ParentRequestsScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    testWidgets('renders tabs and shows pending empty state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ParentRequestsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('All caught up!'), findsOneWidget);
    });

    testWidgets('history tab shows empty state when no responded requests',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ParentRequestsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('No history yet'), findsOneWidget);
    });

    testWidgets('history tab renders expired requests', (tester) async {
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        requestId: 'request-expired',
        childNickname: 'Aarav',
        appOrSite: 'youtube.com',
        durationLabel: '30 min',
        durationMinutes: 30,
        status: 'expired',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ParentRequestsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Aarav -> youtube.com'), findsOneWidget);
    });

    testWidgets('pending card shows child, app, duration, and reason',
        (tester) async {
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        requestId: 'request-1',
        childNickname: 'Aarav',
        appOrSite: 'youtube.com',
        durationLabel: '30 min',
        durationMinutes: 30,
        status: 'pending',
        reason: 'Need for science assignment',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ParentRequestsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aarav'), findsOneWidget);
      expect(find.text('youtube.com'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(
          find.textContaining('Need for science assignment'), findsOneWidget);
    });

    testWidgets('approve button opens decision modal with reply input',
        (tester) async {
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        requestId: 'request-2',
        childNickname: 'Maya',
        appOrSite: 'instagram.com',
        durationLabel: '15 min',
        durationMinutes: 15,
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ParentRequestsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('request_approve_button_request-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('request_decision_dialog_request-2')),
          findsOneWidget);
      expect(find.text('Approve request?'), findsOneWidget);
      expect(find.byKey(const Key('request_modal_reply_input_request-2')),
          findsOneWidget);

      await tester.tap(find.text('Keep Pending'));
      await tester.pumpAndSettle();

      final snapshot = await fakeFirestore
          .collection('parents')
          .doc('parent-a')
          .collection('access_requests')
          .doc('request-2')
          .get();
      expect(snapshot.data()!['status'], 'pending');
    });

    testWidgets('approve action updates status and moves request to history',
        (tester) async {
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        requestId: 'request-3',
        childNickname: 'Leo',
        appOrSite: 'reddit.com',
        durationLabel: '1 hour',
        durationMinutes: 60,
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ParentRequestsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('request_approve_button_request-3')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('request_modal_reply_input_request-3')),
        'Approved for homework',
      );
      await tester
          .tap(find.byKey(const Key('request_confirm_approve_button_request-3')));
      await tester.pumpAndSettle();

      final snapshot = await fakeFirestore
          .collection('parents')
          .doc('parent-a')
          .collection('access_requests')
          .doc('request-3')
          .get();
      expect(snapshot.data()!['status'], 'approved');
      expect(snapshot.data()!['respondedAt'], isA<Timestamp>());
      expect(snapshot.data()!['expiresAt'], isA<Timestamp>());
      expect(snapshot.data()!['parentReply'], 'Approved for homework');

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Leo -> reddit.com'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
    });
  });
}

Future<void> _seedRequest({
  required FakeFirebaseFirestore firestore,
  required String parentId,
  required String requestId,
  required String childNickname,
  required String appOrSite,
  required String durationLabel,
  required int? durationMinutes,
  required String status,
  String? reason,
}) {
  return firestore
      .collection('parents')
      .doc(parentId)
      .collection('access_requests')
      .doc(requestId)
      .set({
    'childId': 'child-$requestId',
    'parentId': parentId,
    'childNickname': childNickname,
    'appOrSite': appOrSite,
    'durationLabel': durationLabel,
    'durationMinutes': durationMinutes,
    'reason': reason,
    'status': status,
    'parentReply': null,
    'requestedAt': Timestamp.fromDate(DateTime(2026, 2, 17, 20, 0)),
    'respondedAt': null,
    'expiresAt': null,
  });
}
