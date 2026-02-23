import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trustbridge_app/screens/usage_reports_screen.dart';
import 'package:trustbridge_app/services/app_usage_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';
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
    Future<void> pumpScreen(
      WidgetTester tester, {
      AppUsageService? appUsageService,
      FirestoreService? firestoreService,
      NextDnsApiService? nextDnsApiService,
      String? parentIdOverride,
    }) async {
      await tester.binding.setSurfaceSize(const Size(430, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: UsageReportsScreen(
            appUsageService: appUsageService,
            firestoreService: firestoreService,
            nextDnsApiService: nextDnsApiService,
            parentIdOverride: parentIdOverride,
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
    });

    testWidgets('shows hero card and category section', (tester) async {
      await pumpScreen(tester, appUsageService: buildDataService());

      expect(find.byKey(const Key('usage_reports_hero_card')), findsOneWidget);
      expect(find.text('Total Screen Time'), findsOneWidget);
      expect(find.text('5h 47m'), findsOneWidget);

      expect(
        find.byKey(const Key('usage_reports_category_card')),
        findsOneWidget,
      );
      expect(find.text('By Category'), findsOneWidget);
      expect(find.text('Social'), findsWidgets);
      expect(find.text('Education'), findsWidgets);
      expect(find.text('Games'), findsWidgets);
    });

    testWidgets('shows trend and most used apps sections', (tester) async {
      await pumpScreen(tester, appUsageService: buildDataService());

      expect(find.byKey(const Key('usage_reports_trend_card')), findsOneWidget);
      expect(find.text('7-Day Trend'), findsOneWidget);

      expect(find.byKey(const Key('usage_reports_apps_card')), findsOneWidget);
      expect(find.text('Most Used Apps'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Entertainment'), findsOneWidget);
      expect(find.text('Social'), findsWidgets);
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

    testWidgets('shows child-report waiting state when usage data is unavailable',
        (tester) async {
      await pumpScreen(
        tester,
        appUsageService: _FakeAppUsageService(
          permissionGranted: false,
          reportData: UsageReportData.permissionDenied(),
        ),
      );

      expect(find.text('No child devices paired'), findsOneWidget);
      expect(find.text('Grant Access'), findsNothing);
      expect(find.byKey(const Key('usage_reports_nextdns_card')), findsOneWidget);
    });

    testWidgets('shows NextDNS analytics when profile is configured',
        (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      const parentId = 'parent-nextdns-usage';

      await fakeFirestore.collection('parents').doc(parentId).set({
        'uid': parentId,
        'phoneNumber': '+911234567890',
        'preferences': {
          'nextDnsEnabled': true,
          'nextDnsProfileId': 'abc123',
        },
      });

      final firestoreService = FirestoreService(firestore: fakeFirestore);
      final nextDnsApiService = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/analytics/domains')) {
            return http.Response(
              jsonEncode({
                'data': [
                  {'domain': 'youtube.com', 'queries': 12},
                  {'domain': 'tiktok.com', 'queries': 7},
                ],
              }),
              200,
            );
          }
          if (path.endsWith('/analytics/status')) {
            return http.Response(
              jsonEncode({
                'data': [
                  {'status': 'blocked', 'queries': 19},
                  {'status': 'allowed', 'queries': 40},
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'data': []}), 200);
        }),
      );
      await nextDnsApiService.setNextDnsApiKey('test-api-key');

      await pumpScreen(
        tester,
        appUsageService: buildDataService(),
        firestoreService: firestoreService,
        nextDnsApiService: nextDnsApiService,
        parentIdOverride: parentId,
      );

      expect(find.byKey(const Key('usage_reports_nextdns_card')), findsOneWidget);
      expect(find.text('Sites Blocked Today: 19'), findsOneWidget);
      expect(find.text('youtube.com'), findsOneWidget);
      expect(find.text('tiktok.com'), findsOneWidget);
    });
  });
}
