import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/age_preset_policy_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('AgePresetPolicyScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.middle,
      );
    });

    testWidgets('renders preset details', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: AgePresetPolicyScreen(child: testChild),
        ),
      );

      expect(find.text('Age Preset'), findsOneWidget);
      expect(find.textContaining('Recommended for Age'), findsOneWidget);
      expect(find.text('Current vs Recommended'), findsOneWidget);
      expect(find.text('Apply Recommended Preset'), findsOneWidget);
    });

    testWidgets('applies preset and updates Firestore', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);
      const parentId = 'parent-test-002';

      await fakeFirestore.collection('children').doc(testChild.id).set({
        ...testChild.toFirestore(),
        'parentId': parentId,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AgePresetPolicyScreen(
            child: testChild,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );

      await tester
          .tap(find.widgetWithText(FilledButton, 'Apply Recommended Preset'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      final snapshot =
          await fakeFirestore.collection('children').doc(testChild.id).get();
      final policyMap = snapshot.data()!['policy'] as Map<String, dynamic>;
      final schedules = policyMap['schedules'] as List<dynamic>;

      expect(policyMap['blockedCategories'], isA<List<dynamic>>());
      expect(
          (policyMap['blockedCategories'] as List<dynamic>).isNotEmpty, true);
      expect(schedules.isNotEmpty, true);
    });
  });
}
