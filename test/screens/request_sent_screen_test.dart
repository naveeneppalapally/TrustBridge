import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/request_sent_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('RequestSentScreen', () {
    late ChildProfile testChild;
    late FirestoreService firestoreService;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Aarav',
        ageBand: AgeBand.young,
      );
      firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
    });

    testWidgets('renders success content and status card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RequestSentScreen(
            child: testChild,
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Request Sent!'), findsOneWidget);
      expect(find.text('CURRENT STATUS'), findsOneWidget);
      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.byKey(const Key('request_sent_view_status_button')),
          findsOneWidget);
      expect(
          find.byKey(const Key('request_sent_back_home_button')), findsOneWidget);
    });

    testWidgets('view status button opens child request updates screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RequestSentScreen(
            child: testChild,
            parentIdOverride: 'parent-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pump();

      await tester
          .tap(find.byKey(const Key('request_sent_view_status_button')));
      await tester.pumpAndSettle();

      expect(find.text('Request Updates'), findsOneWidget);
    });
  });
}
