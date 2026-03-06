import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trustbridge_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppTheme', () {
    test('color tokens match design specification', () {
      // Calm Guardian redesign: sage green primary, warm dark backgrounds
      expect(AppColors.primary, const Color(0xFF7CB987));
      expect(AppColors.bgLight, const Color(0xFFF0F4F8));
      expect(AppColors.bg, const Color(0xFF0F0F0F));
      expect(AppColors.success, const Color(0xFF7CB987));
      expect(AppColors.danger, const Color(0xFFE07070));
      expect(AppColors.surface, const Color(0xFF1A1A1A));
    });

    test('light theme uses tokenized background and card radius', () {
      final theme = AppTheme.light();

      expect(theme.scaffoldBackgroundColor, AppColors.bgLight);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.colorScheme.tertiary, AppColors.success);
      expect(theme.colorScheme.error, AppColors.danger);

      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      final radius = shape.borderRadius as BorderRadius;
      expect(radius.topLeft.x, 16);
      expect(radius.bottomRight.x, 16);
    });

    test('dark theme uses dark tokenized surfaces', () {
      final theme = AppTheme.dark();

      expect(theme.scaffoldBackgroundColor, AppColors.bg);
      expect(theme.cardColor, AppColors.surface);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(
          theme.bottomNavigationBarTheme.selectedItemColor, AppColors.primary);
    });
  });
}
