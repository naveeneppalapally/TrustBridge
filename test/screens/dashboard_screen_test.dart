import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/dashboard_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('DashboardScreen', () {
    testWidgets('shows empty state when no children', (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            parentIdOverride: 'parent-empty',
            firestoreService: firestoreService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No children yet'), findsOneWidget);
      expect(find.text('Add your first child to get started'), findsOneWidget);
    });

    testWidgets('renders child from Firestore stream', (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);

      await fakeFirestore.collection('children').doc('child-1').set({
        'parentId': 'parent-a',
        'nickname': 'Leo',
        'ageBand': '6-9',
        'deviceIds': <String>[],
        'policy': {
          'blockedCategories': <String>['social-networks'],
          'blockedDomains': <String>[],
          'schedules': <Map<String, dynamic>>[],
          'safeSearchEnabled': true,
        },
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 16, 10, 0)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 16, 10, 0)),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Leo'), findsOneWidget);
      expect(find.text('Age: 6-9'), findsOneWidget);
    });

    testWidgets('shows pending requests badge when requests exist',
        (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);

      await fakeFirestore
          .collection('parents')
          .doc('parent-badge')
          .collection('access_requests')
          .doc('req-1')
          .set({
        'childId': 'child-1',
        'parentId': 'parent-badge',
        'childNickname': 'Aarav',
        'appOrSite': 'youtube.com',
        'durationLabel': '30 min',
        'durationMinutes': 30,
        'reason': 'Project work',
        'status': 'pending',
        'parentReply': null,
        'requestedAt': Timestamp.fromDate(DateTime(2026, 2, 17, 20, 30)),
        'respondedAt': null,
        'expiresAt': null,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            parentIdOverride: 'parent-badge',
            firestoreService: firestoreService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('dashboard_requests_button')), findsOneWidget);
      expect(find.byKey(const Key('dashboard_requests_badge')), findsOneWidget);
    });
  });

  group('ChildCard', () {
    testWidgets('displays child information correctly', (tester) async {
      final child = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChildCard(
              child: child,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Child'), findsOneWidget);
      expect(find.text('Age: 6-9'), findsOneWidget);
    });
  });
}
