import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_mode.dart';

/// Persists and resolves app role mode (parent/child/unset).
class AppModeService {
  AppModeService._({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _key = 'app_mode';
  static AppModeService _instance = AppModeService._();

  final FlutterSecureStorage _secureStorage;
  AppMode _cachedMode = AppMode.unset;
  bool _isCachePrimed = false;

  /// Returns shared singleton instance.
  factory AppModeService({
    FlutterSecureStorage? secureStorage,
  }) {
    if (secureStorage == null) {
      return _instance;
    }
    return AppModeService._(secureStorage: secureStorage);
  }

  /// Returns currently cached mode synchronously.
  AppMode get cachedMode => _cachedMode;

  /// Ensures cache is loaded at least once.
  Future<void> primeCache() async {
    if (_isCachePrimed) {
      return;
    }
    await getMode();
  }

  /// Reads stored mode from secure storage.
  Future<AppMode> getMode() async {
    final raw = (await _secureStorage.read(key: _key))?.trim().toLowerCase();
    _cachedMode = _parse(raw);
    _isCachePrimed = true;
    return _cachedMode;
  }

  /// Persists mode to secure storage.
  Future<void> setMode(AppMode mode) async {
    if (mode == AppMode.unset) {
      await clearMode();
      return;
    }
    await _secureStorage.write(key: _key, value: mode.name);
    _cachedMode = mode;
    _isCachePrimed = true;
  }

  /// Clears stored mode.
  Future<void> clearMode() async {
    await _secureStorage.delete(key: _key);
    _cachedMode = AppMode.unset;
    _isCachePrimed = true;
  }

  AppMode _parse(String? value) {
    if (value == AppMode.parent.name) {
      return AppMode.parent;
    }
    if (value == AppMode.child.name) {
      return AppMode.child;
    }
    return AppMode.unset;
  }

  /// Overrides singleton for tests.
  static void replaceSingletonForTest(AppModeService service) {
    _instance = service;
  }
}
