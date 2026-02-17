import 'dart:io';

import 'package:flutter/services.dart';

class VpnStatus {
  const VpnStatus({
    required this.supported,
    required this.permissionGranted,
    required this.isRunning,
    this.queriesProcessed = 0,
    this.queriesBlocked = 0,
    this.queriesAllowed = 0,
    this.blockedCategoryCount = 0,
    this.blockedDomainCount = 0,
    this.startedAt,
    this.lastRuleUpdateAt,
  });

  const VpnStatus.unsupported()
      : supported = false,
        permissionGranted = false,
        isRunning = false,
        queriesProcessed = 0,
        queriesBlocked = 0,
        queriesAllowed = 0,
        blockedCategoryCount = 0,
        blockedDomainCount = 0,
        startedAt = null,
        lastRuleUpdateAt = null;

  final bool supported;
  final bool permissionGranted;
  final bool isRunning;
  final int queriesProcessed;
  final int queriesBlocked;
  final int queriesAllowed;
  final int blockedCategoryCount;
  final int blockedDomainCount;
  final DateTime? startedAt;
  final DateTime? lastRuleUpdateAt;

  double get blockedRate {
    if (queriesProcessed <= 0) {
      return 0;
    }
    return queriesBlocked / queriesProcessed;
  }

  factory VpnStatus.fromChannelMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const VpnStatus.unsupported();
    }
    return VpnStatus(
      supported: map['supported'] == true,
      permissionGranted: map['permissionGranted'] == true,
      isRunning: map['isRunning'] == true,
      queriesProcessed: _toInt(map['queriesProcessed']),
      queriesBlocked: _toInt(map['queriesBlocked']),
      queriesAllowed: _toInt(map['queriesAllowed']),
      blockedCategoryCount: _toInt(map['blockedCategoryCount']),
      blockedDomainCount: _toInt(map['blockedDomainCount']),
      startedAt: _toDateTime(map['startedAtEpochMs']),
      lastRuleUpdateAt: _toDateTime(map['lastRuleUpdateEpochMs']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  static DateTime? _toDateTime(dynamic value) {
    final epochMs = _toInt(value);
    if (epochMs <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(epochMs);
  }
}

class DnsQueryLogEntry {
  const DnsQueryLogEntry({
    required this.domain,
    required this.blocked,
    required this.timestamp,
  });

  final String domain;
  final bool blocked;
  final DateTime timestamp;

  factory DnsQueryLogEntry.fromMap(Map<dynamic, dynamic> map) {
    final domain = (map['domain'] as String?)?.trim();
    return DnsQueryLogEntry(
      domain: (domain == null || domain.isEmpty) ? '<unknown>' : domain,
      blocked: map['blocked'] == true,
      timestamp: VpnStatus._toDateTime(map['timestampEpochMs']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
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

  Future<bool> isIgnoringBatteryOptimizations();

  Future<bool> openBatteryOptimizationSettings();

  Future<List<DnsQueryLogEntry>> getRecentDnsQueries({int limit = 100});

  Future<bool> clearDnsQueryLogs();
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

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openBatteryOptimizationSettings() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'openBatteryOptimizationSettings',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<DnsQueryLogEntry>> getRecentDnsQueries({int limit = 100}) async {
    if (!_supported) {
      return const [];
    }

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getRecentDnsQueries',
        {'limit': limit},
      );
      if (result == null || result.isEmpty) {
        return const [];
      }

      final entries = <DnsQueryLogEntry>[];
      for (final item in result) {
        if (item is Map) {
          entries.add(DnsQueryLogEntry.fromMap(item));
        }
      }
      return entries;
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<bool> clearDnsQueryLogs() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('clearDnsQueryLogs') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
