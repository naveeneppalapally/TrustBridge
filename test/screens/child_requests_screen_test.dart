import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_requests_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('ChildRequestsScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;
    late ChildProfile child;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
      child = ChildProfile.create(
        nickname: 'Aarav',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('shows empty state when child has no requests', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestsScreen(
            child: child,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-a',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Request Updates'), findsOneWidget);
      expect(
          find.byKey(const Key('child_requests_empty_state')), findsOneWidget);
    });

    testWidgets('renders request details and parent reply', (tester) async {
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        childId: child.id,
        requestId: 'request-1',
        appOrSite: 'youtube.com',
        status: 'approved',
        reason: 'Need this for class',
        parentReply: 'Okay for learning.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestsScreen(
            child: child,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-a',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('youtube.com'), findsOneWidget);
      expect(
          find.textContaining('Reason: Need this for class'), findsOneWidget);
      expect(find.textContaining('Message from parent: Okay for learning.'),
          findsOneWidget);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('pending filter hides responded requests', (tester) async {
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        childId: child.id,
        requestId: 'request-2',
        appOrSite: 'minecraft.net',
        status: 'pending',
      );
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        childId: child.id,
        requestId: 'request-3',
        appOrSite: 'reddit.com',
        status: 'approved',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestsScreen(
            child: child,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-a',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('minecraft.net'), findsOneWidget);
      expect(find.text('reddit.com'), findsOneWidget);

      await tester.tap(find.byKey(const Key('child_requests_filter_pending')));
      await tester.pumpAndSettle();

      expect(find.text('minecraft.net'), findsOneWidget);
      expect(find.text('reddit.com'), findsNothing);
    });

    testWidgets('responded filter shows approved or denied requests',
        (tester) async {
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        childId: child.id,
        requestId: 'request-4',
        appOrSite: 'example.com',
        status: 'pending',
      );
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        childId: child.id,
        requestId: 'request-5',
        appOrSite: 'khanacademy.org',
        status: 'denied',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestsScreen(
            child: child,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-a',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('child_requests_filter_responded')));
      await tester.pumpAndSettle();

      expect(find.text('khanacademy.org'), findsOneWidget);
      expect(find.text('example.com'), findsNothing);
    });

    testWidgets('approved request with past expiresAt renders as expired',
        (tester) async {
      await _seedRequest(
        firestore: fakeFirestore,
        parentId: 'parent-a',
        childId: child.id,
        requestId: 'request-expired-soft',
        appOrSite: 'youtube.com',
        status: 'approved',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestsScreen(
            child: child,
            firestoreService: firestoreService,
            parentIdOverride: 'parent-a',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Expired'), findsOneWidget);
      expect(find.text('This access window has ended.'), findsOneWidget);
    });
  });
}

Future<void> _seedRequest({
  required FakeFirebaseFirestore firestore,
  required String parentId,
  required String childId,
  required String requestId,
  required String appOrSite,
  required String status,
  DateTime? expiresAt,
  String? reason,
  String? parentReply,
}) {
  return firestore
      .collection('parents')
      .doc(parentId)
      .collection('access_requests')
      .doc(requestId)
      .set({
    'childId': childId,
    'parentId': parentId,
    'childNickname': 'Aarav',
    'appOrSite': appOrSite,
    'durationLabel': '30 min',
    'durationMinutes': 30,
    'reason': reason,
    'status': status,
    'parentReply': parentReply,
    'requestedAt': Timestamp.fromDate(DateTime(2026, 2, 17, 21, 0)),
    'respondedAt': status == 'pending'
        ? null
        : Timestamp.fromDate(DateTime(2026, 2, 17, 21, 8)),
    'expiresAt': status == 'approved'
        ? Timestamp.fromDate(
            expiresAt ?? DateTime.now().add(const Duration(minutes: 30)),
          )
        : null,
  });
}
