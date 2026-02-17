import 'package:flutter/material.dart';
import 'package:trustbridge_app/services/app_lock_service.dart';
import 'package:trustbridge_app/widgets/pin_entry_dialog.dart';

Future<void> guardedNavigate(
  BuildContext context,
  Future<void> Function() navigate,
) async {
  if (WidgetsBinding.instance is! WidgetsFlutterBinding) {
    await navigate();
    return;
  }

  final appLockService = AppLockService();
  final isEnabled = await appLockService.isEnabled();

  if (!isEnabled || appLockService.isWithinGracePeriod) {
    await navigate();
    return;
  }

  if (!context.mounted) {
    return;
  }

  final unlocked = await showPinEntryDialog(context);
  if (unlocked && context.mounted) {
    await navigate();
  }
}
