import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/service_definitions.dart';
import '../config/rollout_flags.dart';
import 'app_usage_service.dart';

/// Uploads the child device's app‐usage summary to Firestore so that the
/// parent dashboard can display screen‐time data remotely.
///
/// The upload runs at most once per [_minUploadInterval] to avoid excessive
/// Firestore writes.  Each upload creates/overwrites a single document at
/// `children/{childId}/usage_reports/latest`.
class ChildUsageUploadService {
  ChildUsageUploadService({
    FirebaseFirestore? firestore,
    AppUsageService? appUsageService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _appUsageService = appUsageService ?? AppUsageService();

  final FirebaseFirestore _firestore;
  final AppUsageService _appUsageService;

  static const Duration _minUploadInterval = Duration(minutes: 15);
  DateTime? _lastUploadedAt;

  /// Uploads usage data if enough time has elapsed since the last upload.
  ///
  /// Returns `true` on successful upload, `false` if skipped or failed
  /// (non-throwing — errors are swallowed so callers can fire-and-forget).
  Future<bool> uploadIfNeeded({
    required String childId,
  }) async {
    final now = DateTime.now();
    if (_lastUploadedAt != null &&
        now.difference(_lastUploadedAt!) < _minUploadInterval) {
      return false; // too soon
    }

    try {
      final hasPermission = await _appUsageService.hasUsageAccessPermission();
      if (!hasPermission) {
        debugPrint(
          '[ChildUsageUpload] Usage access permission not granted — skipping.',
        );
        return false;
      }

      final report = await _appUsageService.getUsageReport(pastDays: 7);
      if (!report.hasData) {
        return false;
      }
      final usageEntries = await _appUsageService.getUsageEntries(pastDays: 7);
      final installedApps = await _appUsageService.getInstalledLaunchableApps();
      final appIconsByPackage = <String, String>{};
      for (final app in installedApps) {
        final packageName = app.packageName.trim().toLowerCase();
        final icon = app.appIconBase64?.trim() ?? '';
        if (packageName.isEmpty || icon.isEmpty) {
          continue;
        }
        appIconsByPackage[packageName] = icon;
      }
      final dayKey = _dateKey(now);
      final trackedDayKeys = List<String>.generate(
        7,
        (index) => _dateKey(now.subtract(Duration(days: index))),
      );
      final dailyBuckets = <String, _UsageDayBucket>{
        for (final key in trackedDayKeys) key: _UsageDayBucket(dayKey: key),
      };

      for (final entry in usageEntries) {
        final packageName = entry.packageName.trim().toLowerCase();
        if (packageName.isEmpty) {
          continue;
        }
        final appName = entry.appName.isEmpty ? packageName : entry.appName;
        final appCategory = _categoryFromPackage(packageName);
        final icon = appIconsByPackage[packageName];

        for (final usagePoint in entry.dailyUsageMs.entries) {
          final bucket = dailyBuckets[usagePoint.key];
          if (bucket == null) {
            continue;
          }
          final usageMs = usagePoint.value;
          if (usageMs <= 0) {
            continue;
          }
          bucket.totalMs += usageMs;
          bucket.categoryTotals[appCategory] =
              (bucket.categoryTotals[appCategory] ?? 0) + usageMs;
          final existing = bucket.appUsageByPackage[packageName];
          if (existing == null) {
            bucket.appUsageByPackage[packageName] = <String, dynamic>{
              'appName': appName,
              'minutes': (usageMs / 60000).round(),
              'durationMs': usageMs,
              'launches': 0,
              if (icon != null && icon.isNotEmpty) 'appIconBase64': icon,
            };
          } else {
            final previousMs = _toInt(existing['durationMs']);
            final mergedMs = previousMs + usageMs;
            bucket.appUsageByPackage[packageName] = <String, dynamic>{
              ...existing,
              'appName': appName,
              'minutes': (mergedMs / 60000).round(),
              'durationMs': mergedMs,
              'launches': _toInt(existing['launches']),
              if (icon != null && icon.isNotEmpty) 'appIconBase64': icon,
            };
          }
        }
      }
      final todayBucket =
          dailyBuckets[dayKey] ?? _UsageDayBucket(dayKey: dayKey);
      final appUsageByPackage = todayBucket.appUsageByPackage;
      final todayTotalMs = todayBucket.totalMs;

      final dailyTopApps = _buildTopAppsFromDailyUsage(
        appUsageByPackage: appUsageByPackage,
        appIconsByPackage: appIconsByPackage,
      );
      final dailyCategorySlices = todayBucket.categoryTotals.entries
          .map((entry) => <String, dynamic>{
                'label': entry.key,
                'durationMs': entry.value,
              })
          .toList(growable: false)
        ..sort(
          (a, b) => _toInt(b['durationMs']).compareTo(_toInt(a['durationMs'])),
        );

      final payload = <String, dynamic>{
        // "latest" should represent today's snapshot, not 7-day cumulative data.
        'totalScreenTimeMs': todayTotalMs,
        'averageDailyScreenTimeMs':
            report.averageDailyScreenTime.inMilliseconds,
        'categorySlices': dailyCategorySlices,
        'dailyTrend': report.dailyTrend
            .map((p) => <String, dynamic>{
                  'label': p.label,
                  'durationMs': p.duration.inMilliseconds,
                })
            .toList(),
        'topApps': dailyTopApps,
        'dayKey': dayKey,
        'snapshotVersion': 2,
        'uploadedAt': FieldValue.serverTimestamp(),
        'deviceUploadedAtLocal': now.toIso8601String(),
      };
      if (RolloutFlags.perAppUsageReports) {
        payload['appUsageByPackage'] = appUsageByPackage;
        payload['trendPoint'] = <String, dynamic>{
          'dayKey': dayKey,
          'durationMs': todayTotalMs,
        };
      }

      await _firestore
          .collection('children')
          .doc(childId)
          .collection('usage_reports')
          .doc('latest')
          .set(payload, SetOptions(merge: true));

      if (RolloutFlags.perAppUsageReports) {
        for (final bucket in dailyBuckets.values) {
          if (bucket.totalMs <= 0 && bucket.appUsageByPackage.isEmpty) {
            continue;
          }
          final dailyPayload = <String, dynamic>{
            'capturedAt': FieldValue.serverTimestamp(),
            'dayKey': bucket.dayKey,
            'snapshotVersion': 2,
            'totalScreenMinutes': (bucket.totalMs / 60000).round(),
            'appUsageByPackage': bucket.appUsageByPackage,
            'categoryTotals': bucket.categoryTotals,
            'trendPoint': <String, dynamic>{
              'dayKey': bucket.dayKey,
              'durationMs': bucket.totalMs,
            },
            'uploadedAt': FieldValue.serverTimestamp(),
            'deviceUploadedAtLocal': now.toIso8601String(),
          };

          // Canonical nested path.
          await _firestore
              .collection('children')
              .doc(childId)
              .collection('usage_reports')
              .doc('daily')
              .collection('days')
              .doc(bucket.dayKey)
              .set(dailyPayload, SetOptions(merge: true));

          // Backward-compatible flat path.
          await _firestore
              .collection('children')
              .doc(childId)
              .collection('usage_reports')
              .doc('daily_${bucket.dayKey}')
              .set(dailyPayload, SetOptions(merge: true));
        }
      }

      _lastUploadedAt = now;
      debugPrint('[ChildUsageUpload] Uploaded usage for child=$childId');
      return true;
    } catch (error) {
      debugPrint('[ChildUsageUpload] Upload failed: $error');
      return false;
    }
  }

  String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _categoryFromPackage(String packageName) {
    final normalized = packageName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Other';
    }
    for (final service in ServiceDefinitions.all) {
      for (final pkg in service.androidPackages) {
        if (pkg.trim().toLowerCase() == normalized) {
          return service.categoryId;
        }
      }
    }
    return 'Other';
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  List<Map<String, dynamic>> _buildTopAppsFromDailyUsage({
    required Map<String, dynamic> appUsageByPackage,
    required Map<String, String> appIconsByPackage,
  }) {
    final rows = <Map<String, dynamic>>[];
    var maxDurationMs = 0;

    for (final entry in appUsageByPackage.entries) {
      final packageName = entry.key.trim().toLowerCase();
      if (packageName.isEmpty || entry.value is! Map) {
        continue;
      }
      final appMap = (entry.value as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final durationMs = _toInt(appMap['durationMs']);
      if (durationMs <= 0) {
        continue;
      }
      if (durationMs > maxDurationMs) {
        maxDurationMs = durationMs;
      }
      final icon = (appIconsByPackage[packageName] ?? '').trim();
      rows.add(<String, dynamic>{
        'packageName': packageName,
        'appName': (appMap['appName'] as String?)?.trim().isNotEmpty == true
            ? (appMap['appName'] as String).trim()
            : packageName,
        'category': _categoryFromPackage(packageName),
        'durationMs': durationMs,
        'progress': 0.0,
        if (icon.isNotEmpty) 'appIconBase64': icon,
      });
    }

    if (rows.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    rows.sort(
      (a, b) => _toInt(b['durationMs']).compareTo(_toInt(a['durationMs'])),
    );
    final safeMax = maxDurationMs <= 0 ? 1 : maxDurationMs;
    return rows
        .take(10)
        .map((row) => <String, dynamic>{
              ...row,
              'progress': (_toInt(row['durationMs']) / safeMax)
                  .clamp(0.0, 1.0),
            })
        .toList(growable: false);
  }
}

class _UsageDayBucket {
  _UsageDayBucket({required this.dayKey});

  final String dayKey;
  int totalMs = 0;
  Map<String, dynamic> appUsageByPackage = <String, dynamic>{};
  Map<String, int> categoryTotals = <String, int>{};
}
