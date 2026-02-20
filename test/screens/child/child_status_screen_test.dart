import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/child/child_status_screen.dart';

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
          'schedules': [
            {
              'id': 'schedule-1',
              'name': 'Homework',
              'type': 'homework',
              'days': const [
                'monday',
                'tuesday',
                'wednesday',
                'thursday',
                'friday',
                'saturday',
                'sunday',
              ],
              'startTime': '00:00',
              'endTime': '23:59',
              'enabled': true,
              'action': 'blockDistracting',
            }
          ],
        },
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });

    testWidgets('shows child nickname from Firestore', (tester) async {
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
      await tester.pumpAndSettle();

      expect(find.textContaining('Hi, Rahul'), findsOneWidget);
    });

    testWidgets('shows mode name and emoji', (tester) async {
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
      await tester.pumpAndSettle();

      expect(find.text('Study Mode'), findsOneWidget);
      expect(find.text('📚'), findsOneWidget);
    });

    testWidgets('shows blocked apps using friendly app names', (tester) async {
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
      await tester.pumpAndSettle();

      expect(find.textContaining('Instagram'), findsOneWidget);
      expect(find.text('instagram.com'), findsNothing);
    });

    testWidgets('ask for access button opens request access screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
      await tester.pumpAndSettle();

      final askButton = find.widgetWithText(FilledButton, 'Ask for access');
      await tester.tap(askButton);
      await tester.pumpAndSettle();

      expect(find.text('What do you want to use?'), findsOneWidget);
    });

    testWidgets('does not show technical network terms', (tester) async {
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
      await tester.pumpAndSettle();

      expect(find.textContaining('DNS'), findsNothing);
      expect(find.textContaining('VPN'), findsNothing);
      expect(find.textContaining('domain'), findsNothing);
      expect(find.textContaining('blocked'), findsNothing);
    });
  });
}
