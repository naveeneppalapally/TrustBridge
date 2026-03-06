import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/theme/app_theme.dart';

void main() {
  group('Dark theme tokens', () {
    test('dark design token colors match spec', () {
      // Warm dark palette (updated for Calm Guardian redesign)
      expect(AppColors.bg, const Color(0xFF0F0F0F));
      expect(AppColors.surface, const Color(0xFF1A1A1A));
      expect(AppColors.surfaceRaised, const Color(0xFF222222));
      expect(AppColors.surfaceBorder, const Color(0xFF2E2E2E));
      expect(AppColors.textPrimary, const Color(0xFFF5F0EB));
      expect(AppColors.textSecondary, const Color(0xFF8A8580));
    });

    test('legacy aliases map to new tokens', () {
      expect(AppColors.bgDark, AppColors.bg);
      expect(AppColors.cardDark, AppColors.surface);
      expect(AppColors.surfaceDark, AppColors.surfaceRaised);
      expect(AppColors.darkDivider, AppColors.surfaceBorder);
      expect(AppColors.darkTextPrimary, AppColors.textPrimary);
      expect(AppColors.darkTextSecondary, AppColors.textSecondary);
    });

    test('dark theme maps tokens to scaffold/card/text/dividers', () {
      final theme = AppTheme.dark();

      expect(theme.scaffoldBackgroundColor, AppColors.bg);
      expect(theme.cardColor, AppColors.surface);
      expect(theme.dividerColor, AppColors.surfaceBorder);
      expect(theme.colorScheme.onSurface, AppColors.textPrimary);
      expect(theme.colorScheme.onSurfaceVariant, AppColors.textSecondary);
      expect(
        theme.bottomNavigationBarTheme.unselectedItemColor,
        AppColors.textMuted,
      );
    });
  });
}
