import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/parent_settings_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('ParentSettingsScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    Future<void> seedParent({
      required String parentId,
      required Map<String, dynamic> preferences,
    }) {
      return fakeFirestore.collection('parents').doc(parentId).set({
        'parentId': parentId,
        'email': 'parent@test.com',
        'phone': '+919999999999',
        'preferences': preferences,
      });
    }

    testWidgets('renders settings sections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await seedParent(
        parentId: 'parent-settings-a',
        preferences: {
          'language': 'en',
          'timezone': 'Asia/Kolkata',
          'pushNotificationsEnabled': true,
          'weeklySummaryEnabled': true,
          'securityAlertsEnabled': true,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSettingsScreen(
            parentIdOverride: 'parent-settings-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Account & Preferences'), findsOneWidget);
      expect(find.text('PREFERENCES'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('SECURITY & PRIVACY'), findsOneWidget);
    });

    testWidgets('saves toggled notification preference to Firestore',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const parentId = 'parent-settings-b';
      await seedParent(
        parentId: parentId,
        preferences: {
          'language': 'en',
          'timezone': 'Asia/Kolkata',
          'pushNotificationsEnabled': true,
          'weeklySummaryEnabled': true,
          'securityAlertsEnabled': true,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSettingsScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_push_notifications_switch')));
      await tester.pumpAndSettle();

      expect(find.text('SAVE'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'SAVE'));
      await tester.pumpAndSettle();

      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;

      expect(preferences['pushNotificationsEnabled'], false);
    });
  });
}
