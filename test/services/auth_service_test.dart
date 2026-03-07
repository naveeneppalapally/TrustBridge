import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

class _MockFirestoreService extends Mock implements FirestoreService {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
  });

  test('signInWithGoogle retries transient platform network errors', () async {
    final mockAuth = _MockFirebaseAuth();
    final mockGoogleSignIn = _MockGoogleSignIn();
    final mockGoogleAccount = _MockGoogleSignInAccount();
    final mockGoogleAuth = _MockGoogleSignInAuthentication();
    final mockUserCredential = _MockUserCredential();
    final mockUser = _MockUser();
    final mockFirestoreService = _MockFirestoreService();

    var attempts = 0;
    when(() => mockGoogleSignIn.signIn()).thenAnswer((_) async {
      if (attempts++ == 0) {
        throw PlatformException(
          code: 'network_error',
          message: 'com.google.android.gms.common.api.ApiException: 7: null',
        );
      }
      return mockGoogleAccount;
    });
    when(() => mockGoogleAccount.authentication)
        .thenAnswer((_) async => mockGoogleAuth);
    when(() => mockGoogleAuth.idToken).thenReturn('id-token');
    when(() => mockGoogleAuth.accessToken).thenReturn('access-token');
    when(() => mockAuth.signInWithCredential(any()))
        .thenAnswer((_) async => mockUserCredential);
    when(() => mockUserCredential.user).thenReturn(mockUser);
    when(() => mockUser.uid).thenReturn('parent-google');
    when(() => mockUser.phoneNumber).thenReturn(null);
    when(
      () => mockFirestoreService.ensureParentProfile(
        parentId: any(named: 'parentId'),
        phoneNumber: any(named: 'phoneNumber'),
      ),
    ).thenAnswer((_) async {});

    final service = AuthService(
      auth: mockAuth,
      googleSignIn: mockGoogleSignIn,
      firestoreService: mockFirestoreService,
    );

    final user = await service.signInWithGoogle();
    await Future<void>.delayed(Duration.zero);

    expect(user, same(mockUser));
    expect(service.lastErrorMessage, isNull);
    verify(() => mockGoogleSignIn.signIn()).called(2);
    verify(() => mockAuth.signInWithCredential(any())).called(1);
    verify(
      () => mockFirestoreService.ensureParentProfile(
        parentId: 'parent-google',
        phoneNumber: null,
      ),
    ).called(1);
  });
}
