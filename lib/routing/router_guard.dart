import '../models/app_mode.dart';

/// Returns redirect route for an incoming location based on [mode].
///
/// Returns null when navigation is allowed.
String? resolveModeRedirect({
  required AppMode mode,
  required String location,
}) {
  final normalized = location.trim().isEmpty ? '/' : location.trim();

  if (mode == AppMode.unset) {
    return normalized == '/welcome' ? null : '/welcome';
  }

  if (mode == AppMode.child) {
    // Allow parent login from child mode so child setup can bootstrap an
    // authenticated Firebase session before pairing.
    if (normalized.startsWith('/child') || normalized == '/parent/login') {
      return null;
    }
    return '/child/status';
  }

  if (mode == AppMode.parent) {
    return normalized.startsWith('/child') ? '/parent/dashboard' : null;
  }

  return null;
}
