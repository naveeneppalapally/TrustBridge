import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/app_mode.dart';
import 'package:trustbridge_app/routing/router_guard.dart';

void main() {
  group('Child mode access restrictions', () {
    test('cannot navigate to /parent/dashboard in child mode', () {
      final redirect = resolveModeRedirect(
        mode: AppMode.child,
        location: '/parent/dashboard',
      );
      expect(redirect, '/child/status');
    });

    test('cannot navigate to /parent/settings in child mode', () {
      final redirect = resolveModeRedirect(
        mode: AppMode.child,
        location: '/parent/settings',
      );
      expect(redirect, '/child/status');
    });

    test('advanced/security routes are blocked in child mode', () {
      final advancedRedirect = resolveModeRedirect(
        mode: AppMode.child,
        location: '/parent/protection/advanced',
      );
      final securityRedirect = resolveModeRedirect(
        mode: AppMode.child,
        location: '/parent/security',
      );

      expect(advancedRedirect, '/child/status');
      expect(securityRedirect, '/child/status');
    });

    test('child mode can only access /child/* locations', () {
      const parentLikeRoutes = <String>[
        '/settings',
        '/dashboard',
        '/parent/protection',
        '/parent/help',
      ];

      for (final route in parentLikeRoutes) {
        final redirect = resolveModeRedirect(
          mode: AppMode.child,
          location: route,
        );
        expect(redirect, '/child/status');
      }
    });
  });
}
