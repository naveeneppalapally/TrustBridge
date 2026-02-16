import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/custom_domains_screen.dart';

void main() {
  group('CustomDomainsScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('renders editor sections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: CustomDomainsScreen(child: testChild),
        ),
      );

      expect(find.text('Custom Domains'), findsOneWidget);
      expect(find.text('Add Domain'), findsOneWidget);
      expect(find.text('Quick Add'), findsOneWidget);
      expect(find.text('Blocked Domains'), findsOneWidget);
    });

    testWidgets('adds a valid domain and enables save', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: CustomDomainsScreen(child: testChild),
        ),
      );

      await tester.enterText(
          find.byType(TextField), 'https://www.Example.com/a');
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'example.com'), findsOneWidget);
      expect(find.text('SAVE'), findsOneWidget);
    });

    testWidgets('shows validation for invalid domain', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: CustomDomainsScreen(child: testChild),
        ),
      );

      await tester.enterText(find.byType(TextField), 'invalid-domain');
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a valid domain like example.com'),
        findsOneWidget,
      );
    });
  });
}
