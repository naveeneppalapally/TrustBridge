import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirestoreService? firestoreService,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _firestoreService = firestoreService ??
            FirestoreService(
              firestore: firestore ?? FirebaseFirestore.instance,
            );

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirestoreService _firestoreService;
  static const Duration _authRequestTimeout = Duration(seconds: 60);
  static const Duration _networkRetryDelay = Duration(seconds: 2);

  String? _verificationId;
  int? _resendToken;
  String? _lastErrorMessage;

  User? get currentUser => _auth.currentUser;
  String? get lastErrorMessage => _lastErrorMessage;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<bool> sendOTP(
    String phoneNumber, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    if (normalizedPhone == null) {
      _lastErrorMessage = 'invalid-phone-number';
      _log('OTP request rejected: invalid phone number input');
      return false;
    }
    _lastErrorMessage = null;

    Future<bool> attemptSend({required bool allowRetry}) async {
      final completer = Completer<bool>();
      final verificationIdBefore = _verificationId;

      try {
        await _auth.verifyPhoneNumber(
          phoneNumber: normalizedPhone,
          timeout: timeout,
          forceResendingToken: _resendToken,
          verificationCompleted: (PhoneAuthCredential credential) async {
            _log('Auto verification callback received');
            try {
              final userCredential =
                  await _auth.signInWithCredential(credential);
              final user = userCredential.user;
              if (user != null &&
                  (userCredential.additionalUserInfo?.isNewUser ?? false)) {
                await _ensureParentProfileSafely(user);
              }
              if (!completer.isCompleted) {
                completer.complete(true);
              }
            } catch (error, stackTrace) {
              _lastErrorMessage = _extractErrorCode(error);
              _log(
                'Auto verification sign-in failed',
                error: error,
                stackTrace: stackTrace,
              );
              if (!completer.isCompleted) {
                completer.complete(false);
              }
            }
          },
          verificationFailed: (FirebaseAuthException exception) {
            _lastErrorMessage = exception.code;
            _log(
              'Phone verification failed: ${exception.code}',
              error: exception,
              stackTrace: exception.stackTrace,
            );
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _log('OTP code sent successfully');
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            _verificationId = verificationId;
            _log('Code auto-retrieval timeout reached');
          },
        );
      } catch (error, stackTrace) {
        _lastErrorMessage = _extractErrorCode(error);
        _log(
          'Exception while sending OTP',
          error: error,
          stackTrace: stackTrace,
        );
        return false;
      }

      final success = await completer.future.timeout(
        timeout + const Duration(seconds: 5),
        onTimeout: () {
          _lastErrorMessage = 'otp-send-timeout';
          _log('OTP send flow timed out before callback completion');
          return false;
        },
      );

      if (success) {
        return true;
      }

      final codeSentDuringAttempt =
          _verificationId != null && _verificationId != verificationIdBefore;
      if (!allowRetry ||
          codeSentDuringAttempt ||
          !_isTransientNetworkErrorCode(_lastErrorMessage)) {
        return false;
      }

      _log(
        'Retrying OTP request after transient network failure '
        '(code=$_lastErrorMessage)',
      );
      await Future<void>.delayed(_networkRetryDelay);
      return attemptSend(allowRetry: false);
    }

    return attemptSend(allowRetry: true);
  }

  Future<User?> verifyOTP(String otp) async {
    final sanitizedOtp = otp.trim();
    if (_verificationId == null || sanitizedOtp.isEmpty) {
      _lastErrorMessage = 'missing-verification-state';
      _log('OTP verification skipped: missing verificationId or code');
      return null;
    }
    _lastErrorMessage = null;

    return _runAuthOperationWithRetry<User?>(
      operationName: 'OTP verification',
      action: () async {
        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: sanitizedOtp,
        );

        final userCredential = await _auth
            .signInWithCredential(credential)
            .timeout(_authRequestTimeout);
        final user = userCredential.user;

        if (user != null &&
            (userCredential.additionalUserInfo?.isNewUser ?? false)) {
          unawaited(_ensureParentProfileSafely(user));
        }

        _log('OTP verification succeeded');
        return user;
      },
    );
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Keep sign-out resilient even if Google sign-out fails.
    }
    await _auth.signOut();
    _log('User signed out');
  }

  Future<User?> signInWithGoogle() async {
    _lastErrorMessage = null;
    return _runAuthOperationWithRetry<User?>(
      operationName: 'Google sign-in',
      action: () async {
        final googleAccount = await _googleSignIn.signIn();
        if (googleAccount == null) {
          _lastErrorMessage = 'aborted-by-user';
          return null;
        }

        final googleAuth = await googleAccount.authentication;
        if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
          throw FirebaseAuthException(
            code: 'missing-id-token',
            message: 'Google sign-in did not return a valid ID token.',
          );
        }

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final userCredential = await _auth
            .signInWithCredential(credential)
            .timeout(_authRequestTimeout);
        final user = userCredential.user;
        if (user != null) {
          unawaited(_ensureParentProfileSafely(user));
        }
        _log('Google sign-in succeeded');
        return user;
      },
    );
  }

  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _lastErrorMessage = null;
    return _runAuthOperationWithRetry<User?>(
      operationName: 'Email sign-in',
      action: () async {
        final credential = await _auth
            .signInWithEmailAndPassword(
              email: email.trim(),
              password: password,
            )
            .timeout(_authRequestTimeout);
        final user = credential.user;
        if (user != null &&
            (credential.additionalUserInfo?.isNewUser ?? false)) {
          unawaited(_ensureParentProfileSafely(user));
        }
        _log('Email sign-in succeeded');
        return user;
      },
    );
  }

  Future<User?> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _lastErrorMessage = null;
    return _runAuthOperationWithRetry<User?>(
      operationName: 'Email sign-up',
      action: () async {
        final credential = await _auth
            .createUserWithEmailAndPassword(
              email: email.trim(),
              password: password,
            )
            .timeout(_authRequestTimeout);
        final user = credential.user;
        if (user != null) {
          unawaited(_ensureParentProfileSafely(user));
        }
        _log('Email sign-up succeeded');
        return user;
      },
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _lastErrorMessage = null;
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not logged in');
    }
    final email = user.email;
    if (email == null || email.trim().isEmpty) {
      throw StateError('Password change is only available for email accounts.');
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      _log('Password updated successfully');
    } catch (error, stackTrace) {
      _lastErrorMessage = _extractErrorCode(error);
      _log(
        'Password update failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _ensureParentProfile(User user) async {
    await _firestoreService.ensureParentProfile(
      parentId: user.uid,
      phoneNumber: user.phoneNumber,
    );
    _log('Parent profile ensured for ${user.uid}');
  }

  Future<void> _ensureParentProfileSafely(User user) async {
    try {
      await _ensureParentProfile(user);
    } catch (error, stackTrace) {
      _log(
        'Parent profile ensure failed; continuing authenticated session',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String? _normalizePhoneNumber(String input) {
    var normalized = input.trim();
    if (normalized.isEmpty) {
      return null;
    }

    normalized = normalized.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (normalized.startsWith('+')) {
      return normalized;
    }

    normalized = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('0')) {
      normalized = normalized.substring(1);
    }
    return '+91$normalized';
  }

  String _extractErrorCode(Object error) {
    if (error is TimeoutException) {
      return 'network-timeout';
    }
    if (error is FirebaseAuthException) {
      return error.code;
    }
    if (error is FirebaseException) {
      return error.code;
    }
    return error.toString();
  }

  bool _isTransientNetworkErrorCode(String? code) {
    if (code == null || code.isEmpty) {
      return false;
    }
    return code == 'network-request-failed' ||
        code == 'network-timeout' ||
        code == 'timeout' ||
        code == 'unknown';
  }

  Future<T?> _runAuthOperationWithRetry<T>({
    required String operationName,
    required Future<T> Function() action,
  }) async {
    Future<T?> attempt({required bool allowRetry}) async {
      try {
        return await action();
      } catch (error, stackTrace) {
        _lastErrorMessage = _extractErrorCode(error);
        final errorCode = _lastErrorMessage;

        if (allowRetry && _isTransientNetworkErrorCode(errorCode)) {
          _log(
            '$operationName transient failure; retrying (code=$errorCode)',
            error: error,
            stackTrace: stackTrace,
          );
          await Future<void>.delayed(_networkRetryDelay);
          return attempt(allowRetry: false);
        }

        _log(
          '$operationName failed',
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      }
    }

    return attempt(allowRetry: true);
  }

  void _log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: 'AuthService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
