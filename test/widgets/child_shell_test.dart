import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/widgets/child_shell.dart';

void main() {
  group('ChildShell', () {
    final child = ChildProfile.create(
      nickname: 'Maya',
      ageBand: AgeBand.middle,
    );

    Widget buildShell() {
      return MaterialApp(
        home: ChildShell(
          child: child,
          firestoreService: FirestoreService(
            firestore: FakeFirebaseFirestore(),
          ),
          parentIdOverride: 'parent-child-shell',
          enableTutorialGate: false,
        ),
      );
    }

    testWidgets('renders child bottom navigation tabs', (tester) async {
      await tester.pumpWidget(buildShell());
      await tester.pump();

      expect(find.byKey(const Key('child_shell_bottom_nav')), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
    });

    testWidgets('switches to activity tab', (tester) async {
      await tester.pumpWidget(buildShell());
      await tester.pump();

      await tester.tap(find.text('Activity'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Request Updates'), findsOneWidget);
    });

    testWidgets('switches to help tab', (tester) async {
      await tester.pumpWidget(buildShell());
      await tester.pump();

      await tester.tap(find.text('Help'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(
          'Need help?\n\nOpen Request Access to ask your parent for temporary allowance.',
        ),
        findsOneWidget,
      );
    });
  });
}
