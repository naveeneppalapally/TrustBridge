import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockService extends ChangeNotifier {
  AppLockService._();

  static final AppLockService _instance = AppLockService._();

  factory AppLockService() => _instance;

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _pinKey = 'trustbridge_parent_pin';
  static const String _enabledKey = 'trustbridge_pin_enabled';
  static const Duration _gracePeriod = Duration(seconds: 60);
  static const int _maxFailedAttempts = 5;
  static const Duration _failedAttemptLockout = Duration(seconds: 30);

  final LocalAuthentication _localAuth = LocalAuthentication();
  DateTime? _lastUnlockedAt;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  Future<bool> isEnabled() async {
    try {
      final value = await _storage.read(key: _enabledKey);
      return value == 'true';
    } catch (error) {
      debugPrint('[AppLock] Failed reading enabled flag: $error');
      return false;
    }
  }

  Future<bool> hasPin() async {
    try {
      final pin = await _storage.read(key: _pinKey);
      return pin != null && pin.isNotEmpty;
    } catch (error) {
      debugPrint('[AppLock] Failed reading PIN value: $error');
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    if (pin.length != 4 || int.tryParse(pin) == null) {
      throw ArgumentError('PIN must be exactly 4 numeric digits.');
    }

    await _storage.write(key: _pinKey, value: pin);
    await _storage.write(key: _enabledKey, value: 'true');
    notifyListeners();
  }

  Future<void> enableLock() async {
    final pinExists = await hasPin();
    if (!pinExists) {
      throw StateError('Cannot enable app lock without a PIN.');
    }
    await _storage.write(key: _enabledKey, value: 'true');
    notifyListeners();
  }

  Future<bool> verifyPin(String enteredPin) async {
    final lockExpiry = _lockedUntil;
    if (lockExpiry != null && lockExpiry.isAfter(DateTime.now())) {
      return false;
    }

    try {
      final storedPin = await _storage.read(key: _pinKey);
      final isMatch = storedPin != null && storedPin == enteredPin;
      if (isMatch) {
        _failedAttempts = 0;
        _lockedUntil = null;
        markUnlocked();
      } else {
        _failedAttempts += 1;
        if (_failedAttempts >= _maxFailedAttempts) {
          _failedAttempts = 0;
          _lockedUntil = DateTime.now().add(_failedAttemptLockout);
        }
      }
      return isMatch;
    } catch (error) {
      debugPrint('[AppLock] Failed verifying PIN: $error');
      return false;
    }
  }

  Future<void> disableLock() async {
    await _storage.write(key: _enabledKey, value: 'false');
    _lastUnlockedAt = null;
    _failedAttempts = 0;
    _lockedUntil = null;
    notifyListeners();
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
    await _storage.write(key: _enabledKey, value: 'false');
    _lastUnlockedAt = null;
    _failedAttempts = 0;
    _lockedUntil = null;
    notifyListeners();
  }

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

  bool get isTemporarilyLocked {
    final lockExpiry = _lockedUntil;
    return lockExpiry != null && lockExpiry.isAfter(DateTime.now());
  }

  Duration? get remainingLockDuration {
    final lockExpiry = _lockedUntil;
    if (lockExpiry == null) {
      return null;
    }
    final remaining = lockExpiry.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      return null;
    }
    return remaining;
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
      debugPrint('[AppLock] Biometric capability check failed: $error');
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
      debugPrint('[AppLock] Biometric authentication failed: $error');
      return false;
    }
  }
}
