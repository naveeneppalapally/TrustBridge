import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextTheme textTheme(Brightness brightness) {
    final isFlutterTest =
        !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
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
}
