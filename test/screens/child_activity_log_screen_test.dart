import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_activity_log_screen.dart';

void main() {
  group('ChildActivityLogScreen', () {
    testWidgets('renders activity timeline entries', (tester) async {
      final child = ChildProfile.create(
        nickname: 'Maya',
        ageBand: AgeBand.middle,
      ).copyWith(
        pausedUntil: DateTime.now().add(const Duration(minutes: 30)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChildActivityLogScreen(child: child),
        ),
      );

      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.text('Profile created'), findsOneWidget);
      expect(find.text('Policy updated'), findsOneWidget);
      expect(find.text('Device links reviewed'), findsOneWidget);
    });
  });
}
