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
        'preferences': {
          'biometricLoginEnabled': false,
          'incognitoModeEnabled': false,
        },
      });
    }

    testWidgets('renders security controls content', (tester) async {
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

      expect(find.text('Security Controls'), findsOneWidget);
      expect(find.text('Protect Your Account'), findsOneWidget);
      expect(
          find.byKey(const Key('security_biometric_switch')), findsOneWidget);
      expect(
          find.byKey(const Key('security_incognito_switch')), findsOneWidget);
    });

    testWidgets('saves biometric toggle to firestore', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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

      expect(find.text('SAVE'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'SAVE'));
      await tester.pumpAndSettle();

      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;
      expect(preferences['biometricLoginEnabled'], true);
    });
  });
}
