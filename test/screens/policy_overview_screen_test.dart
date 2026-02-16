import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/policy_overview_screen.dart';

void main() {
  group('PolicyOverviewScreen', () {
    late ChildProfile testChild;

    setUp(() {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );
    });

    testWidgets('renders policy overview correctly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: PolicyOverviewScreen(child: testChild),
        ),
      );

      expect(find.text('Test Child\'s Policy'), findsOneWidget);
      expect(find.text('Content & Time Controls'), findsOneWidget);
      expect(find.text('Protection Summary'), findsOneWidget);
    });

    testWidgets('displays quick stats', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: PolicyOverviewScreen(child: testChild),
        ),
      );

      expect(find.text('Categories\nBlocked'), findsOneWidget);
      expect(find.text('Time\nRules'), findsOneWidget);
      expect(find.text('Custom\nDomains'), findsOneWidget);
    });

    testWidgets('shows all policy sections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: PolicyOverviewScreen(child: testChild),
        ),
      );

      expect(find.text('Blocked Content Categories'), findsOneWidget);
      expect(find.text('Time Restrictions'), findsOneWidget);
      expect(find.text('Safe Search'), findsOneWidget);
      expect(find.text('Custom Blocked Domains'), findsOneWidget);
    });
  });
}
