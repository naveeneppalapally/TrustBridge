import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/security_controls_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('SecurityControlsScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    Future<void> seedParent(String parentId) {
      return fakeFirestore.collection('parents').doc(parentId).set({
        'parentId': parentId,
        'email': 'parent@test.com',
        'preferences': {
          'biometricLoginEnabled': false,
          'incognitoModeEnabled': false,
        },
        'security': {
          'activeSessions': 2,
          'twoFactorEnabled': false,
        },
      });
    }

    testWidgets('renders redesigned security controls layout', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await seedParent('parent-security-a');

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityControlsScreen(
            parentIdOverride: 'parent-security-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Security'), findsWidgets);
      expect(find.text('Lock Your TrustBridge App'), findsOneWidget);
      expect(find.text('Security Options'), findsOneWidget);
      expect(find.text('Use Fingerprint or Face to Open'), findsOneWidget);
      expect(find.text('Devices That Opened TrustBridge'), findsOneWidget);
      expect(find.text('2-Step Login Protection'), findsOneWidget);
      expect(
          find.byKey(const Key('security_biometric_switch')), findsOneWidget);
      expect(
          find.byKey(const Key('security_login_history_tile')), findsOneWidget);
      expect(find.byKey(const Key('security_two_factor_tile')), findsOneWidget);
      expect(
        find.byKey(const Key('security_encryption_info_card')),
        findsOneWidget,
      );
    });

    testWidgets('biometric toggle persists to Firestore preferences',
        (tester) async {
      const parentId = 'parent-security-b';
      await seedParent(parentId);

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityControlsScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('security_biometric_switch')));
      await tester.pumpAndSettle();

      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;
      expect(preferences['biometricLoginEnabled'], true);
    });

    testWidgets('change password opens change password screen', (tester) async {
      const parentId = 'parent-security-c';
      await seedParent(parentId);

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityControlsScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('security_change_password_tile')));
      await tester.pumpAndSettle();

      expect(find.text('Update Account Password'), findsOneWidget);
      expect(find.byKey(const Key('current_password_input')), findsOneWidget);
    });

    testWidgets('two-factor row toggles security metadata', (tester) async {
      const parentId = 'parent-security-d';
      await seedParent(parentId);

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityControlsScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('security_two_factor_tile')));
      await tester.pumpAndSettle();

      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final security = snapshot.data()!['security'] as Map<String, dynamic>;
      expect(security['twoFactorEnabled'], true);
    });
  });
}
