import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  static const Duration _minUploadInterval = Duration(minutes: 30);
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
      final hasPermission =
          await _appUsageService.hasUsageAccessPermission();
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
        'uploadedAt': FieldValue.serverTimestamp(),
        'deviceUploadedAtLocal': now.toIso8601String(),
      };

      await _firestore
          .collection('children')
          .doc(childId)
          .collection('usage_reports')
          .doc('latest')
          .set(payload);

      _lastUploadedAt = now;
      debugPrint('[ChildUsageUpload] Uploaded usage for child=$childId');
      return true;
    } catch (error) {
      debugPrint('[ChildUsageUpload] Upload failed: $error');
      return false;
    }
  }
}
