import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/duplicate_analytics_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('DuplicateAnalyticsScreen', () {
    testWidgets('renders screen title and action buttons', (tester) async {
      final fakeService = _FakeFirestoreService(
        analyticsResponse: const <String, dynamic>{
          'totalDuplicateClusters': 0,
          'totalDuplicateReports': 0,
          'resolutionRate': 0.0,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DuplicateAnalyticsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Duplicate Analytics'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('shows empty state when duplicate clusters are absent',
        (tester) async {
      final fakeService = _FakeFirestoreService(
        analyticsResponse: const <String, dynamic>{
          'totalDuplicateClusters': 0,
          'totalDuplicateReports': 0,
          'resolutionRate': 0.0,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DuplicateAnalyticsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No duplicate reports yet'), findsOneWidget);
    });

    testWidgets('renders summary cards for populated analytics',
        (tester) async {
      final fakeService = _FakeFirestoreService(
        analyticsResponse: const <String, dynamic>{
          'topIssues': <Map<String, dynamic>>[
            <String, dynamic>{'subject': 'Vpn Crash On Enable', 'count': 3},
            <String, dynamic>{'subject': 'Schedule Not Enforcing', 'count': 2},
          ],
          'avgVelocityDays': 2.5,
          'minVelocityDays': 0.8,
          'maxVelocityDays': 4.6,
          'volumeByWeek': <String, int>{
            'Week -3': 1,
            'Week -2': 2,
            'Week -1': 4,
            'Week -0': 3,
          },
          'categoryBreakdown': <String, int>{
            'VPN': 4,
            'Policy': 2,
          },
          'totalDuplicateClusters': 2,
          'totalDuplicateReports': 5,
          'resolutionRate': 0.6,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DuplicateAnalyticsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Top Duplicate Issues'), findsOneWidget);
      expect(find.text('Resolution Velocity'), findsOneWidget);
      expect(find.text('Vpn Crash On Enable'), findsOneWidget);
      expect(find.text('Clusters'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Category Breakdown'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Category Breakdown'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Volume Trend'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Volume Trend'), findsOneWidget);
    });

    testWidgets('export button requests CSV and uses injected share callback',
        (tester) async {
      final fakeService = _FakeFirestoreService(
        analyticsResponse: const <String, dynamic>{
          'totalDuplicateClusters': 1,
          'totalDuplicateReports': 2,
          'resolutionRate': 0.5,
        },
        csvResponse: 'Subject,Report Count,Category\n"VPN crash",2,VPN\n',
      );
      String? sharedCsv;

      await tester.pumpWidget(
        MaterialApp(
          home: DuplicateAnalyticsScreen(
            parentIdOverride: 'parent-a',
            firestoreService: fakeService,
            onShareCsv: (csv) async {
              sharedCsv = csv;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('duplicate_analytics_export_button')),
      );
      await tester.pumpAndSettle();

      expect(fakeService.exportCallCount, 1);
      expect(sharedCsv, contains('Subject,Report Count,Category'));
    });
  });
}

class _FakeFirestoreService extends FirestoreService {
  _FakeFirestoreService({
    required Map<String, dynamic> analyticsResponse,
    String csvResponse = '',
  })  : _analyticsResponse = analyticsResponse,
        _csvResponse = csvResponse,
        super(firestore: FakeFirebaseFirestore());

  final Map<String, dynamic> _analyticsResponse;
  final String _csvResponse;
  int exportCallCount = 0;

  @override
  Future<Map<String, dynamic>> getDuplicateAnalytics(String parentId) async {
    return _analyticsResponse;
  }

  @override
  Future<String> exportDuplicateClustersCSV(String parentId) async {
    exportCallCount += 1;
    return _csvResponse;
  }
}
