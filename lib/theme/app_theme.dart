import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_text_styles.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF207CF8);
  static const Color bgLight = Color(0xFFF0F4F8);
  static const Color bgDark = Color(0xFF0D1117);
  static const Color surfaceDark = Color(0xFF21262D);
  static const Color success = Color(0xFF68B901);
  static const Color error = Color(0xFFF41F5C);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Color(0xFF161B22);
  static const Color navUnselected = Color(0xFF8B95A3);
  static const Color darkDivider = Color(0xFF30363D);
  static const Color darkTextPrimary = Color(0xFFF0F6FC);
  static const Color darkTextSecondary = Color(0xFF8B949E);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.primary,
      tertiary: AppColors.success,
      error: AppColors.error,
      surface: AppColors.cardLight,
    );

    final textTheme = AppTextStyles.textTheme(Brightness.light);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bgLight,
      cardColor: AppColors.cardLight,
      dividerColor: const Color(0xFFD0D7DE),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFD0D7DE),
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.navUnselected,
        backgroundColor: AppColors.cardLight,
        elevation: 8,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.primary,
      tertiary: AppColors.success,
      error: AppColors.error,
      surface: AppColors.cardDark,
      onSurface: AppColors.darkTextPrimary,
      onSurfaceVariant: AppColors.darkTextSecondary,
      outline: AppColors.darkDivider,
    );

    final textTheme = AppTextStyles.textTheme(Brightness.dark).apply(
      bodyColor: AppColors.darkTextPrimary,
      displayColor: AppColors.darkTextPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bgDark,
      cardColor: AppColors.cardDark,
      dividerColor: AppColors.darkDivider,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        backgroundColor: AppColors.bgDark,
        foregroundColor: AppColors.darkTextPrimary,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkDivider,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.darkDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.darkTextSecondary,
        backgroundColor: AppColors.cardDark,
        elevation: 8,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
