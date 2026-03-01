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

      final payload = <String, dynamic>{
        'totalScreenTimeMs': report.totalScreenTime.inMilliseconds,
        'averageDailyScreenTimeMs':
            report.averageDailyScreenTime.inMilliseconds,
        'categorySlices': report.categorySlices
            .map((s) => <String, dynamic>{
                  'label': s.label,
                  'durationMs': s.duration.inMilliseconds,
                })
            .toList(),
        'dailyTrend': report.dailyTrend
            .map((p) => <String, dynamic>{
                  'label': p.label,
                  'durationMs': p.duration.inMilliseconds,
                })
            .toList(),
        'topApps': report.topApps
            .map((a) => <String, dynamic>{
                  'packageName': a.packageName,
                  'appName': a.appName,
                  'category': a.category,
                  'durationMs': a.duration.inMilliseconds,
                  'progress': a.progress,
                  if ((appIconsByPackage[a.packageName] ?? '').isNotEmpty)
                    'appIconBase64': appIconsByPackage[a.packageName],
                })
            .toList(),
        'dayKey': dayKey,
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
}

class _UsageDayBucket {
  _UsageDayBucket({required this.dayKey});

  final String dayKey;
  int totalMs = 0;
  Map<String, dynamic> appUsageByPackage = <String, dynamic>{};
  Map<String, int> categoryTotals = <String, int>{};
}
