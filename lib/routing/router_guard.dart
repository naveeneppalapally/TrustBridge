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
    return normalized.startsWith('/child') ? null : '/child/status';
  }

  if (mode == AppMode.parent) {
    return normalized.startsWith('/child') ? '/parent/dashboard' : null;
  }

  return null;
}
