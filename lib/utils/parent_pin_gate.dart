import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';
import '../widgets/pin_entry_dialog.dart';

/// Requires parent PIN before sensitive actions when app lock is enabled.
Future<bool> requireParentPin(BuildContext context) async {
  final appLockService = AppLockService();

  final enabled = await appLockService.isEnabled();
  if (!enabled) {
    return true;
  }

  if (appLockService.isWithinGracePeriod) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  final unlocked = await showPinEntryDialog(context);
  if (unlocked) {
    appLockService.markUnlocked();
  }
  return unlocked;
}
