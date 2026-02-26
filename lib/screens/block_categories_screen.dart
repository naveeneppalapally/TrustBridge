import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trustbridge_app/config/category_ids.dart';
import 'package:trustbridge_app/config/feature_gates.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';
import 'package:trustbridge_app/config/service_definitions.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/content_categories.dart';
import 'package:trustbridge_app/models/installed_app_info.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/screens/upgrade_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/feature_gate_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';
import 'package:trustbridge_app/services/policy_apply_status.dart';
import 'package:trustbridge_app/services/remote_command_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';
import 'package:trustbridge_app/utils/parent_pin_gate.dart';
import 'package:trustbridge_app/widgets/empty_state.dart';

class BlockCategoriesScreen extends StatefulWidget {
  const BlockCategoriesScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.vpnService,
    this.nextDnsApiService,
    this.parentIdOverride,
    this.showAppBar = true,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final VpnServiceBase? vpnService;
  final NextDnsApiService? nextDnsApiService;
  final String? parentIdOverride;
  final bool showAppBar;

  @override
  State<BlockCategoriesScreen> createState() => _BlockCategoriesScreenState();
}

class _BlockCategoriesScreenState extends State<BlockCategoriesScreen> {
  static const Map<String, List<String>> _serviceOrderByCategory =
      <String, List<String>>{
    'social-networks': <String>[
      'instagram',
      'tiktok',
      'facebook',
      'snapchat',
      'twitter',
    ],
    'streaming': <String>['youtube'],
    'games': <String>['roblox'],
    'forums': <String>['reddit'],
    'chat': <String>['whatsapp', 'telegram', 'discord'],
  };

  static const List<String> _nextDnsServiceIds = <String>[
    'youtube',
    'instagram',
    'tiktok',
    'facebook',
    'netflix',
    'roblox',
  ];

  static const Map<String, String> _localToNextDnsCategoryMap =
      <String, String>{
    'social-networks': 'social-networks',
    'games': 'games',
    'streaming': 'streaming',
    'adult-content': 'porn',
  };

  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;
  NextDnsApiService? _nextDnsApiService;
  final FeatureGateService _featureGateService = FeatureGateService();

  late Set<String> _initialBlockedCategories;
  late Set<String> _initialBlockedServices;
  late Set<String> _initialBlockedDomains;
  late Set<String> _initialBlockedPackages;
  late Set<String> _blockedCategories;
  late Set<String> _blockedServices;
  late Set<String> _blockedDomains;
  late Set<String> _blockedPackages;
  late Map<String, bool> _nextDnsServiceToggles;
  late bool _nextDnsSafeSearchEnabled;
  late bool _nextDnsYoutubeRestrictedModeEnabled;
  late bool _nextDnsBlockBypassEnabled;
  late Set<String> _expandedCategoryIds;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _effectivePolicySubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _policyApplyAckSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _vpnDiagnosticsSubscription;

  int? _latestEffectivePolicyVersion;
  DateTime? _latestEffectivePolicyUpdatedAt;
  _PolicyApplyAckSnapshot? _latestPolicyApplyAck;
  _VpnDiagnosticsSnapshot? _latestVpnDiagnostics;
  DateTime? _lastToggleTapAt;

  bool _isLoading = false;
  bool _isSyncingNextDns = false;
  bool _isLoadingInstalledApps = false;
  bool _autoSaveQueued = false;
  String _query = '';
  List<InstalledAppInfo> _installedApps = const <InstalledAppInfo>[];

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  VpnServiceBase get _resolvedVpnService {
    _vpnService ??= widget.vpnService ?? VpnService();
    return _vpnService!;
  }

  NextDnsApiService get _resolvedNextDnsApiService {
    _nextDnsApiService ??= widget.nextDnsApiService ?? NextDnsApiService();
    return _nextDnsApiService!;
  }

  String? get _nextDnsProfileId {
    final value = widget.child.nextDnsProfileId?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  bool get _hasNextDnsProfile => _nextDnsProfileId != null;

  String? get _resolvedParentId {
    final override = widget.parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    try {
      return _resolvedAuthService.currentUser?.uid;
    } catch (_) {
      // Widget tests may render this screen without Firebase initialization.
      return null;
    }
  }

  bool get _hasChanges {
    return !_setEquals(_initialBlockedCategories, _blockedCategories) ||
        !_setEquals(_initialBlockedServices, _blockedServices) ||
        !_setEquals(_initialBlockedDomains, _blockedDomains) ||
        !_setEquals(_initialBlockedPackages, _blockedPackages);
  }

  bool get _appInventoryEnabled => RolloutFlags.appInventory;
  bool get _packageBlockingEnabled => RolloutFlags.appBlockingPackages;

  int get _blockedKnownCategoryCount {
    final knownIds = ContentCategories.allCategories.map((c) => c.id).toSet();
    return _blockedCategories.where(knownIds.contains).length;
  }

  List<ContentCategory> get _visibleCategories {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return ContentCategories.allCategories;
    }
    return ContentCategories.allCategories.where((category) {
      final categoryText =
          '${category.name} ${category.description}'.toLowerCase();
      if (categoryText.contains(normalized)) {
        return true;
      }
      return _appsForCategory(category.id).any(
        (appKey) => _appLabel(appKey).toLowerCase().contains(normalized),
      );
    }).toList(growable: false);
  }

  List<InstalledAppInfo> get _visibleInstalledApps {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _installedApps;
    }
    return _installedApps.where((app) {
      final appName = app.appName.toLowerCase();
      final packageName = app.packageName.toLowerCase();
      return appName.contains(normalized) || packageName.contains(normalized);
    }).toList(growable: false);
  }

  String? get _activeRestrictionNotice {
    final now = DateTime.now();
    final pausedUntil = widget.child.pausedUntil;
    if (pausedUntil != null && pausedUntil.isAfter(now)) {
      return 'Device is paused until ${_formatTime(pausedUntil)}. '
          'App toggles will apply after pause ends.';
    }

    final activeManualMode = _activeManualModeAt(now);
    if (activeManualMode != null) {
      final mode = (activeManualMode['mode'] as String?)?.trim().toLowerCase();
      if (mode == 'free') {
        return null;
      }
      final modeLabel = switch (mode) {
        'bedtime' => 'Bedtime mode',
        'homework' => 'Homework mode',
        'free' => 'Free mode',
        _ => 'Manual mode',
      };
      final expiresAt = _manualModeDateTime(activeManualMode['expiresAt']);
      final untilLabel = expiresAt == null
          ? 'until your parent changes it'
          : 'until ${_formatTime(expiresAt)}';
      return '$modeLabel is active $untilLabel. '
          'This override blocks apps regardless of toggles. '
          'Your toggles apply again automatically when it ends.';
    }

    final activeSchedule = _activeScheduleAt(now);
    if (activeSchedule == null) {
      return null;
    }
    if (activeSchedule.action == ScheduleAction.allowAll) {
      return null;
    }
    final scheduleEnd = _scheduleWindowForReference(activeSchedule, now).end;
    final modeLabel = activeSchedule.action == ScheduleAction.blockAll
        ? 'Block All'
        : 'Block Distracting';
    return '${activeSchedule.name} is active until ${_formatTime(scheduleEnd)} '
        '($modeLabel). This override is currently in control. '
        'Toggles apply again after it ends.';
  }

  Map<String, dynamic>? _activeManualModeAt(DateTime now) {
    final rawMode = widget.child.manualMode;
    if (rawMode == null || rawMode.isEmpty) {
      return null;
    }
    final mode = (rawMode['mode'] as String?)?.trim().toLowerCase();
    if (mode == null || mode.isEmpty) {
      return null;
    }
    final expiresAt = _manualModeDateTime(rawMode['expiresAt']);
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      return null;
    }
    return rawMode;
  }

  DateTime? _manualModeDateTime(Object? rawValue) {
    if (rawValue is DateTime) {
      return rawValue;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _hydrateStateFromChild(widget.child);
    if (_appInventoryEnabled) {
      unawaited(_loadInstalledApps());
    }
    _startPolicyTelemetryListeners();
  }

  @override
  void didUpdateWidget(covariant BlockCategoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parentChanged =
        oldWidget.parentIdOverride?.trim() != widget.parentIdOverride?.trim();
    final childChanged = oldWidget.child.id != widget.child.id;
    if (childChanged) {
      _hydrateStateFromChild(widget.child);
      if (_appInventoryEnabled) {
        unawaited(_loadInstalledApps());
      }
    }
    if (childChanged || parentChanged) {
      _startPolicyTelemetryListeners();
    }
  }

  @override
  void dispose() {
    _effectivePolicySubscription?.cancel();
    _effectivePolicySubscription = null;
    _policyApplyAckSubscription?.cancel();
    _policyApplyAckSubscription = null;
    _vpnDiagnosticsSubscription?.cancel();
    _vpnDiagnosticsSubscription = null;
    super.dispose();
  }

  void _hydrateStateFromChild(ChildProfile child) {
    final normalizedCategories =
        normalizeCategoryIds(child.policy.blockedCategories).toSet();
    final normalizedServices = child.policy.blockedServices
        .map((serviceId) => serviceId.trim().toLowerCase())
        .where((serviceId) => serviceId.isNotEmpty)
        .toSet();
    final normalizedDomains = child.policy.blockedDomains
        .map(_normalizeDomain)
        .where((domain) => domain.isNotEmpty)
        .toSet();
    final inferredServices =
        ServiceDefinitions.inferServicesFromLegacyDomains(normalizedDomains);
    final mergedServices = <String>{...normalizedServices, ...inferredServices};
    final inferredServiceDomains = ServiceDefinitions.resolveDomains(
      blockedCategories: const <String>[],
      blockedServices: mergedServices,
      customBlockedDomains: const <String>[],
    );
    final customDomains = normalizedDomains.difference(inferredServiceDomains);

    _initialBlockedCategories = Set<String>.from(normalizedCategories);
    _initialBlockedServices = Set<String>.from(mergedServices);
    _initialBlockedDomains = Set<String>.from(customDomains);
    _initialBlockedPackages = child.policy.blockedPackages
        .map((pkg) => pkg.trim().toLowerCase())
        .where((pkg) => pkg.isNotEmpty)
        .toSet();
    _blockedCategories = Set<String>.from(normalizedCategories);
    _blockedServices = Set<String>.from(mergedServices);
    _blockedDomains = Set<String>.from(customDomains);
    _blockedPackages = Set<String>.from(_initialBlockedPackages);
    _expandedCategoryIds = <String>{
      ..._blockedCategories,
    };
    for (final entry in _serviceOrderByCategory.entries) {
      final hasBlockedApp =
          entry.value.any((appKey) => _isAppExplicitlyBlocked(appKey));
      if (hasBlockedApp) {
        _expandedCategoryIds.add(entry.key);
      }
    }
    if (_expandedCategoryIds.isEmpty) {
      _expandedCategoryIds.add('social-networks');
    }
    _nextDnsServiceToggles = <String, bool>{
      for (final id in _nextDnsServiceIds) id: false,
    };
    _nextDnsSafeSearchEnabled = child.policy.safeSearchEnabled;
    _nextDnsYoutubeRestrictedModeEnabled = false;
    _nextDnsBlockBypassEnabled = true;
    _hydrateNextDnsControls();
  }

  Future<void> _loadInstalledApps() async {
    if (!_appInventoryEnabled) {
      return;
    }
    final parentId = _resolvedParentId?.trim();
    if (parentId == null || parentId.isEmpty) {
      return;
    }
    setState(() {
      _isLoadingInstalledApps = true;
    });
    try {
      final apps = await _resolvedFirestoreService.getChildInstalledAppsOnce(
        parentId: parentId,
        childId: widget.child.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _installedApps = apps;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _installedApps = const <InstalledAppInfo>[];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInstalledApps = false;
        });
      }
    }
  }

  bool _isCategoryBlocked(String categoryId) {
    return _blockedCategories.contains(normalizeCategoryId(categoryId));
  }

  void _startPolicyTelemetryListeners() {
    _effectivePolicySubscription?.cancel();
    _effectivePolicySubscription = null;
    _policyApplyAckSubscription?.cancel();
    _policyApplyAckSubscription = null;
    _vpnDiagnosticsSubscription?.cancel();
    _vpnDiagnosticsSubscription = null;

    final parentId = _resolvedParentId?.trim();
    final childId = widget.child.id.trim();
    if (parentId == null || parentId.isEmpty || childId.isEmpty) {
      if (mounted) {
        setState(() {
          _latestEffectivePolicyVersion = null;
          _latestEffectivePolicyUpdatedAt = null;
          _latestPolicyApplyAck = null;
          _latestVpnDiagnostics = null;
        });
      }
      return;
    }

    final childRef =
        _resolvedFirestoreService.firestore.collection('children').doc(childId);

    _effectivePolicySubscription = childRef
        .collection('effective_policy')
        .doc('current')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) {
        return;
      }
      final data = snapshot.data();
      final nextVersion = data == null ? null : _dynamicInt(data['version']);
      final nextUpdatedAt =
          data == null ? null : _dynamicDateTime(data['updatedAt']);
      if (_latestEffectivePolicyVersion == nextVersion &&
          _latestEffectivePolicyUpdatedAt == nextUpdatedAt) {
        return;
      }
      setState(() {
        _latestEffectivePolicyVersion = nextVersion;
        _latestEffectivePolicyUpdatedAt = nextUpdatedAt;
      });
    }, onError: (_, __) {});

    _policyApplyAckSubscription =
        childRef.collection('policy_apply_acks').snapshots().listen((snapshot) {
      if (!mounted) {
        return;
      }
      _PolicyApplyAckSnapshot? newest;
      for (final doc in snapshot.docs) {
        final candidate = _PolicyApplyAckSnapshot.fromMap(doc.id, doc.data());
        if (candidate == null) {
          continue;
        }
        if (newest == null || candidate.sortTime.isAfter(newest.sortTime)) {
          newest = candidate;
        }
      }
      if (_latestPolicyApplyAck == newest) {
        return;
      }
      setState(() {
        _latestPolicyApplyAck = newest;
      });
    }, onError: (_, __) {});

    _vpnDiagnosticsSubscription = childRef
        .collection('vpn_diagnostics')
        .doc('current')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) {
        return;
      }
      final nextSnapshot = _VpnDiagnosticsSnapshot.fromMap(
          snapshot.data() ?? const <String, dynamic>{});
      if (_latestVpnDiagnostics == nextSnapshot) {
        return;
      }
      setState(() {
        _latestVpnDiagnostics = nextSnapshot;
      });
    }, onError: (_, __) {});
  }

  Widget _buildPolicyApplyStatusCard(BuildContext context) {
    final evaluation = PolicyApplyStatusEvaluator.evaluate(
      effectiveVersion: _latestEffectivePolicyVersion,
      effectiveUpdatedAt: _latestEffectivePolicyUpdatedAt,
      appliedVersion: _latestPolicyApplyAck?.appliedVersion,
      ackUpdatedAt: _latestPolicyApplyAck?.updatedAt,
      applyStatus: _latestPolicyApplyAck?.applyStatus,
    );
    final indicatorColor = switch (evaluation.indicator) {
      PolicyApplyIndicator.applied => Colors.green.shade700,
      PolicyApplyIndicator.pending => Colors.orange.shade700,
      PolicyApplyIndicator.stale => Colors.red.shade700,
      PolicyApplyIndicator.unknown => Colors.blueGrey,
    };
    final indicatorLabel = switch (evaluation.indicator) {
      PolicyApplyIndicator.applied => 'Applied',
      PolicyApplyIndicator.pending => 'Pending',
      PolicyApplyIndicator.stale => 'Stale',
      PolicyApplyIndicator.unknown => 'Unknown',
    };

    final lag = evaluation.versionLag;
    final lagLabel = lag == null ? '—' : '$lag';
    final applyDelayLabel = _formatDurationCompact(evaluation.applyDelay);
    final freshnessLabel = switch (evaluation.ackAge) {
      null => 'No recent ack',
      final Duration age when age > PolicyApplyStatusEvaluator.staleAckWindow =>
        'Stale (${_formatDurationCompact(age)} ago)',
      final Duration age => 'Fresh (${_formatDurationCompact(age)} ago)',
    };

    return Card(
      key: const Key('block_categories_policy_sync_card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'POLICY APPLY STATUS',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  key: const Key('block_categories_policy_sync_indicator'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: indicatorColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    indicatorLabel,
                    style: TextStyle(
                      color: indicatorColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTelemetryLine(
              label: 'Effective policy version',
              value: _latestEffectivePolicyVersion?.toString() ?? '—',
            ),
            _buildTelemetryLine(
              label: 'Child applied version',
              value: _latestPolicyApplyAck?.appliedVersion?.toString() ?? '—',
            ),
            _buildTelemetryLine(label: 'Version lag', value: lagLabel),
            _buildTelemetryLine(
                label: 'Apply freshness', value: freshnessLabel),
            _buildTelemetryLine(label: 'Apply delay', value: applyDelayLabel),
            if (_latestPolicyApplyAck?.deviceId != null)
              _buildTelemetryLine(
                label: 'Ack device',
                value: _latestPolicyApplyAck!.deviceId,
              ),
            if ((_latestPolicyApplyAck?.applyStatus ?? '').isNotEmpty)
              _buildTelemetryLine(
                label: 'Child apply status',
                value: _latestPolicyApplyAck!.applyStatus,
              ),
            if (_lastToggleTapAt != null)
              _buildTelemetryLine(
                label: 'Last parent toggle',
                value:
                    '${_formatDurationCompact(DateTime.now().difference(_lastToggleTapAt!))} ago',
              ),
            if (evaluation.indicator == PolicyApplyIndicator.pending)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Child has not applied the latest effective policy yet. Keep this screen open until versions match.',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (evaluation.indicator == PolicyApplyIndicator.stale)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  evaluation.ackHasFailureStatus
                      ? 'Child reported an apply failure. Check child diagnostics and retry once online.'
                      : 'Child apply telemetry is stale. Open the child app to refresh policy status.',
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebValidationCard(BuildContext context) {
    final diagnostics = _latestVpnDiagnostics;
    final now = DateTime.now();
    final lastBlocked = diagnostics?.lastBlockedDnsQuery;
    final diagnosticsAge = diagnostics?.updatedAt == null
        ? null
        : now.difference(diagnostics!.updatedAt!);
    final diagnosticsStale =
        diagnosticsAge != null && diagnosticsAge > const Duration(minutes: 3);
    final recentParentToggle = _lastToggleTapAt != null &&
        now.difference(_lastToggleTapAt!) <= const Duration(minutes: 10);
    final diagnosticsBehindEffectivePolicy = _latestEffectivePolicyUpdatedAt != null &&
        (diagnostics?.updatedAt == null ||
            diagnostics!.updatedAt!.isBefore(
              _latestEffectivePolicyUpdatedAt!
                  .subtract(const Duration(seconds: 5)),
            ));
    final shouldShowDiagnosticsWarning =
        diagnosticsBehindEffectivePolicy || (diagnosticsStale && recentParentToggle);
    final blockedAge =
        lastBlocked == null ? null : now.difference(lastBlocked.timestamp);
    final blockedStale =
        blockedAge != null && blockedAge > const Duration(minutes: 3);
    final cacheBusterDomain = (lastBlocked?.domain ?? 'facebook.com').trim();
    final cacheBusterUrl =
        'https://$cacheBusterDomain/?tb=${DateTime.now().millisecondsSinceEpoch}';

    return Card(
      key: const Key('block_categories_web_validation_card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WEB VALIDATION HINTS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'TrustBridge website blocking is DNS-only. Browser cache and Secure DNS (DoH) can make unblock checks look inconsistent.',
            ),
            const SizedBox(height: 8),
            _buildTelemetryLine(
              label: 'Diagnostics updated',
              value: diagnostics?.updatedAt == null
                  ? 'No diagnostics document'
                  : '${_formatDurationCompact(diagnosticsAge)} ago',
            ),
            _buildTelemetryLine(
              label: 'Last blocked DNS',
              value: lastBlocked == null
                  ? 'No blocked DNS event captured'
                  : '${lastBlocked.domain} (${_formatDiagReason(lastBlocked.reasonCode)})',
            ),
            if (lastBlocked != null)
              _buildTelemetryLine(
                label: 'Blocked evidence',
                value: blockedStale
                    ? 'Stale (${_formatDurationCompact(blockedAge)} ago)'
                    : 'Fresh (${_formatDurationCompact(blockedAge)} ago)',
              ),
            if ((lastBlocked?.matchedRule ?? '').isNotEmpty)
              _buildTelemetryLine(
                label: 'Matched rule',
                value: lastBlocked!.matchedRule!,
              ),
            if ((diagnostics?.bypassReasonCode ?? '').isNotEmpty)
              _buildTelemetryLine(
                label: 'Bypass signal',
                value:
                    '${diagnostics!.likelyDnsBypass ? 'Likely' : 'Not likely'} (${_formatDiagReason(diagnostics.bypassReasonCode)})',
              ),
            const SizedBox(height: 8),
            const Text(
              'Website unblock check: open a fresh tab and test with a cache-buster URL.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            SelectableText(
              cacheBusterUrl,
              style: TextStyle(color: Colors.blue.shade700),
            ),
            if (shouldShowDiagnosticsWarning)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  diagnosticsBehindEffectivePolicy
                      ? 'Child diagnostics are behind the latest policy update. Keep TrustBridge open on child device while re-testing.'
                      : 'Child diagnostics are stale. Keep TrustBridge open on child device while re-testing.',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryLine({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDurationCompact(Duration? value) {
    if (value == null) {
      return '—';
    }
    if (value.inSeconds < 60) {
      return '${value.inSeconds}s';
    }
    if (value.inMinutes < 60) {
      return '${value.inMinutes}m';
    }
    return '${value.inHours}h';
  }

  String _formatDiagReason(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'unknown';
    }
    return normalized.replaceAll('_', ' ');
  }

  DateTime? _dynamicDateTime(Object? rawValue) {
    if (rawValue is Timestamp) {
      return rawValue.toDate();
    }
    if (rawValue is DateTime) {
      return rawValue;
    }
    if (rawValue is int && rawValue > 0) {
      return DateTime.fromMillisecondsSinceEpoch(rawValue);
    }
    if (rawValue is num && rawValue.toInt() > 0) {
      return DateTime.fromMillisecondsSinceEpoch(rawValue.toInt());
    }
    if (rawValue is String) {
      final numeric = int.tryParse(rawValue.trim());
      if (numeric != null && numeric > 0) {
        return DateTime.fromMillisecondsSinceEpoch(numeric);
      }
      return DateTime.tryParse(rawValue.trim());
    }
    return null;
  }

  int? _dynamicInt(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String) {
      return int.tryParse(rawValue.trim());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          key: const Key('block_categories_search'),
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Search categories or apps',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_activeRestrictionNotice != null) ...[
          Card(
            color: Colors.orange.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.schedule_rounded, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _activeRestrictionNotice!,
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (RolloutFlags.parentPolicyApplyStatus) ...[
          _buildPolicyApplyStatusCard(context),
          const SizedBox(height: 12),
        ],
        if (RolloutFlags.parentWebValidationHints) ...[
          _buildWebValidationCard(context),
          const SizedBox(height: 12),
        ],
        Text(
          'APP CATEGORIES',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.18)),
          ),
          child: Text(
            'Categories are the main controls. Expand a category to manage '
            'apps inside it. If the category is ON, every app inside is blocked.',
            style: TextStyle(
              color: Colors.blue.shade900,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_query.trim().isEmpty && _blockedKnownCategoryCount == 0) ...[
          Card(
            key: const Key('block_categories_empty_state'),
            margin: const EdgeInsets.only(bottom: 12),
            child: EmptyState(
              icon: const Text('\u{1F6E1}'),
              title: 'No categories blocked',
              subtitle: 'Toggle categories to start filtering.',
              actionLabel: 'Block First Category',
              onAction: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _blockedCategories
                            .add(ContentCategories.allCategories.first.id);
                      });
                    },
            ),
          ),
        ],
        if (_visibleCategories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No categories match your search.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          )
        else
          ..._visibleCategories.map((category) => _buildCategoryCard(category)),
        const SizedBox(height: 18),
        if (_appInventoryEnabled) ...[
          _buildInstalledAppsSection(),
          const SizedBox(height: 18),
        ],
        Text(
          'CUSTOM BLOCKED SITES',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 10),
        ..._buildCustomDomains(),
        const SizedBox(height: 10),
        _buildAddDomainButton(),
        if (_hasNextDnsProfile) ...[
          const SizedBox(height: 18),
          _buildNextDnsCard(context),
        ],
      ],
    );

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Category Blocking'),
        ),
        bottomNavigationBar: _hasChanges ? _buildSaveBar() : null,
        body: content,
      );
    }

    return Column(
      children: [
        Expanded(child: content),
        if (_hasChanges) _buildSaveBar(),
      ],
    );
  }

  Widget _buildInstalledAppsSection() {
    final apps = _visibleInstalledApps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'INSTALLED APPS',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh installed apps',
              onPressed: _isLoadingInstalledApps
                  ? null
                  : () => unawaited(_loadInstalledApps()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
          ),
          child: const Text(
            'These are apps detected on your child device. '
            'Turning one ON blocks that app package even if it is not in a preset category.',
          ),
        ),
        if (!_packageBlockingEnabled) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.18)),
            ),
            child: const Text(
              'Package-level app blocking is temporarily disabled by rollout '
              'flag. Inventory remains visible for verification.',
            ),
          ),
        ],
        if (_isLoadingInstalledApps) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 3),
        ],
        const SizedBox(height: 10),
        if (apps.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _isLoadingInstalledApps
                    ? 'Loading app inventory from child device...'
                    : 'No app inventory yet. Open TrustBridge on the child phone to sync installed apps.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else
          ...apps.map(_buildInstalledAppRow),
      ],
    );
  }

  Widget _buildInstalledAppRow(InstalledAppInfo app) {
    final packageName = app.packageName.trim().toLowerCase();
    final explicitBlocked = _blockedPackages.contains(packageName);
    final effectiveState = _effectiveInstalledPackageState(app);
    final subtitlePieces = <String>[
      if (app.isSystemApp) 'System',
      packageName,
      effectiveState.status,
    ];
    final subtitle = subtitlePieces.join(' • ');

    return Card(
      key: Key('installed_app_row_$packageName'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.apps_rounded,
          color: effectiveState.blocked ? Colors.red : Colors.blueGrey,
        ),
        title: Text(
          app.appName.isEmpty ? packageName : app.appName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: effectiveState.color),
        ),
        trailing: Switch.adaptive(
          key: Key('installed_app_switch_$packageName'),
          value: explicitBlocked,
          onChanged: _isLoading || !_packageBlockingEnabled
              ? null
              : (enabled) => _toggleInstalledPackageWithPin(
                    packageName: packageName,
                    enabled: enabled,
                    appName: app.appName.isEmpty ? packageName : app.appName,
                  ),
        ),
      ),
    );
  }

  ({bool blocked, String status, Color color}) _effectiveInstalledPackageState(
    InstalledAppInfo app,
  ) {
    final packageName = app.packageName.trim().toLowerCase();
    String? matchedServiceId;
    String? matchedCategoryId;
    for (final service in ServiceDefinitions.all) {
      final packages = service.androidPackages
          .map((pkg) => pkg.trim().toLowerCase())
          .toSet();
      if (!packages.contains(packageName)) {
        continue;
      }
      matchedServiceId = service.serviceId;
      matchedCategoryId = service.categoryId;
      break;
    }

    final serviceBlocked =
        matchedServiceId != null && _isAppExplicitlyBlocked(matchedServiceId);
    final categoryBlocked = matchedCategoryId != null &&
        _isCategoryBlocked(normalizeCategoryId(matchedCategoryId));
    final packageBlocked = _blockedPackages.contains(packageName);

    final activeModeKey = _activeModeOverrideKeyForParent();
    final modeOverride = !RolloutFlags.modeAppOverrides || activeModeKey == null
        ? null
        : widget.child.policy.modeOverrides[activeModeKey];
    final forceBlockByMode = modeOverride?.forceBlockPackages
            .map((pkg) => pkg.trim().toLowerCase())
            .contains(packageName) ==
        true;
    final forceAllowByMode = modeOverride?.forceAllowPackages
            .map((pkg) => pkg.trim().toLowerCase())
            .contains(packageName) ==
        true;

    if (forceAllowByMode) {
      return (
        blocked: false,
        status: 'Allowed by mode override',
        color: Colors.green.shade700
      );
    }
    if (forceBlockByMode) {
      return (
        blocked: true,
        status: 'Blocked by mode',
        color: Colors.deepOrange.shade700
      );
    }
    if (categoryBlocked) {
      return (
        blocked: true,
        status: 'Blocked by category',
        color: Colors.red.shade700
      );
    }
    if (serviceBlocked) {
      return (
        blocked: true,
        status: 'Blocked by service toggle',
        color: Colors.red.shade700
      );
    }
    if (packageBlocked) {
      return (
        blocked: true,
        status: 'Blocked individually',
        color: Colors.red.shade700
      );
    }
    return (blocked: false, status: 'Allowed', color: Colors.green.shade700);
  }

  String? _activeModeOverrideKeyForParent() {
    final now = DateTime.now();
    final pausedUntil = widget.child.pausedUntil;
    if (pausedUntil != null && pausedUntil.isAfter(now)) {
      return 'bedtime';
    }
    final activeManualMode = _activeManualModeAt(now);
    final manualValue =
        (activeManualMode?['mode'] as String?)?.trim().toLowerCase();
    if (manualValue != null && manualValue.isNotEmpty) {
      switch (manualValue) {
        case 'bedtime':
          return 'bedtime';
        case 'homework':
          return 'homework';
        case 'free':
          return 'free';
        default:
          return 'focus';
      }
    }
    final activeSchedule = _activeScheduleAt(now);
    if (activeSchedule == null) {
      return null;
    }
    switch (activeSchedule.action) {
      case ScheduleAction.blockAll:
        return 'bedtime';
      case ScheduleAction.blockDistracting:
        return 'homework';
      case ScheduleAction.allowAll:
        return 'free';
    }
  }

  Future<void> _toggleInstalledPackageWithPin({
    required String packageName,
    required bool enabled,
    required String appName,
  }) async {
    if (!_packageBlockingEnabled) {
      return;
    }
    if (!mounted) {
      return;
    }
    final allowed = await requireParentPin(context);
    if (!allowed || !mounted) {
      return;
    }
    setState(() {
      if (enabled) {
        _blockedPackages.add(packageName);
      } else {
        _blockedPackages.remove(packageName);
      }
      _lastToggleTapAt = DateTime.now();
    });
    unawaited(
      _emitBlockAppsDebugEvent(
        eventType: 'toggle_tapped',
        payload: <String, dynamic>{
          'targetType': 'package',
          'targetId': packageName,
          'targetLabel': appName,
          'enabled': enabled,
          'effectiveBlockedAfterTap': _blockedPackages.contains(packageName),
        },
      ),
    );
    await _autoSaveToggleChanges();
  }

  Widget _buildCategoryCard(ContentCategory category) {
    final isBlocked = _isCategoryBlocked(category.id);
    final iconColor = _categoryColor(category.id);
    final enforcementBadge = _buildEnforcementBadgeForCategory(category.id);
    final appKeys = _visibleAppsForCategory(category.id);
    final hasApps = appKeys.isNotEmpty;
    final isExpanded = _expandedCategoryIds.contains(category.id);
    final blockedApps = appKeys
        .where(
          (appKey) => _isAppEffectivelyBlocked(
            appKey,
            categoryId: category.id,
          ),
        )
        .length;

    return Card(
      key: Key('block_category_card_${category.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(category.icon, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              category.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (enforcementBadge != null) enforcementBadge,
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _categoryExamples(category.id),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      if (hasApps) ...[
                        const SizedBox(height: 6),
                        Text(
                          '$blockedApps/${appKeys.length} apps currently blocked',
                          style: TextStyle(
                            color: isBlocked
                                ? Colors.red.shade700
                                : Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  key: Key('block_category_switch_${category.id}'),
                  value: isBlocked,
                  onChanged: _isLoading || _isSyncingNextDns
                      ? null
                      : (enabled) => _toggleCategoryWithPin(
                            categoryId: category.id,
                            enabled: enabled,
                          ),
                ),
                if (hasApps)
                  IconButton(
                    tooltip: isExpanded ? 'Collapse apps' : 'Expand apps',
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedCategoryIds.remove(category.id);
                        } else {
                          _expandedCategoryIds.add(category.id);
                        }
                      });
                    },
                    icon: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                    ),
                  ),
              ],
            ),
          ),
          if (hasApps && isExpanded) ...[
            Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                children: appKeys
                    .map(
                      (appKey) => _buildCategoryAppRow(
                        categoryId: category.id,
                        appKey: appKey,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _visibleAppsForCategory(String categoryId) {
    final appKeys = _appsForCategory(categoryId);
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return appKeys;
    }

    final matchingApps = appKeys
        .where((appKey) =>
            _appLabel(appKey).toLowerCase().contains(normalizedQuery))
        .toList(growable: false);
    if (matchingApps.isNotEmpty) {
      return matchingApps;
    }

    final category = ContentCategories.findById(categoryId);
    final categoryText =
        '${category?.name ?? ''} ${category?.description ?? ''}'.toLowerCase();
    return categoryText.contains(normalizedQuery) ? appKeys : const <String>[];
  }

  List<String> _appsForCategory(String categoryId) {
    final dynamicServices = ServiceDefinitions.servicesForCategory(categoryId);
    if (dynamicServices.isEmpty) {
      return const <String>[];
    }
    final orderedIds = _serviceOrderByCategory[categoryId];
    if (orderedIds == null || orderedIds.isEmpty) {
      final sorted = dynamicServices.toList()..sort();
      return sorted;
    }
    final ordered = <String>[];
    for (final serviceId in orderedIds) {
      if (dynamicServices.contains(serviceId)) {
        ordered.add(serviceId);
      }
    }
    for (final serviceId in dynamicServices) {
      if (!ordered.contains(serviceId)) {
        ordered.add(serviceId);
      }
    }
    return ordered;
  }

  Widget _buildCategoryAppRow({
    required String categoryId,
    required String appKey,
  }) {
    final categoryBlocked = _isCategoryBlocked(categoryId);
    final explicitBlocked = _isAppExplicitlyBlocked(appKey);
    final effectiveBlocked = categoryBlocked || explicitBlocked;
    final statusText = switch ((categoryBlocked, explicitBlocked)) {
      (true, true) => 'Blocked by category + app override',
      (true, false) => 'Blocked by category',
      (false, true) => 'Blocked individually',
      (false, false) => 'Allowed',
    };
    final statusColor =
        effectiveBlocked ? Colors.red.shade700 : Colors.green.shade700;

    return Container(
      key: Key('block_app_row_${categoryId}_$appKey'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: effectiveBlocked
            ? Colors.red.withValues(alpha: 0.06)
            : Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: effectiveBlocked
              ? Colors.red.withValues(alpha: 0.18)
              : Colors.green.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_appIcon(appKey),
                color: const Color(0xFF207CF8), size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _appLabel(appKey),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: Key('block_app_switch_${categoryId}_$appKey'),
            value: explicitBlocked,
            onChanged: _isLoading || _isSyncingNextDns
                ? null
                : (enabled) => _toggleAppWithPin(
                      appKey: appKey,
                      enabled: enabled,
                      categoryId: categoryId,
                    ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCustomDomains() {
    final sorted = _blockedDomains.toList()..sort();
    if (sorted.isEmpty) {
      return [
        Text(
          'No custom blocked sites yet.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ];
    }

    return sorted
        .map(
          (domain) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.public_rounded, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(domain),
                ),
                _buildInstantBadge(),
                const SizedBox(width: 8),
                InkWell(
                  key: Key('custom_domain_remove_$domain'),
                  onTap: _isLoading || _isSyncingNextDns
                      ? null
                      : () => _removeDomain(domain),
                  child: const Icon(Icons.remove_circle_outline, size: 20),
                ),
              ],
            ),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildAddDomainButton() {
    return InkWell(
      key: const Key('block_categories_add_domain'),
      onTap: _isLoading || _isSyncingNextDns ? null : _showAddDomainDialog,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.55),
            style: BorderStyle.solid,
          ),
        ),
        child: const Text(
          '+ Add Custom Site',
          style: TextStyle(
            color: Color(0xFF207CF8),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
              top: BorderSide(color: Colors.grey.withValues(alpha: 0.25))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Safe Mode Active - $_blockedKnownCategoryCount Categories Restricted',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              key: const Key('block_categories_save_button'),
              onPressed:
                  (_isLoading || _isSyncingNextDns) ? null : _saveChanges,
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDomainDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Custom Site'),
          content: TextField(
            key: const Key('block_categories_domain_input'),
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'e.g., reddit.com',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('block_categories_add_domain_confirm'),
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (value == null || value.isEmpty) {
      return;
    }
    final normalized = _normalizeDomain(value);
    if (!_isValidDomain(normalized)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid domain, e.g. reddit.com')),
      );
      return;
    }

    setState(() {
      _blockedDomains.add(normalized);
      _lastToggleTapAt = DateTime.now();
    });
    unawaited(
      _emitBlockAppsDebugEvent(
        eventType: 'toggle_tapped',
        payload: <String, dynamic>{
          'targetType': 'domain',
          'targetId': normalized,
          'enabled': true,
        },
      ),
    );
    await _autoSaveToggleChanges();
    await _syncNextDnsDomain(normalized, blocked: true);
  }

  Future<void> _saveChanges({
    bool popOnSuccess = true,
    bool showSuccessSnackBar = true,
    String debugOrigin = 'manual_save',
  }) async {
    if (!_hasChanges) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final parentId = _resolvedParentId;
      if (parentId == null) {
        throw Exception('Not logged in');
      }
      unawaited(
        _emitBlockAppsDebugEvent(
          eventType: 'policy_save_started',
          payload: <String, dynamic>{
            'origin': debugOrigin,
            'blockedCategoriesCount': _blockedCategories.length,
            'blockedServicesCount': _blockedServices.length,
            'blockedDomainsCount': _blockedDomains.length,
            'blockedPackagesCount': _blockedPackages.length,
          },
        ),
      );

      final updatedPolicy = widget.child.policy.copyWith(
        blockedCategories: _orderedBlockedCategories(_blockedCategories),
        blockedServices: _orderedBlockedServices(_blockedServices),
        blockedDomains: _orderedBlockedDomains(_blockedDomains),
        blockedPackages: _orderedBlockedPackages(_blockedPackages),
      );
      final updatedChild = widget.child.copyWith(
        policy: updatedPolicy,
        nextDnsControls: _hasNextDnsProfile
            ? _buildNextDnsControlsPayload()
            : widget.child.nextDnsControls,
      );

      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );

      if (!mounted) {
        return;
      }

      // VPN sync is best-effort – don't let it block the save.
      await _syncVpnRulesIfRunning(updatedPolicy);

      // Trigger remote command to child devices for immediate policy sync.
      // This ensures the child receives policy updates in real-time,
      // even if Firestore listeners are not working in background.
      if (RolloutFlags.policySyncTriggerRemoteCommand &&
          widget.child.deviceIds.isNotEmpty) {
        final remoteCommandService = RemoteCommandService();
        for (final deviceId in widget.child.deviceIds) {
          unawaited(
            remoteCommandService.sendRestartVpnCommand(deviceId).catchError(
                  (_) => '',
                ),
          );
        }
      }

      final effectiveVersion =
          await _resolvedFirestoreService.getEffectivePolicyCurrentVersion(
        parentId: parentId,
        childId: widget.child.id,
      );
      if (mounted && effectiveVersion != null) {
        setState(() {
          _latestEffectivePolicyVersion = effectiveVersion;
        });
      }
      unawaited(
        _emitBlockAppsDebugEvent(
          eventType: 'policy_save_succeeded',
          payload: <String, dynamic>{
            'origin': debugOrigin,
            'blockedCategoriesCount': updatedPolicy.blockedCategories.length,
            'blockedServicesCount': updatedPolicy.blockedServices.length,
            'blockedDomainsCount': updatedPolicy.blockedDomains.length,
            'blockedPackagesCount': updatedPolicy.blockedPackages.length,
            if (effectiveVersion != null)
              'effectivePolicyVersion': effectiveVersion,
          },
        ),
      );
      if (effectiveVersion != null) {
        unawaited(
          _emitBlockAppsDebugEvent(
            eventType: 'effective_policy_version_observed',
            payload: <String, dynamic>{
              'origin': debugOrigin,
              'version': effectiveVersion,
            },
          ),
        );
      }

      if (!mounted) {
        return;
      }
      if (showSuccessSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Category blocks updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      final navigator = Navigator.of(context);
      if (popOnSuccess && navigator.canPop()) {
        navigator.pop(updatedChild);
      } else {
        setState(() {
          _initialBlockedCategories = Set<String>.from(_blockedCategories);
          _initialBlockedServices = Set<String>.from(_blockedServices);
          _initialBlockedDomains = Set<String>.from(_blockedDomains);
          _initialBlockedPackages = Set<String>.from(_blockedPackages);
        });
      }
    } catch (error) {
      unawaited(
        _emitBlockAppsDebugEvent(
          eventType: 'policy_save_failed',
          payload: <String, dynamic>{
            'origin': debugOrigin,
            'error': '$error',
          },
        ),
      );
      if (!mounted) {
        return;
      }
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Save Failed'),
          content: Text('Failed to update categories: $error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      final shouldFlushQueuedAutoSave = _autoSaveQueued && _hasChanges;
      _autoSaveQueued = false;
      if (shouldFlushQueuedAutoSave) {
        unawaited(
          _saveChanges(
            popOnSuccess: false,
            showSuccessSnackBar: false,
            debugOrigin: 'auto_toggle_flush',
          ),
        );
      }
    }
  }

  Future<void> _autoSaveToggleChanges() async {
    // Widget tests often render this screen without auth/Firebase.
    if (_resolvedParentId == null || !_hasChanges) {
      return;
    }
    if (_isLoading) {
      _autoSaveQueued = true;
      return;
    }
    await _saveChanges(
      popOnSuccess: false,
      showSuccessSnackBar: false,
      debugOrigin: 'auto_toggle',
    );
  }

  Future<void> _emitBlockAppsDebugEvent({
    required String eventType,
    Map<String, dynamic>? payload,
  }) async {
    final parentId = _resolvedParentId?.trim();
    if (parentId == null || parentId.isEmpty) {
      return;
    }
    try {
      await _resolvedFirestoreService.appendParentDebugEvent(
        parentId: parentId,
        childId: widget.child.id,
        eventType: eventType,
        screen: 'block_apps',
        payload: payload,
      );
    } catch (_) {
      // Debug traces must not block user actions.
    }
  }

  bool _isAppExplicitlyBlocked(String appKey) {
    return _blockedServices.contains(appKey.trim().toLowerCase());
  }

  bool _isAppEffectivelyBlocked(
    String appKey, {
    String? categoryId,
  }) {
    final explicit = _isAppExplicitlyBlocked(appKey);
    if (explicit) {
      return true;
    }
    if (categoryId != null && _isCategoryBlocked(categoryId)) {
      return true;
    }
    final fallbackCategory = _serviceOrderByCategory.entries
        .firstWhere(
          (entry) => entry.value.contains(appKey),
          orElse: () => const MapEntry<String, List<String>>('', <String>[]),
        )
        .key;
    if (fallbackCategory.isEmpty) {
      return false;
    }
    return _isCategoryBlocked(fallbackCategory);
  }

  Future<void> _toggleAppWithPin({
    required String appKey,
    required bool enabled,
    String? categoryId,
  }) async {
    if (!mounted) {
      return;
    }
    final authorized = await requireParentPin(context);
    if (!authorized) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parent PIN required to change protection.'),
        ),
      );
      return;
    }

    final service = ServiceDefinitions.byId[appKey];
    if (service == null) {
      return;
    }

    final categoryBlocked =
        categoryId != null && _isCategoryBlocked(categoryId);
    if (enabled && categoryBlocked && !_isAppExplicitlyBlocked(appKey)) {
      if (!mounted) {
        return;
      }
      final continueAnyway = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text('${_appLabel(appKey)} is already blocked'),
              content: Text(
                '${_prettyLabel(categoryId)} is ON, so this app is blocked now. '
                'Turning this ON keeps ${_appLabel(appKey)} blocked even if you turn the category OFF later.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Keep App Blocked'),
                ),
              ],
            ),
          ) ??
          false;
      if (!continueAnyway) {
        return;
      }
    }

    setState(() {
      if (enabled) {
        _blockedServices.add(appKey.trim().toLowerCase());
      } else {
        _blockedServices.remove(appKey.trim().toLowerCase());
      }
      _lastToggleTapAt = DateTime.now();
    });
    unawaited(
      _emitBlockAppsDebugEvent(
        eventType: 'toggle_tapped',
        payload: <String, dynamic>{
          'targetType': 'service',
          'targetId': appKey.trim().toLowerCase(),
          'targetLabel': _appLabel(appKey),
          'enabled': enabled,
          if (categoryId != null) 'categoryId': categoryId,
          'categoryBlockedAtTap': categoryBlocked,
          'effectiveBlockedAfterTap':
              _isAppEffectivelyBlocked(appKey, categoryId: categoryId),
        },
      ),
    );
    await _autoSaveToggleChanges();
    if (_nextDnsServiceToggles.containsKey(service.serviceId)) {
      await _toggleNextDnsService(service.serviceId, enabled);
    }
    if (!enabled && categoryBlocked && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_appLabel(appKey)} is still blocked because ${_prettyLabel(categoryId)} is ON.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleCategoryWithPin({
    required String categoryId,
    required bool enabled,
  }) async {
    if (_isProOnlyCategory(categoryId)) {
      final gate = await () async {
        try {
          return await _featureGateService
              .checkGate(AppFeature.categoryBlocking);
        } catch (_) {
          // Fail-open for non-Firebase test contexts.
          return const GateResult(allowed: true);
        }
      }();
      if (!gate.allowed) {
        if (mounted) {
          await UpgradeScreen.maybeShow(
            context,
            feature: AppFeature.categoryBlocking,
            reason: gate.upgradeReason,
          );
        }
        return;
      }
    }

    if (!mounted) {
      return;
    }
    final authorized = await requireParentPin(context);
    if (!authorized) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Parent PIN required to change protection.')),
      );
      return;
    }

    setState(() {
      final normalizedCategoryId = normalizeCategoryId(categoryId);
      if (enabled) {
        _blockedCategories.add(normalizedCategoryId);
        _expandedCategoryIds.add(normalizedCategoryId);
      } else {
        removeCategoryAndAliases(_blockedCategories, normalizedCategoryId);
      }
      _lastToggleTapAt = DateTime.now();
    });
    unawaited(
      _emitBlockAppsDebugEvent(
        eventType: 'toggle_tapped',
        payload: <String, dynamic>{
          'targetType': 'category',
          'targetId': normalizeCategoryId(categoryId),
          'targetLabel': _prettyLabel(normalizeCategoryId(categoryId)),
          'enabled': enabled,
          'effectiveBlockedAfterTap': _isCategoryBlocked(categoryId),
        },
      ),
    );
    await _autoSaveToggleChanges();
    await _syncNextDnsCategoryForLocalToggle(
      localCategoryId: normalizeCategoryId(categoryId),
      blocked: enabled,
    );
  }

  bool _isProOnlyCategory(String categoryId) {
    return categoryId == 'adult-content' ||
        categoryId == 'gambling' ||
        categoryId == 'malware';
  }

  Future<void> _syncVpnRulesIfRunning(Policy updatedPolicy) async {
    try {
      final resolvedDomains = ServiceDefinitions.resolveDomains(
        blockedCategories: updatedPolicy.blockedCategories,
        blockedServices: updatedPolicy.blockedServices,
        customBlockedDomains: updatedPolicy.blockedDomains,
      ).toList()
        ..sort();
      // Always push rules to the native layer so they are persisted and
      // available when the VPN starts, even if it isn't running right now.
      // On the parent device the VPN channel may not be registered, so we
      // catch MissingPluginException and all other platform errors.
      await _resolvedVpnService.updateFilterRules(
        blockedCategories: updatedPolicy.blockedCategories,
        blockedDomains: resolvedDomains,
      );
    } on MissingPluginException {
      // Parent device – VPN channel not registered. Ignore.
    } catch (_) {
      // Non-fatal: saving policy should succeed even if VPN sync fails.
    }
  }

  String _normalizeDomain(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.startsWith('http://')) {
      normalized = normalized.substring(7);
    } else if (normalized.startsWith('https://')) {
      normalized = normalized.substring(8);
    }
    if (normalized.startsWith('www.')) {
      normalized = normalized.substring(4);
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _isValidDomain(String value) {
    final pattern = RegExp(r'^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$');
    return pattern.hasMatch(value) && !value.contains('..');
  }

  String _categoryExamples(String categoryId) {
    switch (categoryId) {
      case 'social-networks':
        return 'Instagram, TikTok, Snapchat';
      case 'games':
        return 'Roblox, Minecraft, Fortnite';
      case 'streaming':
        return 'YouTube, Twitch, Netflix';
      case 'adult-content':
        return 'Adult websites and explicit portals';
      case 'shopping':
        return 'Amazon, Flipkart, Myntra';
      default:
        final category = ContentCategories.findById(categoryId);
        return category?.description ?? 'Restricted by policy';
    }
  }

  String _appLabel(String appKey) {
    switch (appKey) {
      case 'instagram':
        return 'Instagram';
      case 'tiktok':
        return 'TikTok';
      case 'youtube':
        return 'YouTube';
      case 'facebook':
        return 'Facebook';
      case 'snapchat':
        return 'Snapchat';
      case 'roblox':
        return 'Roblox';
      case 'reddit':
        return 'Reddit';
      case 'twitter':
        return 'Twitter / X';
      case 'whatsapp':
        return 'WhatsApp';
      case 'telegram':
        return 'Telegram';
      case 'discord':
        return 'Discord';
      default:
        return ServiceDefinitions.byId[appKey]?.displayName ??
            _prettyLabel(appKey);
    }
  }

  IconData _appIcon(String appKey) {
    switch (appKey) {
      case 'instagram':
        return Icons.camera_alt_rounded;
      case 'tiktok':
        return Icons.music_note_rounded;
      case 'youtube':
        return Icons.play_circle_fill_rounded;
      case 'facebook':
        return Icons.groups_rounded;
      case 'snapchat':
        return Icons.chat_bubble_rounded;
      case 'roblox':
        return Icons.videogame_asset_rounded;
      case 'reddit':
        return Icons.forum_rounded;
      case 'twitter':
        return Icons.alternate_email_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  Schedule? _activeScheduleAt(DateTime now) {
    final today = Day.fromDateTime(now);
    final yesterday = Day.fromDateTime(now.subtract(const Duration(days: 1)));
    for (final schedule in widget.child.policy.schedules) {
      if (!schedule.enabled) {
        continue;
      }

      if (schedule.days.contains(today)) {
        final start = _scheduleStartDate(schedule, now);
        final end = _scheduleEndDate(schedule, now);
        if ((now.isAfter(start) || now.isAtSameMomentAs(start)) &&
            now.isBefore(end)) {
          return schedule;
        }
      }

      if (_crossesMidnight(schedule) && schedule.days.contains(yesterday)) {
        final previousDay = now.subtract(const Duration(days: 1));
        final start = _scheduleStartDate(schedule, previousDay);
        final end = _scheduleEndDate(schedule, previousDay);
        if ((now.isAfter(start) || now.isAtSameMomentAs(start)) &&
            now.isBefore(end)) {
          return schedule;
        }
      }
    }
    return null;
  }

  ({DateTime start, DateTime end}) _scheduleWindowForReference(
    Schedule schedule,
    DateTime reference,
  ) {
    final start = _scheduleStartDate(schedule, reference);
    final end = _scheduleEndDate(schedule, reference);
    return (start: start, end: end);
  }

  DateTime _scheduleStartDate(Schedule schedule, DateTime reference) {
    final start = _parseTime(schedule.startTime);
    return DateTime(
      reference.year,
      reference.month,
      reference.day,
      start.hour,
      start.minute,
    );
  }

  DateTime _scheduleEndDate(Schedule schedule, DateTime reference) {
    final end = _parseTime(schedule.endTime);
    var endDate = DateTime(
      reference.year,
      reference.month,
      reference.day,
      end.hour,
      end.minute,
    );
    if (_crossesMidnight(schedule)) {
      endDate = endDate.add(const Duration(days: 1));
    }
    return endDate;
  }

  bool _crossesMidnight(Schedule schedule) {
    final start = _parseTime(schedule.startTime);
    final end = _parseTime(schedule.endTime);
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return startMinutes >= endMinutes;
  }

  ({int hour, int minute}) _parseTime(String raw) {
    final parts = raw.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts.first) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    return (
      hour: hour.clamp(0, 23),
      minute: minute.clamp(0, 59),
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Color _categoryColor(String categoryId) {
    switch (categoryId) {
      case 'social-networks':
        return const Color(0xFF1E88E5);
      case 'games':
        return const Color(0xFF2E7D32);
      case 'streaming':
        return const Color(0xFFD32F2F);
      case 'adult-content':
        return const Color(0xFFF57C00);
      case 'shopping':
        return const Color(0xFFF9A825);
      default:
        final category = ContentCategories.findById(categoryId);
        return category?.riskLevel.color ?? Colors.blueGrey;
    }
  }

  List<String> _orderedBlockedCategories(Set<String> selectedIds) {
    final normalizedIds = normalizeCategoryIds(selectedIds);
    final normalizedSet = normalizedIds.toSet();
    final knownOrder = ContentCategories.allCategories
        .where((category) => normalizedSet.contains(category.id))
        .map((category) => category.id)
        .toList(growable: false);

    final extras = normalizedSet
        .where((id) => !ContentCategories.allCategories.any((c) => c.id == id))
        .toList()
      ..sort();
    return [...knownOrder, ...extras];
  }

  List<String> _orderedBlockedServices(Set<String> selectedServices) {
    final normalizedSet = selectedServices
        .map((serviceId) => serviceId.trim().toLowerCase())
        .where((serviceId) => serviceId.isNotEmpty)
        .where((serviceId) => ServiceDefinitions.byId.containsKey(serviceId))
        .toSet();

    return ServiceDefinitions.all
        .map((service) => service.serviceId)
        .where(normalizedSet.contains)
        .toList(growable: false);
  }

  List<String> _orderedBlockedDomains(Set<String> selectedDomains) {
    final ordered = selectedDomains.map(_normalizeDomain).toSet().toList();
    ordered.sort();
    return ordered;
  }

  List<String> _orderedBlockedPackages(Set<String> selectedPackages) {
    final ordered = selectedPackages
        .map((pkg) => pkg.trim().toLowerCase())
        .where((pkg) => pkg.isNotEmpty)
        .toSet()
        .toList();
    ordered.sort();
    return ordered;
  }

  bool _setEquals(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final value in left) {
      if (!right.contains(value)) {
        return false;
      }
    }
    return true;
  }

  void _hydrateNextDnsControls() {
    final controls = widget.child.nextDnsControls;
    final services = controls['services'];
    if (services is Map) {
      for (final entry in services.entries) {
        final key = entry.key.toString();
        if (_nextDnsServiceToggles.containsKey(key)) {
          _nextDnsServiceToggles[key] = entry.value == true;
        }
      }
    }
    _nextDnsSafeSearchEnabled =
        controls['safeSearchEnabled'] == true || _nextDnsSafeSearchEnabled;
    _nextDnsYoutubeRestrictedModeEnabled =
        controls['youtubeRestrictedModeEnabled'] == true;
    _nextDnsBlockBypassEnabled = controls['blockBypassEnabled'] != false;
  }

  Map<String, dynamic> _buildNextDnsControlsPayload() {
    final categories = <String, bool>{};
    for (final entry in _localToNextDnsCategoryMap.entries) {
      categories[entry.value] = _isCategoryBlocked(entry.key);
    }

    return <String, dynamic>{
      'services': _nextDnsServiceToggles,
      'categories': categories,
      'safeSearchEnabled': _nextDnsSafeSearchEnabled,
      'youtubeRestrictedModeEnabled': _nextDnsYoutubeRestrictedModeEnabled,
      'blockBypassEnabled': _nextDnsBlockBypassEnabled,
      'updatedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> _persistNextDnsControlsOnly() async {
    final profileId = _nextDnsProfileId;
    final parentId =
        widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
    if (profileId == null || parentId == null) {
      return;
    }
    await _resolvedFirestoreService.saveChildNextDnsControls(
      parentId: parentId,
      childId: widget.child.id,
      controls: _buildNextDnsControlsPayload(),
    );
  }

  Future<void> _syncNextDnsCategoryForLocalToggle({
    required String localCategoryId,
    required bool blocked,
  }) async {
    final profileId = _nextDnsProfileId;
    final nextDnsCategoryId = _localToNextDnsCategoryMap[localCategoryId];
    if (profileId == null || nextDnsCategoryId == null) {
      return;
    }

    try {
      setState(() => _isSyncingNextDns = true);
      await _resolvedNextDnsApiService.setCategoryBlocked(
        profileId: profileId,
        categoryId: nextDnsCategoryId,
        blocked: blocked,
      );
      await _persistNextDnsControlsOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'NextDNS category sync failed for $_prettyLabel(localCategoryId): $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingNextDns = false);
      }
    }
  }

  Future<void> _syncNextDnsDomain(String domain,
      {required bool blocked}) async {
    final profileId = _nextDnsProfileId;
    if (profileId == null) {
      return;
    }

    try {
      setState(() => _isSyncingNextDns = true);
      if (blocked) {
        await _resolvedNextDnsApiService.addToDenylist(
          profileId: profileId,
          domain: domain,
        );
      } else {
        await _resolvedNextDnsApiService.removeFromDenylist(
          profileId: profileId,
          domain: domain,
        );
      }
      await _persistNextDnsControlsOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? 'NextDNS denylist add failed for $domain: $error'
                : 'NextDNS denylist remove failed for $domain: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingNextDns = false);
      }
    }
  }

  Future<void> _toggleNextDnsService(String serviceId, bool blocked) async {
    final profileId = _nextDnsProfileId;
    if (profileId == null) {
      return;
    }
    final previous = _nextDnsServiceToggles[serviceId] ?? false;
    setState(() {
      _nextDnsServiceToggles[serviceId] = blocked;
      _isSyncingNextDns = true;
    });

    try {
      await _resolvedNextDnsApiService.setServiceBlocked(
        profileId: profileId,
        serviceId: serviceId,
        blocked: blocked,
      );
      await _persistNextDnsControlsOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nextDnsServiceToggles[serviceId] = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('NextDNS service sync failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingNextDns = false);
      }
    }
  }

  Future<void> _toggleNextDnsParental({
    required bool? safeSearch,
    required bool? youtubeRestricted,
    required bool? blockBypass,
    required VoidCallback optimisticUpdate,
    required VoidCallback rollback,
  }) async {
    final profileId = _nextDnsProfileId;
    if (profileId == null) {
      return;
    }
    optimisticUpdate();
    setState(() => _isSyncingNextDns = true);

    try {
      await _resolvedNextDnsApiService.setParentalControlToggles(
        profileId: profileId,
        safeSearchEnabled: safeSearch,
        youtubeRestrictedModeEnabled: youtubeRestricted,
        blockBypassEnabled: blockBypass,
      );
      await _persistNextDnsControlsOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      rollback();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('NextDNS parental controls sync failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingNextDns = false);
      }
    }
  }

  Future<void> _removeDomain(String domain) async {
    setState(() {
      _blockedDomains.remove(domain);
      _lastToggleTapAt = DateTime.now();
    });
    unawaited(
      _emitBlockAppsDebugEvent(
        eventType: 'toggle_tapped',
        payload: <String, dynamic>{
          'targetType': 'domain',
          'targetId': domain,
          'enabled': false,
        },
      ),
    );
    await _autoSaveToggleChanges();
    await _syncNextDnsDomain(domain, blocked: false);
  }

  Widget _buildNextDnsCard(BuildContext context) {
    final profileId = _nextDnsProfileId!;
    final serviceEntries = _nextDnsServiceToggles.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      key: const Key('block_categories_nextdns_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEXTDNS LIVE CONTROLS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Profile: $profileId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 10),
            ...serviceEntries.map(
              (entry) => SwitchListTile(
                key: Key('nextdns_service_switch_${entry.key}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_prettyLabel(entry.key)),
                value: entry.value,
                onChanged: _isLoading || _isSyncingNextDns
                    ? null
                    : (value) => _toggleNextDnsService(entry.key, value),
              ),
            ),
            const Divider(),
            SwitchListTile(
              key: const Key('nextdns_safe_search_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('SafeSearch'),
              subtitle: const Text('Filter explicit search results'),
              value: _nextDnsSafeSearchEnabled,
              onChanged: _isLoading || _isSyncingNextDns
                  ? null
                  : (value) {
                      final previous = _nextDnsSafeSearchEnabled;
                      _toggleNextDnsParental(
                        safeSearch: value,
                        youtubeRestricted: null,
                        blockBypass: null,
                        optimisticUpdate: () => setState(() {
                          _nextDnsSafeSearchEnabled = value;
                        }),
                        rollback: () => setState(() {
                          _nextDnsSafeSearchEnabled = previous;
                        }),
                      );
                    },
            ),
            SwitchListTile(
              key: const Key('nextdns_youtube_restricted_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('YouTube Restricted Mode'),
              subtitle: const Text('Limit mature content on YouTube'),
              value: _nextDnsYoutubeRestrictedModeEnabled,
              onChanged: _isLoading || _isSyncingNextDns
                  ? null
                  : (value) {
                      final previous = _nextDnsYoutubeRestrictedModeEnabled;
                      _toggleNextDnsParental(
                        safeSearch: null,
                        youtubeRestricted: value,
                        blockBypass: null,
                        optimisticUpdate: () => setState(() {
                          _nextDnsYoutubeRestrictedModeEnabled = value;
                        }),
                        rollback: () => setState(() {
                          _nextDnsYoutubeRestrictedModeEnabled = previous;
                        }),
                      );
                    },
            ),
            SwitchListTile(
              key: const Key('nextdns_block_bypass_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Block Bypass'),
              subtitle: const Text('Prevent simple DNS bypass tricks'),
              value: _nextDnsBlockBypassEnabled,
              onChanged: _isLoading || _isSyncingNextDns
                  ? null
                  : (value) {
                      final previous = _nextDnsBlockBypassEnabled;
                      _toggleNextDnsParental(
                        safeSearch: null,
                        youtubeRestricted: null,
                        blockBypass: value,
                        optimisticUpdate: () => setState(() {
                          _nextDnsBlockBypassEnabled = value;
                        }),
                        rollback: () => setState(() {
                          _nextDnsBlockBypassEnabled = previous;
                        }),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  String _prettyLabel(String raw) {
    return raw
        .split(RegExp(r'[-_]'))
        .where((word) => word.trim().isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  Widget? _buildEnforcementBadgeForCategory(String categoryId) {
    if (_isInstantCategory(categoryId)) {
      return _buildInstantBadge();
    }
    if (_isNextDnsCategory(categoryId)) {
      return _buildNextDnsBadge();
    }
    return null;
  }

  bool _isInstantCategory(String categoryId) {
    return categoryId == 'social-networks';
  }

  bool _isNextDnsCategory(String categoryId) {
    return categoryId == 'adult-content' ||
        categoryId == 'gambling' ||
        categoryId == 'malware';
  }

  Widget _buildInstantBadge() {
    return Tooltip(
      message: 'Changes apply in under 1 second',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          '\u26a1 Instant',
          style: TextStyle(
            color: Colors.green,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildNextDnsBadge() {
    final enabled = _hasNextDnsProfile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: enabled ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '\u2601\ufe0f NextDNS',
        style: TextStyle(
          color: enabled ? Colors.blue.shade700 : Colors.blueGrey,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PolicyApplyAckSnapshot {
  const _PolicyApplyAckSnapshot({
    required this.deviceId,
    required this.appliedVersion,
    required this.applyStatus,
    required this.updatedAt,
    required this.appliedAt,
  });

  final String deviceId;
  final int? appliedVersion;
  final String applyStatus;
  final DateTime? updatedAt;
  final DateTime? appliedAt;

  DateTime get sortTime =>
      updatedAt ?? appliedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  static _PolicyApplyAckSnapshot? fromMap(
    String deviceId,
    Map<String, dynamic> data,
  ) {
    final status = (data['applyStatus'] as String?)?.trim();
    if (status == null || status.isEmpty) {
      return null;
    }
    return _PolicyApplyAckSnapshot(
      deviceId: deviceId,
      appliedVersion: _dynamicInt(data['appliedVersion']),
      applyStatus: status,
      updatedAt: _dynamicDateTime(data['updatedAt']),
      appliedAt: _dynamicDateTime(data['appliedAt']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _PolicyApplyAckSnapshot &&
        other.deviceId == deviceId &&
        other.appliedVersion == appliedVersion &&
        other.applyStatus == applyStatus &&
        other.updatedAt == updatedAt &&
        other.appliedAt == appliedAt;
  }

  @override
  int get hashCode =>
      Object.hash(deviceId, appliedVersion, applyStatus, updatedAt, appliedAt);
}

class _VpnDiagnosticsSnapshot {
  const _VpnDiagnosticsSnapshot({
    required this.updatedAt,
    required this.likelyDnsBypass,
    required this.bypassReasonCode,
    required this.lastBlockedDnsQuery,
  });

  final DateTime? updatedAt;
  final bool likelyDnsBypass;
  final String? bypassReasonCode;
  final _DnsQueryDiagnostics? lastBlockedDnsQuery;

  static _VpnDiagnosticsSnapshot fromMap(Map<String, dynamic> data) {
    return _VpnDiagnosticsSnapshot(
      updatedAt: _dynamicDateTime(data['updatedAt']),
      likelyDnsBypass: data['likelyDnsBypass'] == true,
      bypassReasonCode: (data['bypassReasonCode'] as String?)?.trim(),
      lastBlockedDnsQuery: _DnsQueryDiagnostics.fromMap(
        _dynamicMap(data['lastBlockedDnsQuery']),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _VpnDiagnosticsSnapshot &&
        other.updatedAt == updatedAt &&
        other.likelyDnsBypass == likelyDnsBypass &&
        other.bypassReasonCode == bypassReasonCode &&
        other.lastBlockedDnsQuery == lastBlockedDnsQuery;
  }

  @override
  int get hashCode => Object.hash(
        updatedAt,
        likelyDnsBypass,
        bypassReasonCode,
        lastBlockedDnsQuery,
      );
}

class _DnsQueryDiagnostics {
  const _DnsQueryDiagnostics({
    required this.domain,
    required this.timestamp,
    required this.reasonCode,
    required this.matchedRule,
  });

  final String domain;
  final DateTime timestamp;
  final String? reasonCode;
  final String? matchedRule;

  static _DnsQueryDiagnostics? fromMap(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return null;
    }
    final domain = (data['domain'] as String?)?.trim();
    final timestamp = _dynamicDateTime(data['timestampEpochMs']);
    if (domain == null || domain.isEmpty || timestamp == null) {
      return null;
    }
    return _DnsQueryDiagnostics(
      domain: domain,
      timestamp: timestamp,
      reasonCode: (data['reasonCode'] as String?)?.trim(),
      matchedRule: (data['matchedRule'] as String?)?.trim(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _DnsQueryDiagnostics &&
        other.domain == domain &&
        other.timestamp == timestamp &&
        other.reasonCode == reasonCode &&
        other.matchedRule == matchedRule;
  }

  @override
  int get hashCode => Object.hash(domain, timestamp, reasonCode, matchedRule);
}

DateTime? _dynamicDateTime(Object? rawValue) {
  if (rawValue is Timestamp) {
    return rawValue.toDate();
  }
  if (rawValue is DateTime) {
    return rawValue;
  }
  if (rawValue is int && rawValue > 0) {
    return DateTime.fromMillisecondsSinceEpoch(rawValue);
  }
  if (rawValue is num && rawValue.toInt() > 0) {
    return DateTime.fromMillisecondsSinceEpoch(rawValue.toInt());
  }
  if (rawValue is String) {
    final numeric = int.tryParse(rawValue.trim());
    if (numeric != null && numeric > 0) {
      return DateTime.fromMillisecondsSinceEpoch(numeric);
    }
    return DateTime.tryParse(rawValue.trim());
  }
  return null;
}

int? _dynamicInt(Object? rawValue) {
  if (rawValue is int) {
    return rawValue;
  }
  if (rawValue is num) {
    return rawValue.toInt();
  }
  if (rawValue is String) {
    return int.tryParse(rawValue.trim());
  }
  return null;
}

Map<String, dynamic> _dynamicMap(Object? rawValue) {
  if (rawValue is Map<String, dynamic>) {
    return rawValue;
  }
  if (rawValue is Map) {
    return rawValue.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return const <String, dynamic>{};
}
