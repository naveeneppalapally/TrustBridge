import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/edit_child_screen.dart';

void main() {
  group('EditChildScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('renders with pre-populated values', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: EditChildScreen(child: testChild),
        ),
      );

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Test Child');
      expect(find.byType(Radio<AgeBand>), findsNWidgets(3));
      expect(find.text('Current'), findsOneWidget);
    });

    testWidgets('shows warning and policy changes when age band changes',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: EditChildScreen(child: testChild),
        ),
      );

      await tester.tap(find.text('10-13 years'));
      await tester.pump();

      expect(
        find.text(
          'Changing age band will update content filters to match the new age group.',
        ),
        findsOneWidget,
      );
      expect(find.text('Policy Changes'), findsOneWidget);
      expect(find.text('Blocked Categories'), findsOneWidget);
    });

    testWidgets('shows no-changes snackbar when nothing modified',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: EditChildScreen(child: testChild),
        ),
      );

      await tester.tap(find.byKey(const Key('edit_child_save')));
      await tester.pump();

      expect(find.text('No changes to save'), findsOneWidget);
    });

    testWidgets('validates empty nickname', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: EditChildScreen(child: testChild),
        ),
      );

      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.byKey(const Key('edit_child_save')));
      await tester.pump();

      expect(find.text('Please enter a nickname'), findsOneWidget);
    });
  });
}
