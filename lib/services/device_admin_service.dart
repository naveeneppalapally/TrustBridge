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
}
