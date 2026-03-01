import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:trustbridge_app/core/utils/app_logger.dart';

class AppLockService extends ChangeNotifier {
  AppLockService._();

  static final AppLockService _instance = AppLockService._();

  factory AppLockService() => _instance;

  static const Duration _gracePeriod = Duration(seconds: 60);

  final LocalAuthentication _localAuth = LocalAuthentication();
  DateTime? _lastUnlockedAt;

  bool get isWithinGracePeriod {
    final unlockedAt = _lastUnlockedAt;
    if (unlockedAt == null) {
      return false;
    }
    return DateTime.now().difference(unlockedAt) < _gracePeriod;
  }

  void markUnlocked() {
    _lastUnlockedAt = DateTime.now();
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!isSupported || !canCheck) {
        return false;
      }
      final enrolled = await _localAuth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (error) {
      AppLogger.debug('[AppLock] Biometric capability check failed: $error');
      return false;
    }
  }

  Future<bool> authenticateWithBiometric() async {
    try {
      final success = await _localAuth.authenticate(
        localizedReason: 'Verify it\'s you to access parent controls',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (success) {
        markUnlocked();
      }
      return success;
    } catch (error) {
      AppLogger.debug('[AppLock] Biometric authentication failed: $error');
      return false;
    }
  }
}
