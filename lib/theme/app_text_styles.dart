import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  AppTextStyles._();

  static bool get _isFlutterTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static TextTheme textTheme(Brightness brightness) {
    final isFlutterTest = _isFlutterTest;
    final base = ThemeData(brightness: brightness).textTheme;
    final inter = isFlutterTest ? base : GoogleFonts.interTextTheme(base);

    return inter.copyWith(
      displayLarge: _interStyle(
        isFlutterTest: isFlutterTest,
        baseStyle: inter.displayLarge,
        fontSize: 32,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: _interStyle(
        isFlutterTest: isFlutterTest,
        baseStyle: inter.headlineMedium,
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: _interStyle(
        isFlutterTest: isFlutterTest,
        baseStyle: inter.bodyMedium,
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  static TextStyle _interStyle({
    required bool isFlutterTest,
    required TextStyle? baseStyle,
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
  }) {
    if (isFlutterTest) {
      return (baseStyle ?? const TextStyle()).copyWith(
        fontFamily: 'Inter',
        fontSize: fontSize,
        height: height,
        fontWeight: fontWeight,
      );
    }

    return GoogleFonts.inter(
      textStyle: baseStyle,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
    );
  }

  static TextStyle headingLarge({Color? color}) {
    return _style(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: color,
    );
  }

  static TextStyle headingMedium({Color? color}) {
    return _style(
      fontSize: 18,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: color,
    );
  }

  static TextStyle displayMedium({Color? color}) {
    return _style(
      fontSize: 28,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: color,
    );
  }

  static TextStyle body({Color? color}) {
    return _style(
      fontSize: 16,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: color,
    );
  }

  static TextStyle bodySmall({Color? color}) {
    return _style(
      fontSize: 14,
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: color,
    );
  }

  static TextStyle label({Color? color}) {
    return _style(
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: color,
      letterSpacing: 0.1,
    );
  }

  static TextStyle labelCaps({Color? color}) {
    return _style(
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: 1.0,
    );
  }

  static TextStyle _style({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    if (_isFlutterTest) {
      return TextStyle(
        fontFamily: 'Inter',
        fontSize: fontSize,
        height: height,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      );
    }

    return GoogleFonts.inter(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }
}
