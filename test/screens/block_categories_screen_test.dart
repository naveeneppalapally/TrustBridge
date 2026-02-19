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

    testWidgets('renders search and category section', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.text('Category Blocking'), findsOneWidget);
      expect(find.byKey(const Key('block_categories_search')), findsOneWidget);
      expect(find.text('APP CATEGORIES'), findsOneWidget);
      expect(find.text('Social Networks'), findsOneWidget);
    });

    testWidgets('shows custom blocked sites section with add button',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('CUSTOM BLOCKED SITES'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('CUSTOM BLOCKED SITES'), findsOneWidget);
      expect(find.byKey(const Key('block_categories_add_domain')), findsOneWidget);
    });

    testWidgets('switch updates state and shows sticky save bar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('block_categories_save_button')), findsNothing);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('block_categories_save_button')), findsOneWidget);
      expect(find.textContaining('Safe Mode Active'), findsOneWidget);
    });

    testWidgets('can add a custom blocked domain', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.byKey(const Key('block_categories_add_domain')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('block_categories_add_domain')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('block_categories_domain_input')),
        'reddit.com',
      );
      await tester.tap(find.byKey(const Key('block_categories_add_domain_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('reddit.com'), findsOneWidget);
    });
  });
}
