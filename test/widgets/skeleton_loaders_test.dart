import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:trustbridge_app/widgets/skeleton_loaders.dart';

void main() {
  group('Skeleton loaders', () {
    Future<void> pumpWidgetUnderTest(
      WidgetTester tester,
      Widget child,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: child),
        ),
      );
      await tester.pump();
    }

    testWidgets('SkeletonCard renders shimmer surface', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SkeletonCard(
          key: Key('skeleton_card'),
          height: 120,
        ),
      );

      expect(find.byKey(const Key('skeleton_card')), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('SkeletonChildCard renders card scaffold', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SkeletonChildCard(key: Key('skeleton_child')),
      );

      expect(find.byKey(const Key('skeleton_child')), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('SkeletonListTile renders optional trailing area',
        (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SkeletonListTile(
          key: Key('skeleton_tile'),
          showTrailing: true,
        ),
      );

      expect(find.byKey(const Key('skeleton_tile')), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('SkeletonChart renders shimmer chart bars', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SkeletonChart(
          key: Key('skeleton_chart'),
          height: 200,
        ),
      );

      expect(find.byKey(const Key('skeleton_chart')), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
    });
  });
}
