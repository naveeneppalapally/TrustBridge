import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trustbridge_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppTheme', () {
    test('color tokens match design specification', () {
      expect(AppColors.primary, const Color(0xFF207CF8));
      expect(AppColors.bgLight, const Color(0xFFF0F4F8));
      expect(AppColors.bgDark, const Color(0xFF0D1117));
      expect(AppColors.success, const Color(0xFF68B901));
      expect(AppColors.error, const Color(0xFFF41F5C));
      expect(AppColors.cardDark, const Color(0xFF161B22));
    });

    test('light theme uses tokenized background and card radius', () {
      final theme = AppTheme.light();

      expect(theme.scaffoldBackgroundColor, AppColors.bgLight);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.colorScheme.tertiary, AppColors.success);
      expect(theme.colorScheme.error, AppColors.error);

      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      final radius = shape.borderRadius as BorderRadius;
      expect(radius.topLeft.x, 16);
      expect(radius.bottomRight.x, 16);
    });

    test('dark theme uses dark tokenized surfaces', () {
      final theme = AppTheme.dark();

      expect(theme.scaffoldBackgroundColor, AppColors.bgDark);
      expect(theme.cardColor, AppColors.cardDark);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(
          theme.bottomNavigationBarTheme.selectedItemColor, AppColors.primary);
    });
  });
}
