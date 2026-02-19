import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/utils/spring_animation.dart';

void main() {
  group('SpringAnimation', () {
    test('uses design token stiffness and damping', () {
      expect(SpringAnimation.stiffness, 300);
      expect(SpringAnimation.damping, 20);
    });

    test('spring curve remains within normalized range', () {
      const curve = SpringAnimation.springCurve;
      expect(curve.transform(0), inInclusiveRange(0, 1));
      expect(curve.transform(0.25), inInclusiveRange(0, 1));
      expect(curve.transform(0.5), inInclusiveRange(0, 1));
      expect(curve.transform(0.75), inInclusiveRange(0, 1));
      expect(curve.transform(1), inInclusiveRange(0, 1));
    });

    testWidgets('slidePageRoute navigates without errors',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      SpringAnimation.slidePageRoute(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('Destination')),
                        ),
                      ),
                    );
                  },
                  child: const Text('Go'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Destination'), findsOneWidget);
    });
  });
}
