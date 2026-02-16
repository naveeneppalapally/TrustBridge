import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirestoreService? firestoreService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestoreService = firestoreService ??
            FirestoreService(
              firestore: firestore ?? FirebaseFirestore.instance,
            );

  final FirebaseAuth _auth;
  final FirestoreService _firestoreService;

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

    final completer = Completer<bool>();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        timeout: timeout,
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          _log('Auto verification callback received');
          try {
            final userCredential = await _auth.signInWithCredential(credential);
            final user = userCredential.user;
            if (user != null &&
                (userCredential.additionalUserInfo?.isNewUser ?? false)) {
              await _ensureParentProfile(user);
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

    return completer.future.timeout(
      timeout + const Duration(seconds: 5),
      onTimeout: () {
        _lastErrorMessage = 'otp-send-timeout';
        _log('OTP send flow timed out before callback completion');
        return false;
      },
    );
  }

  Future<User?> verifyOTP(String otp) async {
    final sanitizedOtp = otp.trim();
    if (_verificationId == null || sanitizedOtp.isEmpty) {
      _lastErrorMessage = 'missing-verification-state';
      _log('OTP verification skipped: missing verificationId or code');
      return null;
    }
    _lastErrorMessage = null;

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: sanitizedOtp,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null &&
          (userCredential.additionalUserInfo?.isNewUser ?? false)) {
        await _ensureParentProfile(user);
      }

      _log('OTP verification succeeded');
      return user;
    } catch (error, stackTrace) {
      _lastErrorMessage = _extractErrorCode(error);
      _log(
        'OTP verification failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _log('User signed out');
  }

  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _lastErrorMessage = null;
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await _ensureParentProfile(user);
      }
      _log('Email sign-in succeeded');
      return user;
    } catch (error, stackTrace) {
      _lastErrorMessage = _extractErrorCode(error);
      _log(
        'Email sign-in failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<User?> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _lastErrorMessage = null;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await _ensureParentProfile(user);
      }
      _log('Email sign-up succeeded');
      return user;
    } catch (error, stackTrace) {
      _lastErrorMessage = _extractErrorCode(error);
      _log(
        'Email sign-up failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
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
    // Ensure a fresh auth token is available before Firestore write.
    await user.getIdToken(true);
    await _firestoreService.ensureParentProfile(
      parentId: user.uid,
      phoneNumber: user.phoneNumber,
    );
    _log('Parent profile ensured for ${user.uid}');
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
    if (error is FirebaseAuthException) {
      return error.code;
    }
    if (error is FirebaseException) {
      return error.code;
    }
    return error.toString();
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
