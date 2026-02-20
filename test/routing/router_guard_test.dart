import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/app_mode.dart';
import 'package:trustbridge_app/routing/router_guard.dart';

void main() {
  group('Mode redirect guard', () {
    test('unset mode redirects any route to /welcome', () {
      expect(
        resolveModeRedirect(mode: AppMode.unset, location: '/parent/dashboard'),
        '/welcome',
      );
    });

    test('child mode redirects parent route to /child/status', () {
      expect(
        resolveModeRedirect(mode: AppMode.child, location: '/parent/dashboard'),
        '/child/status',
      );
    });

    test('child mode allows child route', () {
      expect(
        resolveModeRedirect(mode: AppMode.child, location: '/child/status'),
        isNull,
      );
    });

    test('parent mode redirects child route to /parent/dashboard', () {
      expect(
        resolveModeRedirect(mode: AppMode.parent, location: '/child/status'),
        '/parent/dashboard',
      );
    });

    test('parent mode allows parent route', () {
      expect(
        resolveModeRedirect(
            mode: AppMode.parent, location: '/parent/dashboard'),
        isNull,
      );
    });
  });
}
