import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
      final usageEntries = await _appUsageService.getUsageEntries(pastDays: 2);
      final dayKey = _dateKey(now);
      final appUsageByPackage = <String, dynamic>{};
      var todayTotalMs = 0;
      for (final entry in usageEntries) {
        final packageName = entry.packageName.trim().toLowerCase();
        if (packageName.isEmpty) {
          continue;
        }
        final todayMs = entry.dailyUsageMs[dayKey] ?? 0;
        if (todayMs <= 0) {
          continue;
        }
        todayTotalMs += todayMs;
        appUsageByPackage[packageName] = <String, dynamic>{
          'appName': entry.appName.isEmpty ? packageName : entry.appName,
          'minutes': (todayMs / 60000).round(),
          'durationMs': todayMs,
          'launches': 0,
        };
      }
      final categoryTotals = <String, int>{};
      for (final slice in report.categorySlices) {
        categoryTotals[slice.label] = slice.duration.inMilliseconds;
      }

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
        final dailyPayload = <String, dynamic>{
          'capturedAt': FieldValue.serverTimestamp(),
          'dayKey': dayKey,
          'totalScreenMinutes': (todayTotalMs / 60000).round(),
          'appUsageByPackage': appUsageByPackage,
          'categoryTotals': categoryTotals,
          'trendPoint': <String, dynamic>{
            'dayKey': dayKey,
            'durationMs': todayTotalMs,
          },
          'uploadedAt': FieldValue.serverTimestamp(),
          'deviceUploadedAtLocal': now.toIso8601String(),
        };

        // Plan v2 canonical path.
        await _firestore
            .collection('children')
            .doc(childId)
            .collection('usage_reports')
            .doc('daily')
            .collection('days')
            .doc(dayKey)
            .set(dailyPayload, SetOptions(merge: true));

        // Backward-compatible flat path for existing dashboards/tests.
        await _firestore
            .collection('children')
            .doc(childId)
            .collection('usage_reports')
            .doc('daily_$dayKey')
            .set(dailyPayload, SetOptions(merge: true));
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
}
