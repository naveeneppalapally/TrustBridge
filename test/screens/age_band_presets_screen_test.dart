import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/age_band_presets_screen.dart';

void main() {
  group('AgeBandPresetsScreen', () {
    testWidgets('renders all age band cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AgeBandPresetsScreen(),
        ),
      );

      expect(find.text('Choose Age-Appropriate Protection'), findsOneWidget);
      expect(find.text('Quick Comparison'), findsOneWidget);
      expect(find.text('6-9 Years'), findsOneWidget);
      expect(find.text('10-13 Years'), findsOneWidget);
      expect(find.text('14-17 Years'), findsOneWidget);
    });

    testWidgets('expansion tiles show policy details', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AgeBandPresetsScreen(),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('6-9 Years'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('6-9 Years'));
      await tester.pumpAndSettle();

      expect(find.text('Blocked Content'), findsOneWidget);
      expect(find.text('Time Restrictions'), findsOneWidget);
      expect(find.text('Why these restrictions?'), findsOneWidget);
    });

    testWidgets('shows philosophy section', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: AgeBandPresetsScreen(),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();

      expect(find.text('Our Philosophy'), findsOneWidget);
    });
  });
}
