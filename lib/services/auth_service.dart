import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String? _verificationId;
  int? _resendToken;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<bool> sendOTP(
    String phoneNumber, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    if (normalizedPhone == null) {
      _log('OTP request rejected: invalid phone number input');
      return false;
    }

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
              await _createParentProfile(user);
            }
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          } catch (error, stackTrace) {
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
        _log('OTP send flow timed out before callback completion');
        return false;
      },
    );
  }

  Future<User?> verifyOTP(String otp) async {
    final sanitizedOtp = otp.trim();
    if (_verificationId == null || sanitizedOtp.isEmpty) {
      _log('OTP verification skipped: missing verificationId or code');
      return null;
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: sanitizedOtp,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null && (userCredential.additionalUserInfo?.isNewUser ?? false)) {
        await _createParentProfile(user);
      }

      _log('OTP verification succeeded');
      return user;
    } catch (error, stackTrace) {
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

  Future<void> _createParentProfile(User user) async {
    final parentRef = _firestore.collection('parents').doc(user.uid);
    final existing = await parentRef.get();
    if (existing.exists) {
      _log('Parent profile already exists for ${user.uid}');
      return;
    }

    await parentRef.set({
      'parentId': user.uid,
      'phone': user.phoneNumber,
      'createdAt': FieldValue.serverTimestamp(),
      'subscription': {
        'tier': 'free',
        'validUntil': null,
      },
    });
    _log('Parent profile created for ${user.uid}');
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
