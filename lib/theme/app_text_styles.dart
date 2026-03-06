import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Calm Guardian Typography — Fraunces (display) + Plus Jakarta Sans (body)
// ─────────────────────────────────────────────────────────────────────────────

class AppTextStyles {
  AppTextStyles._();

  static bool get _isFlutterTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  // ── Display: Fraunces ──

  /// Hero stat number — Fraunces 56sp w300
  static TextStyle heroNumber({Color? color}) => _fraunces(
        fontSize: 56,
        fontWeight: FontWeight.w300,
        height: 1.1,
        color: color ?? AppColors.textPrimary,
      );

  /// Screen hero text — Fraunces 32sp w400
  static TextStyle displayLarge({Color? color}) => _fraunces(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        height: 1.2,
        color: color ?? AppColors.textPrimary,
      );

  /// Section title — Fraunces 24sp w400
  static TextStyle displayMedium({Color? color}) => _fraunces(
        fontSize: 24,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: color ?? AppColors.textPrimary,
      );

  // ── Body: Plus Jakarta Sans ──

  /// Large heading — Plus Jakarta Sans 18sp w600
  static TextStyle headingLarge({Color? color}) => _jakarta(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color ?? AppColors.textPrimary,
      );

  /// Medium heading — Plus Jakarta Sans 15sp w600
  static TextStyle headingMedium({Color? color}) => _jakarta(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: color ?? AppColors.textPrimary,
      );

  /// Body text — Plus Jakarta Sans 14sp w400
  static TextStyle body({Color? color}) => _jakarta(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? AppColors.textPrimary,
      );

  /// Small body — Plus Jakarta Sans 12sp w400
  static TextStyle bodySmall({Color? color}) => _jakarta(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color ?? AppColors.textSecondary,
      );

  /// Label — Plus Jakarta Sans 11sp w500 letterSpacing 0.8
  static TextStyle label({Color? color}) => _jakarta(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0.8,
        color: color ?? AppColors.textMuted,
      );

  /// Label caps — Plus Jakarta Sans 10sp w600 letterSpacing 1.5 ALL CAPS
  static TextStyle labelCaps({Color? color}) => _jakarta(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 1.5,
        color: color ?? AppColors.textMuted,
      );

  // ── Theme-compatible TextTheme ──

  static TextTheme textTheme(Brightness brightness) {
    final isTest = _isFlutterTest;
    final base = ThemeData(brightness: brightness).textTheme;

    return base.copyWith(
      displayLarge: _buildStyle(
        isTest: isTest,
        base: base.displayLarge,
        fontFamily: 'Fraunces',
        fontSize: 32,
        height: 1.2,
        fontWeight: FontWeight.w400,
      ),
      headlineMedium: _buildStyle(
        isTest: isTest,
        base: base.headlineMedium,
        fontFamily: 'PlusJakartaSans',
        fontSize: 24,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: _buildStyle(
        isTest: isTest,
        base: base.titleLarge,
        fontFamily: 'PlusJakartaSans',
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: _buildStyle(
        isTest: isTest,
        base: base.titleMedium,
        fontFamily: 'PlusJakartaSans',
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: _buildStyle(
        isTest: isTest,
        base: base.bodyLarge,
        fontFamily: 'PlusJakartaSans',
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: _buildStyle(
        isTest: isTest,
        base: base.bodyMedium,
        fontFamily: 'PlusJakartaSans',
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: _buildStyle(
        isTest: isTest,
        base: base.bodySmall,
        fontFamily: 'PlusJakartaSans',
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: _buildStyle(
        isTest: isTest,
        base: base.labelLarge,
        fontFamily: 'PlusJakartaSans',
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: _buildStyle(
        isTest: isTest,
        base: base.labelSmall,
        fontFamily: 'PlusJakartaSans',
        fontSize: 10,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }

  // ── Private helpers ──

  static TextStyle _fraunces({
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
    required Color color,
    double letterSpacing = 0,
  }) {
    if (_isFlutterTest) {
      return TextStyle(
        fontFamily: 'Fraunces',
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
    }
    return GoogleFonts.fraunces(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  static TextStyle _jakarta({
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
    required Color color,
    double letterSpacing = 0,
  }) {
    if (_isFlutterTest) {
      return TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
    }
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  static TextStyle _buildStyle({
    required bool isTest,
    required TextStyle? base,
    required String fontFamily,
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) {
    if (isTest) {
      return (base ?? const TextStyle()).copyWith(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: height,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
      );
    }

    final googleStyle = fontFamily == 'Fraunces'
        ? GoogleFonts.fraunces(
            textStyle: base,
            fontSize: fontSize,
            height: height,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
          )
        : GoogleFonts.plusJakartaSans(
            textStyle: base,
            fontSize: fontSize,
            height: height,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
          );
    return googleStyle;
  }
}
