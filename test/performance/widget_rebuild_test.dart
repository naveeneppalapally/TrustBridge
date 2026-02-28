import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/onboarding_screen.dart';

void main() {
  group('Widget rebuild efficiency', () {
    testWidgets('OnboardingScreen builds without excessive parent rebuilds',
        (WidgetTester tester) async {
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              buildCount++;
              return const OnboardingScreen(parentId: 'parent-test');
            },
          ),
        ),
      );
      await tester.pump();

      expect(buildCount, lessThanOrEqualTo(3));
      expect(find.text('Set up in one step'), findsOneWidget);
    });

    testWidgets('static widgets can be const', (WidgetTester tester) async {
      const sizedBox = SizedBox(height: 16);
      const icon = Icon(Icons.shield);
      const divider = Divider();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                sizedBox,
                icon,
                divider,
              ],
            ),
          ),
        ),
      );

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });
  });

  group('Release mode assumptions', () {
    test('kReleaseMode is false in widget tests', () {
      expect(const bool.fromEnvironment('dart.vm.product'), false);
    });
  });
}
