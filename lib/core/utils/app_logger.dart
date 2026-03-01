import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';

/// Provides consistent app logging for debug and release builds.
abstract final class AppLogger {
  static final CrashlyticsService _crashlyticsService = CrashlyticsService();

  /// Writes a non-fatal diagnostic message.
  static void debug(
    String message, {
    String tag = 'TrustBridge',
  }) {
    developer.log(message, name: tag);
    if (kDebugMode) {
      return;
    }
    unawaited(_crashlyticsService.log('[$tag] $message'));
  }

  /// Writes an error and forwards it to crash reporting in release builds.
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String tag = 'TrustBridge',
    bool fatal = false,
  }) {
    developer.log(
      message,
      name: tag,
      error: error,
      stackTrace: stackTrace,
    );
    if (kDebugMode) {
      return;
    }
    if (error != null) {
      unawaited(
        _crashlyticsService.logError(
          error,
          stackTrace ?? StackTrace.current,
          reason: '[$tag] $message',
          fatal: fatal,
        ),
      );
      return;
    }
    unawaited(_crashlyticsService.log('[$tag] $message'));
  }
}
