import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashlyticsService {
  CrashlyticsService._();

  static final CrashlyticsService _instance = CrashlyticsService._();

  factory CrashlyticsService() {
    return _instance;
  }

  FirebaseCrashlytics get _crashlytics => FirebaseCrashlytics.instance;

  Future<void> setUserId(String userId) async {
    if (kDebugMode) {
      return;
    }
    await _crashlytics.setUserIdentifier(userId);
  }

  Future<void> clearUserId() async {
    if (kDebugMode) {
      return;
    }
    await _crashlytics.setUserIdentifier('');
  }

  Future<void> setCustomKey(String key, dynamic value) async {
    if (kDebugMode) {
      return;
    }
    await _crashlytics.setCustomKey(key, value);
  }

  Future<void> setCustomKeys(Map<String, dynamic> keys) async {
    if (kDebugMode) {
      return;
    }
    for (final entry in keys.entries) {
      await _crashlytics.setCustomKey(entry.key, entry.value);
    }
  }

  Future<void> log(String message) async {
    if (kDebugMode) {
      debugPrint('[Crashlytics] $message');
      return;
    }
    await _crashlytics.log(message);
  }

  Future<void> logError(
    Object error,
    StackTrace stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    if (kDebugMode) {
      debugPrint('[Crashlytics] Error: $error');
      return;
    }
    await _crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }

  void testCrash() {
    if (!kDebugMode) {
      throw StateError('Test crash is available in debug mode only.');
    }
    throw StateError('TEST CRASH from TrustBridge debug action.');
  }

  void forceCrash() {
    _crashlytics.crash();
  }
}
