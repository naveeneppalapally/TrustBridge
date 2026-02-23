import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/child/child_status_screen.dart';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 50);
  final wholeSteps = duration.inMilliseconds ~/ step.inMilliseconds;
  for (var i = 0; i < wholeSteps; i++) {
    await tester.pump(step);
  }
}

void main() {
  group('ChildStatusScreen', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      await firestore.collection('children').doc('child-1').set({
        'nickname': 'Rahul',
        'ageBand': '10-13',
        'deviceIds': const <String>['device-1'],
        'parentId': 'parent-1',
        'policy': {
          'blockedCategories': const <String>['social-networks'],
          'blockedDomains': const <String>['instagram.com'],
          'safeSearchEnabled': true,
          'schedules': const <Map<String, dynamic>>[],
        },
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });

    testWidgets('renders for paired child context without throwing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChildStatusScreen(
              firestore: firestore,
              parentId: 'parent-1',
              childId: 'child-1',
            ),
          ),
        ),
      );

      await _pumpFor(tester, const Duration(milliseconds: 600));

      expect(find.byType(ChildStatusScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not render raw DNS or VPN terms', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChildStatusScreen(
              firestore: firestore,
              parentId: 'parent-1',
              childId: 'child-1',
            ),
          ),
        ),
      );

      await _pumpFor(tester, const Duration(milliseconds: 600));

      expect(find.textContaining('DNS'), findsNothing);
      expect(find.textContaining('VPN'), findsNothing);
    });
  });
}
