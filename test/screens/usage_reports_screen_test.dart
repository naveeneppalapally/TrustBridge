import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';
import 'package:trustbridge_app/screens/usage_reports_screen.dart';
import 'package:trustbridge_app/services/app_usage_service.dart';
import 'package:trustbridge_app/widgets/skeleton_loaders.dart';

class _FakeAppUsageService extends AppUsageService {
  _FakeAppUsageService({
    required this.permissionGranted,
    required this.reportData,
  });

  final bool permissionGranted;
  final UsageReportData reportData;

  @override
  Future<bool> hasUsageAccessPermission() async => permissionGranted;

  @override
  Future<UsageReportData> getUsageReport({
    int pastDays = 7,
    int topAppCount = 5,
  }) async {
    return reportData;
  }

  @override
  Future<bool> openUsageAccessSettings() async => true;
}

void main() {
  group('UsageReportsScreen', () {
    setUp(() {
      RolloutFlags.resetForTest();
      RolloutFlags.setForTest('per_app_usage_reports', true);
    });
    tearDown(RolloutFlags.resetForTest);

    Future<void> pumpScreen(
      WidgetTester tester, {
      AppUsageService? appUsageService,
    }) async {
      await tester.binding.setSurfaceSize(const Size(430, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: UsageReportsScreen(
            allowLocalDeviceFallback: true,
            appUsageService: appUsageService,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    _FakeAppUsageService buildDataService() {
      return _FakeAppUsageService(
        permissionGranted: true,
        reportData: const UsageReportData(
          permissionGranted: true,
          totalScreenTime: Duration(hours: 5, minutes: 47),
          averageDailyScreenTime: Duration(hours: 4, minutes: 12),
          categorySlices: [
            UsageCategorySlice(
              label: 'Social',
              duration: Duration(hours: 2, minutes: 15),
            ),
            UsageCategorySlice(
              label: 'Education',
              duration: Duration(hours: 2, minutes: 2),
            ),
            UsageCategorySlice(
              label: 'Games',
              duration: Duration(hours: 1, minutes: 30),
            ),
          ],
          dailyTrend: [
            DailyUsagePoint(
                label: 'M', duration: Duration(hours: 3, minutes: 30)),
            DailyUsagePoint(
                label: 'T', duration: Duration(hours: 4, minutes: 6)),
            DailyUsagePoint(label: 'W', duration: Duration(hours: 4)),
            DailyUsagePoint(
                label: 'T', duration: Duration(hours: 3, minutes: 48)),
            DailyUsagePoint(
                label: 'F', duration: Duration(hours: 4, minutes: 12)),
            DailyUsagePoint(
                label: 'S', duration: Duration(hours: 5, minutes: 18)),
            DailyUsagePoint(
                label: 'S', duration: Duration(hours: 5, minutes: 6)),
          ],
          topApps: [
            AppUsageSummary(
              packageName: 'com.google.android.youtube',
              appName: 'YouTube',
              category: 'Entertainment',
              duration: Duration(hours: 1, minutes: 25),
              progress: 0.83,
            ),
            AppUsageSummary(
              packageName: 'com.whatsapp',
              appName: 'WhatsApp',
              category: 'Social',
              duration: Duration(hours: 1, minutes: 12),
              progress: 0.70,
            ),
          ],
        ),
      );
    }

    testWidgets('renders app bar title and date chip', (tester) async {
      await pumpScreen(tester, appUsageService: buildDataService());

      expect(find.text('Usage Reports'), findsOneWidget);
      expect(find.text('This Week'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
      expect(find.textContaining('Clear summary for'), findsOneWidget);
    });

    testWidgets('shows hero card and category section', (tester) async {
      RolloutFlags.setForTest('per_app_usage_reports', true);
      await pumpScreen(tester, appUsageService: buildDataService());

      expect(find.byKey(const Key('usage_reports_hero_card')), findsOneWidget);
      expect(find.text('Selected Day Screen Time'), findsOneWidget);
      expect(find.text('5h 47m'), findsOneWidget);

      expect(
        find.byKey(const Key('usage_reports_category_card')),
        findsOneWidget,
      );
      expect(find.text('By Category'), findsOneWidget);
      expect(find.textContaining('Social'), findsWidgets);
      expect(find.textContaining('Education'), findsWidgets);
      expect(find.textContaining('Games'), findsWidgets);
      expect(find.text('Vs Yesterday'), findsOneWidget);
      expect(find.text('Top App'), findsOneWidget);
    });

    testWidgets('shows trend and most used apps sections', (tester) async {
      RolloutFlags.setForTest('per_app_usage_reports', true);
      expect(RolloutFlags.perAppUsageReports, isTrue);
      await pumpScreen(tester, appUsageService: buildDataService());

      expect(find.byKey(const Key('usage_reports_trend_card')), findsOneWidget);
      expect(find.text('7-Day Trend'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Most Used Apps'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Most Used Apps'), findsOneWidget);
      expect(find.text('YouTube'), findsWidgets);
      expect(find.text('WhatsApp'), findsWidgets);
      expect(find.text('Entertainment'), findsWidgets);
      expect(find.textContaining('Social'), findsWidgets);
    });

    testWidgets('hides per-app/day-filter sections when rollout flag is off',
        (tester) async {
      RolloutFlags.setForTest('per_app_usage_reports', false);

      await pumpScreen(tester, appUsageService: buildDataService());

      expect(find.text('Day Filter'), findsNothing);
      expect(find.byKey(const Key('usage_reports_trend_card')), findsNothing);
      expect(find.byKey(const Key('usage_reports_apps_card')), findsNothing);
      expect(find.byKey(const Key('usage_reports_hero_card')), findsOneWidget);
      expect(
        find.byKey(const Key('usage_reports_category_card')),
        findsOneWidget,
      );
    });

    testWidgets('shows skeleton loaders when loading state is enabled',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: UsageReportsScreen(showLoadingState: true),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonCard), findsWidgets);
      expect(find.byType(SkeletonChart), findsWidgets);
      expect(find.byType(SkeletonListTile), findsWidgets);
    });

    testWidgets(
        'shows child-report waiting state when usage data is unavailable',
        (tester) async {
      await pumpScreen(
        tester,
        appUsageService: _FakeAppUsageService(
          permissionGranted: false,
          reportData: UsageReportData.permissionDenied(),
        ),
      );

      expect(find.text('Usage access required'), findsOneWidget);
      expect(find.text('Grant Access'), findsOneWidget);
    });
  });
}
