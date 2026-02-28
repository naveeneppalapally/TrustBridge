import 'package:flutter/services.dart';

/// Android Device Admin bridge service.
class DeviceAdminService {
  DeviceAdminService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.navee.trustbridge/device_admin';
  final MethodChannel _channel;

  /// Returns true when Device Admin is active on this device.
  Future<bool> isDeviceAdminActive() async {
    try {
      return await _channel.invokeMethod<bool>('isDeviceAdminActive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns true when TrustBridge is Device Owner on this phone.
  Future<bool> isDeviceOwnerActive() async {
    try {
      return await _channel.invokeMethod<bool>('isDeviceOwnerActive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens Android's Device Admin activation prompt and returns grant result.
  Future<bool> requestDeviceAdmin() async {
    try {
      return await _channel.invokeMethod<bool>('requestDeviceAdmin') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Removes Device Admin if active.
  Future<void> removeDeviceAdmin() async {
    try {
      await _channel.invokeMethod<void>('removeDeviceAdmin');
    } on PlatformException {
      // Best-effort operation.
    } on MissingPluginException {
      // Best-effort operation.
    }
  }

  /// Returns current protection-tier status values from Android.
  Future<Map<String, dynamic>> getMaximumProtectionStatus() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('getMaximumProtectionStatus');
      return raw ?? const <String, dynamic>{};
    } on PlatformException {
      return const <String, dynamic>{};
    } on MissingPluginException {
      return const <String, dynamic>{};
    }
  }

  /// Applies device-owner-only hardening policies (always-on VPN, lockdown, uninstall block).
  Future<Map<String, dynamic>> applyMaximumProtectionPolicies() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('applyMaximumProtectionPolicies');
      return raw ?? const <String, dynamic>{};
    } on PlatformException {
      return const <String, dynamic>{
        'success': false,
        'message': 'Could not apply maximum protection on this device.',
      };
    } on MissingPluginException {
      return const <String, dynamic>{
        'success': false,
        'message': 'Could not apply maximum protection on this device.',
      };
    }
  }

  /// Returns the exact ADB command needed for Device Owner setup.
  Future<String> getDeviceOwnerSetupCommand() async {
    try {
      final value =
          await _channel.invokeMethod<String>('getDeviceOwnerSetupCommand');
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) {
        return _defaultDeviceOwnerCommand;
      }
      return normalized;
    } on PlatformException {
      return _defaultDeviceOwnerCommand;
    } on MissingPluginException {
      return _defaultDeviceOwnerCommand;
    }
  }

  /// Reads Android Private DNS mode for bypass monitoring.
  Future<String?> getPrivateDnsMode() async {
    try {
      final value = await _channel.invokeMethod<String>('getPrivateDnsMode');
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) {
        return null;
      }
      return normalized;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static const String _defaultDeviceOwnerCommand =
      'adb shell dpm set-device-owner '
      'com.navee.trustbridge/.TrustBridgeAdminReceiver';
}
