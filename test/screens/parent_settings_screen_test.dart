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
          'activityHistoryEnabled': true,
          'crashReportsEnabled': true,
          'personalizedTipsEnabled': true,
          'biometricLoginEnabled': false,
          'incognitoModeEnabled': false,
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

      await tester.dragUntilVisible(
        find.text('SUPPORT'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('SECURITY & PRIVACY'), findsOneWidget);
      expect(find.text('SUPPORT'), findsOneWidget);
      expect(find.text('Help & Support'), findsOneWidget);
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
          'activityHistoryEnabled': true,
          'crashReportsEnabled': true,
          'personalizedTipsEnabled': true,
          'biometricLoginEnabled': false,
          'incognitoModeEnabled': false,
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

    testWidgets('navigates to privacy center from security card',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const parentId = 'parent-settings-c';
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

      await tester.tap(find.text('Privacy Center'));
      await tester.pumpAndSettle();

      expect(find.text('Control Data Usage'), findsOneWidget);
    });

    testWidgets('navigates to help support screen from support card',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const parentId = 'parent-settings-d';
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
      await tester.dragUntilVisible(
        find.text('Help & Support'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Help & Support'));
      await tester.pumpAndSettle();

      expect(find.text('Get Help Quickly'), findsOneWidget);
      expect(find.text('Send Support Request'), findsOneWidget);
    });

    testWidgets('shows access request alerts permission card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const parentId = 'parent-settings-e';
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

      expect(find.text('Access request alerts'), findsOneWidget);
      expect(
        find.byKey(const Key('settings_request_alert_permission_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_send_test_notification_button')),
        findsOneWidget,
      );
    });
  });
}
