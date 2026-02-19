import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/screens/child_detail_screen.dart';

void main() {
  group('Navigation Tests', () {
    testWidgets('AddChildScreen can be instantiated', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AddChildScreen(),
        ),
      );

      expect(find.text('Add Child'), findsOneWidget);
      expect(find.text('PROTECTION LEVEL'), findsOneWidget);
    });

    testWidgets('ChildDetailScreen displays child info', (tester) async {
      final child = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(child: child),
        ),
      );

      expect(find.text('Test Child'), findsOneWidget);
      expect(find.text('Quick Actions'), findsOneWidget);
    });

    testWidgets('Back button navigation works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AddChildScreen(),
                      ),
                    );
                  },
                  child: const Text('Navigate'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();

      expect(find.text('Add Child'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Navigate'), findsOneWidget);
    });
  });
}
