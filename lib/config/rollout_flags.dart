import 'package:flutter/foundation.dart';

/// Runtime rollout flags for shipping large features safely.
///
/// Defaults are enabled so current behavior remains unchanged. Tests can
/// override individual flags to verify fallback behavior.
class RolloutFlags {
  RolloutFlags._();

  static final Map<String, bool> _testOverrides = <String, bool>{};

  static bool get appInventory => _resolve(
        'app_inventory',
        const bool.fromEnvironment(
          'TB_FLAG_APP_INVENTORY',
          defaultValue: true,
        ),
      );

  static bool get appBlockingPackages => _resolve(
        'app_blocking_packages',
        const bool.fromEnvironment(
          'TB_FLAG_APP_BLOCKING_PACKAGES',
          defaultValue: true,
        ),
      );

  static bool get modeAppOverrides => _resolve(
        'mode_app_overrides',
        const bool.fromEnvironment(
          'TB_FLAG_MODE_APP_OVERRIDES',
          defaultValue: true,
        ),
      );

  static bool get perAppUsageReports => _resolve(
        'per_app_usage_reports',
        const bool.fromEnvironment(
          'TB_FLAG_PER_APP_USAGE_REPORTS',
          defaultValue: true,
        ),
      );

  static bool get adaptiveParentNav => _resolve(
        'adaptive_parent_nav',
        const bool.fromEnvironment(
          'TB_FLAG_ADAPTIVE_PARENT_NAV',
          defaultValue: true,
        ),
      );

  static bool get explicitChildSelection => _resolve(
        'explicit_child_selection',
        const bool.fromEnvironment(
          'TB_FLAG_EXPLICIT_CHILD_SELECTION',
          defaultValue: true,
        ),
      );

  static bool get parentPolicyApplyStatus => _resolve(
        'parent_policy_apply_status',
        const bool.fromEnvironment(
          'TB_FLAG_PARENT_POLICY_APPLY_STATUS',
          defaultValue: true,
        ),
      );

  static bool get parentWebValidationHints => _resolve(
        'parent_web_validation_hints',
        const bool.fromEnvironment(
          'TB_FLAG_PARENT_WEB_VALIDATION_HINTS',
          defaultValue: true,
        ),
      );

  static bool get policySyncTriggerRemoteCommand => _resolve(
        'policy_sync_trigger_remote_command',
        const bool.fromEnvironment(
          'TB_FLAG_POLICY_SYNC_TRIGGER_REMOTE_COMMAND',
          defaultValue: true,
        ),
      );

  static bool _resolve(String key, bool defaultValue) {
    return _testOverrides[key] ?? defaultValue;
  }

  @visibleForTesting
  static void setForTest(String key, bool value) {
    _testOverrides[key] = value;
  }

  @visibleForTesting
  static void resetForTest() {
    _testOverrides.clear();
  }
}
