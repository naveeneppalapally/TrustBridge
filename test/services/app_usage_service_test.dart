import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/app_usage_service.dart';

class _FakeAppUsageService extends AppUsageService {
  _FakeAppUsageService({
    required this.permissionGranted,
    required this.entries,
  });

  final bool permissionGranted;
  final List<AppUsageEntry> entries;

  @override
  Future<bool> hasUsageAccessPermission() async => permissionGranted;

  @override
  Future<List<AppUsageEntry>> getUsageEntries({int pastDays = 7}) async {
    return entries;
  }
}

void main() {
  group('AppUsageService', () {
    test('returns permissionDenied report when usage access is not granted',
        () async {
      final service = _FakeAppUsageService(
        permissionGranted: false,
        entries: const <AppUsageEntry>[],
      );

      final report = await service.getUsageReport();
      expect(report.permissionGranted, false);
      expect(report.hasData, false);
      expect(report.totalScreenTime, Duration.zero);
    });

    test('aggregates entries into totals, categories, trend and top apps',
        () async {
      final service = _FakeAppUsageService(
        permissionGranted: true,
        entries: <AppUsageEntry>[
          const AppUsageEntry(
            packageName: 'com.google.android.youtube',
            appName: 'YouTube',
            totalForegroundTimeMs: 3600000,
            dailyUsageMs: {'2026-02-18': 1800000, '2026-02-19': 1800000},
          ),
          const AppUsageEntry(
            packageName: 'com.whatsapp',
            appName: 'WhatsApp',
            totalForegroundTimeMs: 1800000,
            dailyUsageMs: {'2026-02-19': 1800000},
          ),
        ],
      );

      final report = await service.getUsageReport(pastDays: 7, topAppCount: 5);

      expect(report.permissionGranted, true);
      expect(report.totalScreenTime, const Duration(minutes: 90));
      expect(
        report.averageDailyScreenTime,
        const Duration(milliseconds: 5400000 ~/ 7),
      );
      expect(report.categorySlices.isNotEmpty, true);
      expect(report.topApps.length, 2);
      expect(report.topApps.first.appName, 'YouTube');
    });

    test('maps unknown package to Other category', () async {
      final service = _FakeAppUsageService(
        permissionGranted: true,
        entries: const <AppUsageEntry>[
          AppUsageEntry(
            packageName: 'com.example.unknown',
            appName: 'Unknown App',
            totalForegroundTimeMs: 120000,
          ),
        ],
      );

      final report = await service.getUsageReport(pastDays: 7);
      expect(report.topApps.first.category, 'Other');
    });
  });
}
