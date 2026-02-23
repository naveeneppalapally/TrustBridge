/// Sanitizes technical/runtime errors into child-friendly language.
class ChildFriendlyErrors {
  /// Converts [technicalError] into a simple, non-technical message.
  static String sanitise(String technicalError) {
    final lower = technicalError.toLowerCase();

    if (lower.contains('permission') ||
        lower.contains('cloud_permission') ||
        lower.contains("doesn't have permission") ||
        lower.contains('does not have permission') ||
        lower.contains('unauthorized') ||
        lower.contains('unauthenticated')) {
      return 'Something needs your parent\'s help.';
    }
    if (lower.contains('nxdomain') || lower.contains('dns')) {
      return 'This site is not available right now.';
    }
    if (lower.contains('vpn') || lower.contains('tunnel')) {
      return 'Protection needs attention - tell your parent.';
    }
    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('socket') ||
        lower.contains('unreachable')) {
      return 'No internet connection.';
    }
    if (lower.contains('timeout')) {
      return 'This is taking too long. Try again.';
    }
    return 'Something went wrong. Try again or ask your parent.';
  }
}
