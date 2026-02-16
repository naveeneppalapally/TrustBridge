import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/privacy_center_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('PrivacyCenterScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    Future<void> seedParent(String parentId) {
      return fakeFirestore.collection('parents').doc(parentId).set({
        'parentId': parentId,
        'preferences': {
          'activityHistoryEnabled': true,
          'crashReportsEnabled': true,
          'personalizedTipsEnabled': true,
        },
      });
    }

    testWidgets('renders privacy settings content', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await seedParent('parent-privacy-a');

      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyCenterScreen(
            parentIdOverride: 'parent-privacy-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacy Center'), findsOneWidget);
      expect(find.text('Control Data Usage'), findsOneWidget);
      expect(find.byKey(const Key('privacy_activity_history_switch')),
          findsOneWidget);
      expect(find.byKey(const Key('privacy_crash_reports_switch')),
          findsOneWidget);
      expect(find.byKey(const Key('privacy_personalized_tips_switch')),
          findsOneWidget);
    });

    testWidgets('saves crash report toggle to firestore', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const parentId = 'parent-privacy-b';
      await seedParent(parentId);

      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyCenterScreen(
            parentIdOverride: parentId,
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('privacy_crash_reports_switch')));
      await tester.pumpAndSettle();

      expect(find.text('SAVE'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'SAVE'));
      await tester.pumpAndSettle();

      final snapshot =
          await fakeFirestore.collection('parents').doc(parentId).get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;
      expect(preferences['crashReportsEnabled'], false);
    });
  });
}
