import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Calm Guardian Design System — Color Tokens
// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Backgrounds — warm dark, not cold black
  static const Color bg = Color(0xFF0F0F0F);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceRaised = Color(0xFF222222);
  static const Color surfaceBorder = Color(0xFF2E2E2E);

  // Primary — sage green, calm and trustworthy
  static const Color primary = Color(0xFF7CB987);
  static const Color primaryDim = Color(0x207CB987); // 12%
  static const Color primaryGlow = Color(0x407CB987); // 25%

  // Semantic
  static const Color success = Color(0xFF7CB987);
  static const Color danger = Color(0xFFE07070);
  static const Color warning = Color(0xFFD4A853);
  static const Color successDim = Color(0x207CB987);
  static const Color dangerDim = Color(0x15E07070);
  static const Color warningDim = Color(0x20D4A853);

  // Text
  static const Color textPrimary = Color(0xFFF5F0EB);
  static const Color textSecondary = Color(0xFF8A8580);
  static const Color textMuted = Color(0xFF4A4845);

  // Special
  static const Color gold = Color(0xFFD4A853);

  // ── Legacy aliases used by existing code (map to new tokens) ──
  static const Color bgLight = Color(0xFFF0F4F8);
  static const Color bgDark = bg;
  static const Color surfaceDark = surfaceRaised;
  static const Color error = danger;
  static const Color cardLight = Colors.white;
  static const Color cardDark = surface;
  static const Color navUnselected = textMuted;
  static const Color darkDivider = surfaceBorder;
  static const Color darkTextPrimary = textPrimary;
  static const Color darkTextSecondary = textSecondary;
}

// ─────────────────────────────────────────────────────────────────────────────
// Spacing & Radius
// ─────────────────────────────────────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _CalmSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: _CalmSlidePageTransitionsBuilder(),
          TargetPlatform.macOS: _CalmSlidePageTransitionsBuilder(),
          TargetPlatform.windows: _CalmSlidePageTransitionsBuilder(),
          TargetPlatform.linux: _CalmSlidePageTransitionsBuilder(),
        },
      );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.primary,
      tertiary: AppColors.success,
      error: AppColors.danger,
      surface: AppColors.cardLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bgLight,
      cardColor: AppColors.cardLight,
      dividerColor: const Color(0xFFD0D7DE),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFD0D7DE),
        space: 1,
        thickness: 0.5,
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
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryDim;
          }
          return AppColors.surfaceBorder;
        }),
      ),
      pageTransitionsTheme: _pageTransitionsTheme,
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
      error: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.surfaceBorder,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      cardColor: AppColors.surface,
      dividerColor: AppColors.surfaceBorder,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceBorder,
        space: 1,
        thickness: 0.5,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: UnderlineInputBorder(
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
          borderRadius: BorderRadius.circular(0),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        backgroundColor: AppColors.surface,
        elevation: 0,
        showSelectedLabels: false,
        showUnselectedLabels: false,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryGlow;
          }
          return AppColors.surfaceBorder;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      pageTransitionsTheme: _pageTransitionsTheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page Transition — vertical slide from bottom 30px + fade, 280ms ease-out
// ─────────────────────────────────────────────────────────────────────────────

class _CalmSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _CalmSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.05), // ~30px on standard screen
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);
}
