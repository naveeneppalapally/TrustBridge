import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/screens/family_management_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('FamilyManagementScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    Future<void> seedData() async {
      await fakeFirestore.collection('parents').doc('parent-family').set({
        'displayName': 'Sarah Jenkins',
        'email': 'sarah@test.com',
      });

      await fakeFirestore.collection('children').doc('child-a').set({
        'parentId': 'parent-family',
        'nickname': 'Leo',
        'ageBand': AgeBand.young.value,
        'deviceIds': ['Pixel 7 Pro'],
        'policy': Policy.presetForAgeBand(AgeBand.young).toMap(),
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
    }

    testWidgets('renders subscription admins and children sections',
        (tester) async {
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: FamilyManagementScreen(
            parentIdOverride: 'parent-family',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Family Management'), findsOneWidget);
      expect(find.byKey(const Key('family_subscription_card')), findsOneWidget);
      expect(find.text('Premium Family'), findsOneWidget);
      expect(find.byKey(const Key('family_admins_card')), findsOneWidget);
      expect(find.byKey(const Key('family_children_card')), findsOneWidget);
      expect(find.text('Leo'), findsOneWidget);
      expect(find.text('child-a'), findsNothing);
    });

    testWidgets('shows leave family group button', (tester) async {
      await seedData();

      await tester.pumpWidget(
        MaterialApp(
          home: FamilyManagementScreen(
            parentIdOverride: 'parent-family',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('family_leave_group_button')),
        find.byType(ListView),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('family_leave_group_button')), findsOneWidget);
    });
  });
}
