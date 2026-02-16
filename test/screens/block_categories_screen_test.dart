import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/block_categories_screen.dart';

void main() {
  group('BlockCategoriesScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('renders category sections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );

      expect(find.text('Block Categories'), findsOneWidget);
      expect(find.text('High Risk'), findsOneWidget);
      expect(find.text('Medium Risk'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Low Risk'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Low Risk'), findsOneWidget);
    });

    testWidgets('shows quick action buttons', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );

      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
    });

    testWidgets('displays category switches and updates save state',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );

      expect(find.byType(SwitchListTile), findsWidgets);
      expect(find.text('SAVE'), findsNothing);

      await tester.tap(find.text('Violence'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE'), findsOneWidget);
    });
  });
}
