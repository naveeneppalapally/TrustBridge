import 'dart:io';

import 'package:flutter/services.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';
import 'package:trustbridge_app/services/performance_service.dart';

class VpnStatus {
  const VpnStatus({
    required this.supported,
    required this.permissionGranted,
    required this.isRunning,
    this.queriesProcessed = 0,
    this.queriesBlocked = 0,
    this.queriesAllowed = 0,
    this.upstreamFailureCount = 0,
    this.fallbackQueryCount = 0,
    this.blockedCategoryCount = 0,
    this.blockedDomainCount = 0,
    this.startedAt,
    this.lastRuleUpdateAt,
    this.upstreamDns,
    this.privateDnsActive = false,
    this.privateDnsMode,
  });

  const VpnStatus.unsupported()
      : supported = false,
        permissionGranted = false,
        isRunning = false,
        queriesProcessed = 0,
        queriesBlocked = 0,
        queriesAllowed = 0,
        upstreamFailureCount = 0,
        fallbackQueryCount = 0,
        blockedCategoryCount = 0,
        blockedDomainCount = 0,
        startedAt = null,
        lastRuleUpdateAt = null,
        upstreamDns = null,
        privateDnsActive = false,
        privateDnsMode = null;

  final bool supported;
  final bool permissionGranted;
  final bool isRunning;
  final int queriesProcessed;
  final int queriesBlocked;
  final int queriesAllowed;
  final int upstreamFailureCount;
  final int fallbackQueryCount;
  final int blockedCategoryCount;
  final int blockedDomainCount;
  final DateTime? startedAt;
  final DateTime? lastRuleUpdateAt;
  final String? upstreamDns;
  final bool privateDnsActive;
  final String? privateDnsMode;

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
      upstreamFailureCount: _toInt(map['upstreamFailureCount']),
      fallbackQueryCount: _toInt(map['fallbackQueryCount']),
      blockedCategoryCount: _toInt(map['blockedCategoryCount']),
      blockedDomainCount: _toInt(map['blockedDomainCount']),
      startedAt: _toDateTime(map['startedAtEpochMs']),
      lastRuleUpdateAt: _toDateTime(map['lastRuleUpdateEpochMs']),
      upstreamDns: _toNullableString(map['upstreamDns']),
      privateDnsActive: map['privateDnsActive'] == true,
      privateDnsMode: _toNullableString(map['privateDnsMode']),
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

  static String? _toNullableString(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }
}

class VpnTelemetry {
  const VpnTelemetry({
    required this.queriesIntercepted,
    required this.queriesBlocked,
    required this.queriesAllowed,
    this.upstreamFailureCount = 0,
    this.fallbackQueryCount = 0,
    this.activeUpstreamDns,
    required this.isRunning,
  });

  final int queriesIntercepted;
  final int queriesBlocked;
  final int queriesAllowed;
  final int upstreamFailureCount;
  final int fallbackQueryCount;
  final String? activeUpstreamDns;
  final bool isRunning;

  factory VpnTelemetry.empty() {
    return const VpnTelemetry(
      queriesIntercepted: 0,
      queriesBlocked: 0,
      queriesAllowed: 0,
      isRunning: false,
    );
  }

  factory VpnTelemetry.fromMap(Map<String, dynamic> map) {
    return VpnTelemetry(
      queriesIntercepted: _readInt(map['queriesIntercepted']),
      queriesBlocked: _readInt(map['queriesBlocked']),
      queriesAllowed: _readInt(map['queriesAllowed']),
      upstreamFailureCount: _readInt(map['upstreamFailureCount']),
      fallbackQueryCount: _readInt(map['fallbackQueryCount']),
      activeUpstreamDns: _readNullableString(map['activeUpstreamDns']),
      isRunning: map['isRunning'] == true,
    );
  }

  factory VpnTelemetry.fromStatus(VpnStatus status) {
    return VpnTelemetry(
      queriesIntercepted: status.queriesProcessed,
      queriesBlocked: status.queriesBlocked,
      queriesAllowed: status.queriesAllowed,
      upstreamFailureCount: status.upstreamFailureCount,
      fallbackQueryCount: status.fallbackQueryCount,
      activeUpstreamDns: status.upstreamDns,
      isRunning: status.isRunning,
    );
  }

  double get blockRate {
    if (queriesIntercepted <= 0) {
      return 0;
    }
    return queriesBlocked / queriesIntercepted;
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  static String? _readNullableString(dynamic value) {
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
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

class RuleCacheSnapshot {
  const RuleCacheSnapshot({
    required this.categoryCount,
    required this.domainCount,
    required this.sampleCategories,
    required this.sampleDomains,
    this.lastUpdatedAt,
  });

  const RuleCacheSnapshot.empty()
      : categoryCount = 0,
        domainCount = 0,
        sampleCategories = const [],
        sampleDomains = const [],
        lastUpdatedAt = null;

  final int categoryCount;
  final int domainCount;
  final List<String> sampleCategories;
  final List<String> sampleDomains;
  final DateTime? lastUpdatedAt;

  factory RuleCacheSnapshot.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const RuleCacheSnapshot.empty();
    }
    return RuleCacheSnapshot(
      categoryCount: VpnStatus._toInt(map['categoryCount']),
      domainCount: VpnStatus._toInt(map['domainCount']),
      sampleCategories: _toStringList(map['sampleCategories'])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      sampleDomains: _toStringList(map['sampleDomains'])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      lastUpdatedAt: VpnStatus._toDateTime(map['lastUpdatedAtEpochMs']),
    );
  }

  static List<String> _toStringList(dynamic raw) {
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return const [];
  }
}

class DomainPolicyEvaluation {
  const DomainPolicyEvaluation({
    required this.inputDomain,
    required this.normalizedDomain,
    required this.blocked,
    this.matchedRule,
  });

  const DomainPolicyEvaluation.empty()
      : inputDomain = '',
        normalizedDomain = '',
        blocked = false,
        matchedRule = null;

  final String inputDomain;
  final String normalizedDomain;
  final bool blocked;
  final String? matchedRule;

  factory DomainPolicyEvaluation.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const DomainPolicyEvaluation.empty();
    }
    return DomainPolicyEvaluation(
      inputDomain: (map['inputDomain'] as String?)?.trim() ?? '',
      normalizedDomain: (map['normalizedDomain'] as String?)?.trim() ?? '',
      blocked: map['blocked'] == true,
      matchedRule: (map['matchedRule'] as String?)?.trim(),
    );
  }
}

class BlockedDomainEvent {
  const BlockedDomainEvent({
    required this.domain,
    required this.modeName,
    this.remainingLabel,
  });

  final String domain;
  final String modeName;
  final String? remainingLabel;

  factory BlockedDomainEvent.fromMap(Map<dynamic, dynamic> map) {
    final domain = (map['domain'] as String?)?.trim();
    final modeName = (map['modeName'] as String?)?.trim();
    final remaining = (map['remainingLabel'] as String?)?.trim();
    return BlockedDomainEvent(
      domain: (domain == null || domain.isEmpty) ? 'blocked domain' : domain,
      modeName:
          (modeName == null || modeName.isEmpty) ? 'Focus Mode' : modeName,
      remainingLabel:
          (remaining == null || remaining.isEmpty) ? null : remaining,
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
    List<String> temporaryAllowedDomains,
    String? parentId,
    String? childId,
    String? upstreamDns,
  });

  Future<bool> restartVpn({
    List<String> blockedCategories,
    List<String> blockedDomains,
    List<String> temporaryAllowedDomains,
    String? parentId,
    String? childId,
    String? upstreamDns,
  });

  Future<bool> stopVpn();

  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    List<String> temporaryAllowedDomains = const [],
    String? parentId,
    String? childId,
  });

  Future<bool> setUpstreamDns({String? upstreamDns});

  Future<bool> isIgnoringBatteryOptimizations();

  Future<bool> openBatteryOptimizationSettings();

  Future<bool> openVpnSettings();

  Future<bool> openPrivateDnsSettings();

  Future<List<DnsQueryLogEntry>> getRecentDnsQueries({int limit = 100});

  Future<bool> clearDnsQueryLogs();

  Future<RuleCacheSnapshot> getRuleCacheSnapshot({int sampleLimit = 5});

  Future<bool> clearRuleCache();

  Future<DomainPolicyEvaluation> evaluateDomainPolicy(String domain);
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
  final CrashlyticsService _crashlyticsService = CrashlyticsService();
  final PerformanceService _performanceService = PerformanceService();
  Future<dynamic> Function(MethodCall call)? _blockedHandler;

  bool get _supported => _forceSupported ?? Platform.isAndroid;

  void setBlockedDomainListener(
    void Function(BlockedDomainEvent event)? listener,
  ) {
    if (!_supported) {
      return;
    }

    if (listener == null) {
      _blockedHandler = null;
      _channel.setMethodCallHandler(null);
      return;
    }

    _blockedHandler = (MethodCall call) async {
      if (call.method != 'onDomainBlocked' &&
          call.method != 'onBlockedDomain') {
        return null;
      }
      final args = call.arguments;
      if (args is Map) {
        listener(BlockedDomainEvent.fromMap(args));
      }
      return null;
    };
    _channel.setMethodCallHandler(_blockedHandler);
  }

  Future<VpnTelemetry> getVpnTelemetry() async {
    if (!_supported) {
      return VpnTelemetry.empty();
    }
    try {
      final result =
          await _channel.invokeMapMethod<dynamic, dynamic>('getStatus');
      if (result != null) {
        return VpnTelemetry.fromMap(<String, dynamic>{
          'queriesIntercepted': VpnStatus._toInt(result['queriesProcessed']),
          'queriesBlocked': VpnStatus._toInt(result['queriesBlocked']),
          'queriesAllowed': VpnStatus._toInt(result['queriesAllowed']),
          'upstreamFailureCount':
              VpnStatus._toInt(result['upstreamFailureCount']),
          'fallbackQueryCount': VpnStatus._toInt(result['fallbackQueryCount']),
          'activeUpstreamDns': VpnStatus._toNullableString(
            result['upstreamDns'],
          ),
          'isRunning': result['isRunning'] == true,
        });
      }
      final status = await getStatus();
      return VpnTelemetry.fromStatus(status);
    } on PlatformException {
      return VpnTelemetry.empty();
    } on MissingPluginException {
      return VpnTelemetry.empty();
    }
  }

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
    List<String> temporaryAllowedDomains = const [],
    String? parentId,
    String? childId,
    String? upstreamDns,
  }) async {
    if (!_supported) {
      return false;
    }

    final trace = await _performanceService.startTrace('vpn_start');
    final stopwatch = Stopwatch()..start();
    try {
      final started = await _channel.invokeMethod<bool>(
            'startVpn',
            {
              'blockedCategories': blockedCategories,
              'blockedDomains': blockedDomains,
              'temporaryAllowedDomains': temporaryAllowedDomains,
              if (parentId != null && parentId.trim().isNotEmpty)
                'parentId': parentId.trim(),
              if (childId != null && childId.trim().isNotEmpty)
                'childId': childId.trim(),
              if (upstreamDns != null && upstreamDns.trim().isNotEmpty)
                'upstreamDns': upstreamDns.trim(),
            },
          ) ??
          false;
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.setMetric(
        trace,
        'blocked_categories',
        blockedCategories.length,
      );
      await _performanceService.setMetric(
        trace,
        'blocked_domains',
        blockedDomains.length,
      );
      await _performanceService.setMetric(
        trace,
        'temporary_allowed_domains',
        temporaryAllowedDomains.length,
      );
      await _performanceService.setMetric(trace, 'started', started ? 1 : 0);
      await _performanceService.annotateThreshold(
        trace: trace,
        name: 'vpn_start_ms',
        actualValue: stopwatch.elapsedMilliseconds,
        warningValue: PerformanceThresholds.vpnStartWarningMs,
      );
      await _performanceService.setAttribute(
        trace,
        'upstream_dns',
        (upstreamDns ?? '').trim().isEmpty ? 'default' : 'custom',
      );
      await _crashlyticsService.setCustomKeys({
        'vpn_status': started ? 'running' : 'stopped',
        'vpn_upstream_dns': (upstreamDns ?? '').trim().isEmpty
            ? 'default'
            : upstreamDns!.trim(),
      });
      await _crashlyticsService.log(
        started ? 'VPN started successfully' : 'VPN start returned false',
      );
      return started;
    } on PlatformException catch (error, stackTrace) {
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.setMetric(trace, 'platform_exception', 1);
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'Failed to start VPN',
      );
      await _crashlyticsService.setCustomKey('vpn_status', 'start_failed');
      return false;
    } on MissingPluginException catch (error, stackTrace) {
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.setMetric(trace, 'plugin_missing', 1);
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'VPN plugin missing while starting',
      );
      await _crashlyticsService.setCustomKey('vpn_status', 'plugin_missing');
      return false;
    } finally {
      await _performanceService.stopTrace(trace);
    }
  }

  @override
  Future<bool> stopVpn() async {
    if (!_supported) {
      return false;
    }

    final trace = await _performanceService.startTrace('vpn_stop');
    final stopwatch = Stopwatch()..start();
    try {
      final stopped = await _channel.invokeMethod<bool>('stopVpn') ?? false;
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.setMetric(trace, 'stopped', stopped ? 1 : 0);
      await _performanceService.annotateThreshold(
        trace: trace,
        name: 'vpn_stop_ms',
        actualValue: stopwatch.elapsedMilliseconds,
        warningValue: PerformanceThresholds.vpnStopWarningMs,
      );
      await _crashlyticsService.setCustomKey(
        'vpn_status',
        stopped ? 'stopped' : 'running',
      );
      await _crashlyticsService.log(
        stopped ? 'VPN stopped successfully' : 'VPN stop returned false',
      );
      return stopped;
    } on PlatformException catch (error, stackTrace) {
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.setMetric(trace, 'platform_exception', 1);
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'Failed to stop VPN',
      );
      await _crashlyticsService.setCustomKey('vpn_status', 'stop_failed');
      return false;
    } on MissingPluginException catch (error, stackTrace) {
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.setMetric(trace, 'plugin_missing', 1);
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'VPN plugin missing while stopping',
      );
      await _crashlyticsService.setCustomKey('vpn_status', 'plugin_missing');
      return false;
    } finally {
      await _performanceService.stopTrace(trace);
    }
  }

  @override
  Future<bool> restartVpn({
    List<String> blockedCategories = const [],
    List<String> blockedDomains = const [],
    List<String> temporaryAllowedDomains = const [],
    String? parentId,
    String? childId,
    String? upstreamDns,
  }) async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'restartVpn',
            {
              'blockedCategories': blockedCategories,
              'blockedDomains': blockedDomains,
              'temporaryAllowedDomains': temporaryAllowedDomains,
              if (parentId != null && parentId.trim().isNotEmpty)
                'parentId': parentId.trim(),
              if (childId != null && childId.trim().isNotEmpty)
                'childId': childId.trim(),
              if (upstreamDns != null && upstreamDns.trim().isNotEmpty)
                'upstreamDns': upstreamDns.trim(),
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
  Future<bool> updateFilterRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    List<String> temporaryAllowedDomains = const [],
    String? parentId,
    String? childId,
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
              'temporaryAllowedDomains': temporaryAllowedDomains,
              if (parentId != null && parentId.trim().isNotEmpty)
                'parentId': parentId.trim(),
              if (childId != null && childId.trim().isNotEmpty)
                'childId': childId.trim(),
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
  Future<bool> setUpstreamDns({String? upstreamDns}) async {
    if (!_supported) {
      return false;
    }

    try {
      final payload = <String, dynamic>{};
      final normalized = upstreamDns?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        payload['upstreamDns'] = normalized;
      }
      return await _channel.invokeMethod<bool>('setUpstreamDns', payload) ??
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
  Future<bool> openVpnSettings() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('openVpnSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openPrivateDnsSettings() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('openPrivateDnsSettings') ??
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

  @override
  Future<RuleCacheSnapshot> getRuleCacheSnapshot({int sampleLimit = 5}) async {
    if (!_supported) {
      return const RuleCacheSnapshot.empty();
    }

    try {
      final map = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getRuleCacheSnapshot',
        {'sampleLimit': sampleLimit},
      );
      return RuleCacheSnapshot.fromMap(map);
    } on PlatformException {
      return const RuleCacheSnapshot.empty();
    } on MissingPluginException {
      return const RuleCacheSnapshot.empty();
    }
  }

  @override
  Future<bool> clearRuleCache() async {
    if (!_supported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('clearRuleCache') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<DomainPolicyEvaluation> evaluateDomainPolicy(String domain) async {
    if (!_supported) {
      return const DomainPolicyEvaluation.empty();
    }

    final normalizedInput = domain.trim();
    if (normalizedInput.isEmpty) {
      return const DomainPolicyEvaluation.empty();
    }

    try {
      final map = await _channel.invokeMapMethod<dynamic, dynamic>(
        'evaluateDomainPolicy',
        {'domain': normalizedInput},
      );
      return DomainPolicyEvaluation.fromMap(map);
    } on PlatformException {
      return const DomainPolicyEvaluation.empty();
    } on MissingPluginException {
      return const DomainPolicyEvaluation.empty();
    }
  }
}
