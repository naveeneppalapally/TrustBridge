import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/child/request_access_screen.dart';

void main() {
  group('RequestAccessScreen', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    testWidgets('duration selector allows selecting 30 min', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RequestAccessScreen(
            firestore: firestore,
            parentId: 'parent-1',
            childId: 'child-1',
            childNickname: 'Rahul',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();

      final selectedChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '30 min'),
      );
      expect(selectedChip.selected, true);
    });

    testWidgets('send button disabled until app is selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RequestAccessScreen(
            firestore: firestore,
            parentId: 'parent-1',
            childId: 'child-1',
            childNickname: 'Rahul',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sendButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send request'),
      );
      expect(sendButton.onPressed, isNull);
    });

    testWidgets('on send creates Firestore access request document',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RequestAccessScreen(
            firestore: firestore,
            parentId: 'parent-1',
            childId: 'child-1',
            childNickname: 'Rahul',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Instagram'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
      await tester.pumpAndSettle();

      final docs = await firestore
          .collection('parents')
          .doc('parent-1')
          .collection('access_requests')
          .get();
      expect(docs.docs, isNotEmpty);
      final data = docs.docs.first.data();
      expect(data['childId'], 'child-1');
      expect(data['childNickname'], 'Rahul');
      expect(data['appOrSite'], 'Instagram');
      expect(data['durationLabel'], '30 min');
      expect(data['status'], 'pending');
    });

    testWidgets('after send shows pending confirmation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RequestAccessScreen(
            firestore: firestore,
            parentId: 'parent-1',
            childId: 'child-1',
            childNickname: 'Rahul',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Instagram'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
      await tester.pumpAndSettle();

      expect(find.text('Request sent!'), findsOneWidget);
      expect(find.text('Back to home'), findsOneWidget);
    });
  });
}
