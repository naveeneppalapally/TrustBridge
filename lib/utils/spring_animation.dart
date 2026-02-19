import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

class SpringAnimation {
  SpringAnimation._();

  static const double stiffness = 300;
  static const double damping = 20;
  static const Duration standardDuration = Duration(milliseconds: 600);
  static const Curve springCurve = SpringCurve(
    stiffness: stiffness,
    damping: damping,
  );

  static Route<T> slidePageRoute<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: springCurve,
          reverseCurve: Curves.easeInCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.3, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class SpringCurve extends Curve {
  const SpringCurve({
    required this.stiffness,
    required this.damping,
    this.mass = 1,
  });

  final double stiffness;
  final double damping;
  final double mass;

  @override
  double transformInternal(double t) {
    final simulation = SpringSimulation(
      SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
      0,
      1,
      0,
    );
    return simulation.x(t).clamp(0.0, 1.0);
  }
}
