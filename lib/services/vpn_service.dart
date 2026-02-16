import 'dart:io';

import 'package:flutter/services.dart';

class VpnStatus {
  const VpnStatus({
    required this.supported,
    required this.permissionGranted,
    required this.isRunning,
  });

  const VpnStatus.unsupported()
      : supported = false,
        permissionGranted = false,
        isRunning = false;

  final bool supported;
  final bool permissionGranted;
  final bool isRunning;

  factory VpnStatus.fromChannelMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const VpnStatus.unsupported();
    }
    return VpnStatus(
      supported: map['supported'] == true,
      permissionGranted: map['permissionGranted'] == true,
      isRunning: map['isRunning'] == true,
    );
  }
}

abstract class VpnServiceBase {
  Future<VpnStatus> getStatus();

  Future<bool> hasVpnPermission();

  Future<bool> isVpnRunning();

  Future<bool> requestPermission();

  Future<bool> startVpn({
    List<String> blockedCategories,
    List<String> blockedDomains,
  });

  Future<bool> stopVpn();

  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
  });
}

class VpnService implements VpnServiceBase {
  VpnService({
    MethodChannel? channel,
    bool? forceSupported,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _forceSupported = forceSupported;

  static const String _channelName = 'com.navee.trustbridge/vpn';
  final MethodChannel _channel;
  final bool? _forceSupported;

  bool get _supported => _forceSupported ?? Platform.isAndroid;

  @override
  Future<VpnStatus> getStatus() async {
    if (!_supported) {
      return const VpnStatus.unsupported();
    }

    try {
      final result =
          await _channel.invokeMapMethod<dynamic, dynamic>('getStatus');
      if (result != null) {
        return VpnStatus.fromChannelMap(result);
      }

      final permissionGranted = await hasVpnPermission();
      final running = await isVpnRunning();
      return VpnStatus(
        supported: true,
        permissionGranted: permissionGranted,
        isRunning: running,
      );
    } on PlatformException {
      return const VpnStatus.unsupported();
    } on MissingPluginException {
      return const VpnStatus.unsupported();
    }
  }

  @override
  Future<bool> hasVpnPermission() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('hasVpnPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> isVpnRunning() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('isVpnRunning') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('requestVpnPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> startVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
  }) async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'startVpn',
            {
              'blockedCategories': blockedCategories,
              'blockedDomains': blockedDomains,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> stopVpn() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('stopVpn') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
  }) async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'updateFilterRules',
            {
              'blockedCategories': blockedCategories,
              'blockedDomains': blockedDomains,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
