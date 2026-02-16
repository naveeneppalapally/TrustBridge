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

  Future<bool> requestPermission();

  Future<bool> startVpn();

  Future<bool> stopVpn();
}

class VpnService implements VpnServiceBase {
  VpnService({
    MethodChannel? channel,
    bool? forceSupported,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _forceSupported = forceSupported;

  static const String _channelName = 'trustbridge/vpn';
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
      return VpnStatus.fromChannelMap(result);
    } on PlatformException {
      return const VpnStatus.unsupported();
    } on MissingPluginException {
      return const VpnStatus.unsupported();
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> startVpn() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('startVpn') ?? false;
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
}
