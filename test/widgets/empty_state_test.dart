import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/widgets/empty_state.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, subtitle, and action',
        (WidgetTester tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: const Text('\u{1F44B}'),
              title: 'Nothing here yet',
              subtitle: 'Create your first item to get started.',
              actionLabel: 'Create',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
          find.text('Create your first item to get started.'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);

      await tester.tap(find.text('Create'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('hides action button when action values are absent',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icon(Icons.inbox_outlined),
              title: 'No data',
              subtitle: 'Try again later.',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No data'), findsOneWidget);
      expect(find.text('Try again later.'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });
}
