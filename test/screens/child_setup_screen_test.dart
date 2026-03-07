import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trustbridge_app/screens/child_setup_screen.dart';
import 'package:trustbridge_app/services/pairing_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

class _FakePairingService extends Fake implements PairingService {}

void main() {
  testWidgets(
    'child setup retries anonymous auth after transient network failure',
    (tester) async {
      final mockAuth = _MockFirebaseAuth();
      final firstError = FirebaseAuthException(code: 'network-request-failed');
      final successfulCredential = _MockUserCredential();
      final user = _MockUser();

      when(() => mockAuth.currentUser).thenReturn(null);
      when(() => mockAuth.signInAnonymously()).thenAnswer((_) async {
        throw firstError;
      });
      when(() => successfulCredential.user).thenReturn(user);

      var attempt = 0;
      when(() => mockAuth.signInAnonymously()).thenAnswer((_) async {
        if (attempt++ == 0) {
          throw firstError;
        }
        return successfulCredential;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ChildSetupScreen(
            auth: mockAuth,
            pairingService: _FakePairingService(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(
        find.text('Could not connect. Check internet and try again.'),
        findsNothing,
      );
      expect(
        find.byType(TextField),
        findsNWidgets(PairingService.pairingCodeLength),
      );
      verify(() => mockAuth.signInAnonymously()).called(2);
    },
  );
}
