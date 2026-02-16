import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/change_password_screen.dart';

void main() {
  group('ChangePasswordScreen', () {
    testWidgets('renders password form for email account', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChangePasswordScreen(
            emailOverride: 'parent@test.com',
          ),
        ),
      );

      expect(find.text('Change Password'), findsOneWidget);
      expect(find.byKey(const Key('current_password_input')), findsOneWidget);
      expect(find.byKey(const Key('new_password_input')), findsOneWidget);
      expect(find.byKey(const Key('confirm_password_input')), findsOneWidget);
      expect(find.text('Update Password'), findsOneWidget);
    });

    testWidgets('shows validation errors for invalid passwords',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChangePasswordScreen(
            emailOverride: 'parent@test.com',
          ),
        ),
      );

      await tester.tap(find.text('Update Password'));
      await tester.pump();
      expect(find.text('Enter your current password'), findsOneWidget);
      expect(find.text('Enter a new password'), findsOneWidget);
      expect(find.text('Confirm your new password'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('current_password_input')), 'abc12345');
      await tester.enterText(
          find.byKey(const Key('new_password_input')), 'short');
      await tester.enterText(
          find.byKey(const Key('confirm_password_input')), 'short');
      await tester.tap(find.text('Update Password'));
      await tester.pump();

      expect(
          find.text('Password must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('submits valid form through callback', (tester) async {
      String? current;
      String? next;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangePasswordScreen(
            emailOverride: 'parent@test.com',
            onSubmit: (currentPassword, newPassword) async {
              current = currentPassword;
              next = newPassword;
            },
          ),
        ),
      );

      await tester.enterText(
          find.byKey(const Key('current_password_input')), 'OldPass123');
      await tester.enterText(
          find.byKey(const Key('new_password_input')), 'NewPass456');
      await tester.enterText(
          find.byKey(const Key('confirm_password_input')), 'NewPass456');
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();

      expect(current, 'OldPass123');
      expect(next, 'NewPass456');
    });
  });
}
