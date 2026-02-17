import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_request_screen.dart';

void main() {
  group('ChildRequestScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Aarav',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('renders form sections', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestScreen(
            child: testChild,
            parentIdOverride: 'parent-test',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Ask for Access'), findsWidgets);
      expect(find.text('What do you need?'), findsOneWidget);
      expect(find.text('For how long?'), findsOneWidget);
      expect(find.text('Why do you need it?'), findsOneWidget);
    });

    testWidgets('shows all duration chips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestScreen(
            child: testChild,
            parentIdOverride: 'parent-test',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('1 hour'), findsOneWidget);
      expect(find.text('Until schedule ends'), findsOneWidget);
    });

    testWidgets('send button disabled when app field is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestScreen(
            child: testChild,
            parentIdOverride: 'parent-test',
          ),
        ),
      );
      await tester.pump();

      await tester.dragUntilVisible(
        find.byKey(const Key('child_request_submit_button')),
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('child_request_submit_button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('preview card appears when app name entered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestScreen(
            child: testChild,
            parentIdOverride: 'parent-test',
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('child_request_app_input')),
        'Instagram',
      );
      await tester.pump();

      await tester.dragUntilVisible(
        find.text('Your request:'),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pump();

      expect(find.text('Your request:'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
    });

    testWidgets('duration chip selection updates preview label',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildRequestScreen(
            child: testChild,
            parentIdOverride: 'parent-test',
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('child_request_app_input')),
        'YouTube',
      );
      await tester.pump();

      await tester.tap(find.text('1 hour'));
      await tester.pump();

      await tester.dragUntilVisible(
        find.text('Your request:'),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pump();

      expect(find.text('1 hour'), findsWidgets);
      expect(find.text('Your request:'), findsOneWidget);
    });
  });
}
