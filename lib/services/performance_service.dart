import 'dart:async';

import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared thresholds used for custom trace alerting.
class PerformanceThresholds {
  const PerformanceThresholds._();

  static const int vpnStartWarningMs = 3000;
  static const int vpnStopWarningMs = 2000;
  static const int policySyncWarningMs = 2500;
  static const int firestoreGetChildrenWarningMs = 900;
  static const int dashboardLoadWarningMs = 1500;
  static const int vpnTelemetryFetchWarningMs = 1000;
  static const int dnsBlockRateHighPct = 80;
}

abstract class PerformanceTrace {
  String get name;

  Future<void> stop();

  Future<void> setMetric(String name, int value);

  Future<void> incrementMetric(String name, int by);

  Future<void> setAttribute(String name, String value);
}

class _NoopPerformanceTrace implements PerformanceTrace {
  const _NoopPerformanceTrace(this.name);

  @override
  final String name;

  @override
  Future<void> stop() async {}

  @override
  Future<void> setMetric(String name, int value) async {}

  @override
  Future<void> incrementMetric(String name, int by) async {}

  @override
  Future<void> setAttribute(String name, String value) async {}
}

class _FirebasePerformanceTrace implements PerformanceTrace {
  _FirebasePerformanceTrace({
    required this.name,
    required Trace trace,
  }) : _trace = trace;

  @override
  final String name;

  final Trace _trace;

  @override
  Future<void> stop() {
    return _trace.stop();
  }

  @override
  Future<void> setMetric(String name, int value) {
    _trace.setMetric(name, value);
    return Future<void>.value();
  }

  @override
  Future<void> incrementMetric(String name, int by) {
    _trace.incrementMetric(name, by);
    return Future<void>.value();
  }

  @override
  Future<void> setAttribute(String name, String value) {
    _trace.putAttribute(name, value);
    return Future<void>.value();
  }
}

class PerformanceService {
  PerformanceService._();

  static final PerformanceService _instance = PerformanceService._();

  factory PerformanceService() {
    return _instance;
  }

  FirebasePerformance? _performance;

  FirebasePerformance? get _performanceInstance {
    if (kDebugMode) {
      return null;
    }
    _performance ??= FirebasePerformance.instance;
    return _performance;
  }

  /// Start a trace. In debug/tests this returns a no-op trace.
  Future<PerformanceTrace> startTrace(String name) async {
    if (kDebugMode) {
      debugPrint('[Performance] startTrace($name)');
      return _NoopPerformanceTrace(name);
    }

    try {
      final performance = _performanceInstance;
      if (performance == null) {
        return _NoopPerformanceTrace(name);
      }
      final trace = performance.newTrace(name);
      await trace.start();
      return _FirebasePerformanceTrace(name: name, trace: trace);
    } on MissingPluginException catch (error) {
      debugPrint('[Performance] plugin missing for trace "$name": $error');
      return _NoopPerformanceTrace(name);
    } catch (error) {
      debugPrint('[Performance] unable to start trace "$name": $error');
      return _NoopPerformanceTrace(name);
    }
  }

  Future<void> stopTrace(PerformanceTrace trace) {
    return trace.stop();
  }

  Future<void> setMetric(PerformanceTrace trace, String name, int value) {
    return trace.setMetric(name, value);
  }

  Future<void> incrementMetric(PerformanceTrace trace, String name, int by) {
    return trace.incrementMetric(name, by);
  }

  Future<void> setAttribute(PerformanceTrace trace, String name, String value) {
    return trace.setAttribute(name, value);
  }

  /// Annotates a warning threshold state so traces can be filtered easily.
  Future<void> annotateThreshold({
    required PerformanceTrace trace,
    required String name,
    required int actualValue,
    required int warningValue,
  }) async {
    await setMetric(trace, '${name}_value', actualValue);
    await setMetric(trace, '${name}_warning', warningValue);
    await setAttribute(
      trace,
      '${name}_state',
      actualValue > warningValue ? 'warning' : 'ok',
    );
  }

  /// Run an operation inside a trace and capture elapsed duration.
  Future<T> traceOperation<T>(
    String traceName,
    Future<T> Function() operation, {
    int? warningThresholdMs,
    String thresholdMetricName = 'duration_ms',
    FutureOr<void> Function(PerformanceTrace trace, T result)? onSuccess,
    FutureOr<void> Function(
      PerformanceTrace trace,
      Object error,
      StackTrace stackTrace,
    )? onError,
  }) async {
    final trace = await startTrace(traceName);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await operation();
      stopwatch.stop();
      await setMetric(trace, 'duration_ms', stopwatch.elapsedMilliseconds);
      if (warningThresholdMs != null) {
        await annotateThreshold(
          trace: trace,
          name: thresholdMetricName,
          actualValue: stopwatch.elapsedMilliseconds,
          warningValue: warningThresholdMs,
        );
      }
      if (onSuccess != null) {
        await onSuccess(trace, result);
      }
      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      await setMetric(trace, 'duration_ms', stopwatch.elapsedMilliseconds);
      if (warningThresholdMs != null) {
        await annotateThreshold(
          trace: trace,
          name: thresholdMetricName,
          actualValue: stopwatch.elapsedMilliseconds,
          warningValue: warningThresholdMs,
        );
      }
      if (onError != null) {
        await onError(trace, error, stackTrace);
      }
      rethrow;
    } finally {
      await stopTrace(trace);
    }
  }

  /// Create an HTTP metric for manual instrumentation when needed.
  HttpMetric? httpMetricForUrl(Uri url, HttpMethod method) {
    if (kDebugMode) {
      return null;
    }
    try {
      final performance = _performanceInstance;
      if (performance == null) {
        return null;
      }
      return performance.newHttpMetric(url.toString(), method);
    } catch (error) {
      debugPrint('[Performance] unable to create HTTP metric: $error');
      return null;
    }
  }
}
