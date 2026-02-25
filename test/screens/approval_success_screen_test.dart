import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trustbridge_app/screens/approval_success_screen.dart';

void main() {
  group('ApprovalSuccessScreen', () {
    testWidgets('renders confirmation details and done button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ApprovalSuccessScreen(
            appName: 'instagram.com',
            durationLabel: '30 min',
            childName: 'Aarav',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Success!'), findsOneWidget);
      expect(find.text('instagram.com approved for 30 min'), findsOneWidget);
      expect(find.text('Sent to Aarav'), findsOneWidget);
      expect(find.byKey(const Key('approval_success_done_button')),
          findsOneWidget);
    });

    testWidgets('done button pops the screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open_approval_success_button'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ApprovalSuccessScreen(
                          appName: 'youtube.com',
                          durationLabel: '1 hour',
                          childName: 'Maya',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_approval_success_button')));
      await tester.pumpAndSettle();
      expect(find.text('Success!'), findsOneWidget);

      await tester.tap(find.byKey(const Key('approval_success_done_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open_approval_success_button')),
          findsOneWidget);
    });
  });
}
