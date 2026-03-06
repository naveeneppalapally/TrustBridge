import 'package:flutter/material.dart';

/// Responsive utility — call `R.init(context)` at the top of every build.
class R {
  static late MediaQueryData _mq;

  static void init(BuildContext context) => _mq = MediaQuery.of(context);

  static double get w => _mq.size.width;
  static double get h => _mq.size.height;
  static double get safeTop => _mq.padding.top;
  static double get safeBottom => _mq.padding.bottom;

  /// Fluid font scale — never fixed px. Base width 390.
  static double fs(double size) => size * (w / 390).clamp(0.8, 1.3);

  /// Fluid spacing.
  static double sp(double size) => size * (w / 390).clamp(0.85, 1.2);

  /// Is this a small phone (under 360px wide — old Redmi, Nokia budget)
  static bool get isSmall => w < 360;

  /// Is this a large phone or tablet (over 420px)
  static bool get isLarge => w > 420;

  /// Is this a tablet (over 600px)
  static bool get isTablet => w > 600;
}
