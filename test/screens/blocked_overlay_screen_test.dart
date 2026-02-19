import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/blocked_overlay_screen.dart';

void main() {
  group('BlockedOverlayScreen', () {
    testWidgets('renders blocked state and status card', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BlockedOverlayScreen(
            modeName: 'Homework Mode',
            remainingLabel: '1h 34m',
            blockedDomain: 'instagram.com',
          ),
        ),
      );

      expect(
        find.byKey(const Key('blocked_overlay_title')),
        findsOneWidget,
      );
      expect(
        find.text('This is blocked during Homework Mode'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('blocked_overlay_status_card')),
        findsOneWidget,
      );
      expect(find.text('instagram.com'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('request access button triggers callback', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: BlockedOverlayScreen(
            modeName: 'Bedtime Mode',
            onRequestAccess: () {
              tapped = true;
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('blocked_overlay_request_button')));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('dismiss button triggers callback', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: BlockedOverlayScreen(
            modeName: 'School Mode',
            onDismiss: () {
              dismissed = true;
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('blocked_overlay_dismiss_button')));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });
}
