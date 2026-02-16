import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_detail_screen.dart';

void main() {
  group('ChildDetailScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('displays child information correctly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(child: testChild),
        ),
      );

      expect(find.text('Test Child'), findsWidgets);
      expect(find.text('Age: 6-9'), findsOneWidget);
      expect(find.textContaining('Added'), findsOneWidget);
    });

    testWidgets('shows policy summary metrics', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(child: testChild),
        ),
      );

      expect(find.text('Protection Overview'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsWidgets);
      expect(find.byIcon(Icons.schedule), findsWidgets);
      expect(find.text('ON'), findsOneWidget);
    });

    testWidgets('displays blocked categories as chips', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(child: testChild),
        ),
      );

      expect(find.text('Blocked Content'), findsOneWidget);
      expect(find.text('Social Networks'), findsOneWidget);
      expect(find.byType(Chip), findsWidgets);
    });

    testWidgets('shows quick action buttons', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(child: testChild),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Edit Profile'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('delete button shows confirmation dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(child: testChild),
        ),
      );

      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Delete'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Child Profile'), findsOneWidget);
      expect(
        find.text(
          'Are you sure you want to delete Test Child\'s profile? This action cannot be undone.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
