import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_status_screen.dart';

void main() {
  group('ChildStatusScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Aarav',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('renders greeting with child nickname', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Aarav'), findsOneWidget);
    });

    testWidgets('displays active mode name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      final modeFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'Free Time' ||
                widget.data == 'Homework Time' ||
                widget.data == 'Bedtime' ||
                widget.data == 'School Hours' ||
                widget.data == 'Custom Schedule'),
      );
      expect(modeFinder, findsWidgets);
    });

    testWidgets('shows Ask for Access button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.text('Ask for Access'), findsOneWidget);
      expect(find.text('Request Updates'), findsOneWidget);
    });

    testWidgets('uses non-punitive wording', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.textContaining('BLOCKED'), findsNothing);
      expect(find.textContaining('DENIED'), findsNothing);
      expect(find.textContaining('FORBIDDEN'), findsNothing);
    });

    testWidgets('tap Ask for Access navigates to request screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChildStatusScreen(child: testChild),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Ask for Access'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('What do you need?'), findsOneWidget);
    });
  });
}
