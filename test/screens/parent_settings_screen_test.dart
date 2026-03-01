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

    Future<void> seedParent(String parentId) {
      return fakeFirestore.collection('parents').doc(parentId).set({
        'parentId': parentId,
        'displayName': 'Sarah Jenkins',
        'email': 'sarah@test.com',
        'phone': '+919999999999',
        'subscription': {
          'tier': 'free',
        },
        'preferences': {
          'biometricLoginEnabled': false,
          'incognitoModeEnabled': false,
        },
      });
    }

    testWidgets('renders redesigned settings sections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await seedParent('parent-settings-a');

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
      expect(find.byKey(const Key('settings_profile_card')), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('SUBSCRIPTION'), findsOneWidget);
      expect(find.text('SECURITY & PRIVACY'), findsOneWidget);
      expect(find.text('ABOUT'), findsOneWidget);
      expect(find.text('Family Subscription'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
    });

    testWidgets('saves biometric toggle to Firestore', (tester) async {
      const parentId = 'parent-settings-b';
      await seedParent(parentId);

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
        find.byKey(const Key('settings_biometric_login_switch')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_biometric_login_switch')));
      await tester.pumpAndSettle();

      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;
      expect(preferences['biometricLoginEnabled'], true);
    });

    testWidgets('navigates to privacy center from security section',
        (tester) async {
      await seedParent('parent-settings-c');

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSettingsScreen(
            parentIdOverride: 'parent-settings-c',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('settings_privacy_center_tile')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_privacy_center_tile')));
      await tester.pumpAndSettle();

      expect(find.text('Control Data Usage'), findsOneWidget);
    });

    testWidgets('navigates to help support from about section', (tester) async {
      await seedParent('parent-settings-d');

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSettingsScreen(
            parentIdOverride: 'parent-settings-d',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('settings_help_support_tile')),
        find.byType(ListView),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_help_support_tile')));
      await tester.pumpAndSettle();

      expect(find.text('Get Help Quickly'), findsOneWidget);
      expect(find.text('Send Support Request'), findsOneWidget);
    });

    testWidgets('navigates to family management from account section',
        (tester) async {
      await seedParent('parent-settings-family');

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSettingsScreen(
            parentIdOverride: 'parent-settings-family',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('settings_family_management_tile')),
        find.byType(ListView),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_family_management_tile')));
      await tester.pumpAndSettle();

      expect(find.text('Family Management'), findsOneWidget);
      expect(find.byKey(const Key('family_admins_card')), findsOneWidget);
    });

    testWidgets('opens premium screen from subscription tile', (tester) async {
      await seedParent('parent-settings-premium');

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSettingsScreen(
            parentIdOverride: 'parent-settings-premium',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('settings_subscription_tile')),
        find.byType(ListView),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_subscription_tile')));
      await tester.pumpAndSettle();

      expect(find.textContaining('TrustBridge'), findsOneWidget);
      expect(find.byKey(const Key('premium_header_card')), findsOneWidget);
    });

    testWidgets('navigates to feedback history from about section',
        (tester) async {
      await seedParent('parent-settings-e');

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSettingsScreen(
            parentIdOverride: 'parent-settings-e',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('settings_feedback_history_tile')),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_feedback_history_tile')));
      await tester.pumpAndSettle();

      expect(find.text('Feedback History'), findsOneWidget);
      expect(find.text('No feedback yet'), findsOneWidget);
    });
  });
}
