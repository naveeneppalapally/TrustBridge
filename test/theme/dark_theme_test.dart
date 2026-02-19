import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/theme/app_theme.dart';

void main() {
  group('Dark theme tokens', () {
    test('dark design token colors match spec', () {
      expect(AppColors.bgDark, const Color(0xFF0D1117));
      expect(AppColors.cardDark, const Color(0xFF161B22));
      expect(AppColors.surfaceDark, const Color(0xFF21262D));
      expect(AppColors.darkDivider, const Color(0xFF30363D));
      expect(AppColors.darkTextPrimary, const Color(0xFFF0F6FC));
      expect(AppColors.darkTextSecondary, const Color(0xFF8B949E));
    });

    test('dark theme maps tokens to scaffold/card/text/dividers', () {
      final theme = AppTheme.dark();

      expect(theme.scaffoldBackgroundColor, AppColors.bgDark);
      expect(theme.cardColor, AppColors.cardDark);
      expect(theme.dividerColor, AppColors.darkDivider);
      expect(theme.colorScheme.onSurface, AppColors.darkTextPrimary);
      expect(theme.colorScheme.onSurfaceVariant, AppColors.darkTextSecondary);
      expect(
        theme.bottomNavigationBarTheme.unselectedItemColor,
        AppColors.darkTextSecondary,
      );
      expect(theme.inputDecorationTheme.fillColor, AppColors.surfaceDark);
    });
  });
}
