import 'dart:async';
import 'dart:convert';

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

  static const Set<String> _homeworkModeBlockedCategories = <String>{
    'social-networks',
    'chat',
    'streaming',
    'games',
  };

  static const Map<String, String> _localToNextDnsCategoryMap =
      <String, String>{
    'social-networks': 'social-networks',
    'games': 'games',
    'streaming': 'streaming',
    'adult-content': 'porn',
  };

  static const List<String> _priorityInstalledPackages = <String>[
    'com.whatsapp',
    'com.instagram.android',
    'com.google.android.youtube',
    'com.snapchat.android',
    'com.dts.freefireth',
    'com.pubg.imobile',
    'com.eterno',
    'in.mohalla.sharechat',
    'com.boloindya.boloindya',
  ];

  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;
  NextDnsApiService? _nextDnsApiService;
  final FeatureGateService _featureGateService = FeatureGateService();

  late Set<String> _initialBlockedCategories;
  late Set<String> _initialBlockedServices;
  late Set<String> _initialBlockedDomains;
  late Set<String> _initialBlockedPackages;
  late Map<String, ModeOverrideSet> _initialModeOverrides;
  late Set<String> _blockedCategories;
  late Set<String> _blockedServices;
  late Set<String> _blockedDomains;
  late Set<String> _blockedPackages;
  late Map<String, ModeOverrideSet> _modeOverrides;
  late Map<String, bool> _nextDnsServiceToggles;
  late bool _nextDnsSafeSearchEnabled;
  late bool _nextDnsYoutubeRestrictedModeEnabled;
  late bool _nextDnsBlockBypassEnabled;
  late Set<String> _expandedCategoryIds;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _effectivePolicySubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _childContextSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _policyApplyAckSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _vpnDiagnosticsSubscription;

  int? _latestEffectivePolicyVersion;
  DateTime? _latestEffectivePolicyUpdatedAt;
  _PolicyApplyAckSnapshot? _latestPolicyApplyAck;
  _VpnDiagnosticsSnapshot? _latestVpnDiagnostics;

  bool _isLoading = false;
  bool _isSyncingNextDns = false;
  bool _isLoadingInstalledApps = false;
  bool _autoSaveQueued = false;
  String _query = '';
  List<InstalledAppInfo> _installedApps = const <InstalledAppInfo>[];
  Map<String, List<String>> _observedDomainsByPackage =
      const <String, List<String>>{};
  final Map<String, Uint8List?> _installedAppIconBytesCache =
      <String, Uint8List?>{};
  ChildProfile? _liveChildContext;

  ChildProfile get _currentChildContext => _liveChildContext ?? widget.child;

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
    final value = _currentChildContext.nextDnsProfileId?.trim();
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
        !_setEquals(_initialBlockedPackages, _blockedPackages) ||
        !_sameModeOverrides(_initialModeOverrides, _modeOverrides);
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
    final sortedApps = List<InstalledAppInfo>.from(_installedApps)
      ..sort((a, b) {
        final rankA = _installedPackageRank(a.packageName);
        final rankB = _installedPackageRank(b.packageName);
        if (rankA != rankB) {
          return rankA.compareTo(rankB);
        }
        return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      });

    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return sortedApps;
    }
    return sortedApps.where((app) {
      final appName = app.appName.toLowerCase();
      final packageName = app.packageName.toLowerCase();
      final domains =
          (_observedDomainsByPackage[packageName] ?? const <String>[])
              .join(' ')
              .toLowerCase();
      return appName.contains(normalized) ||
          packageName.contains(normalized) ||
          domains.contains(normalized);
    }).toList(growable: false);
  }

  int _installedPackageRank(String packageName) {
    final normalized = packageName.trim().toLowerCase();
    final index = _priorityInstalledPackages.indexOf(normalized);
    return index >= 0 ? index : 9999;
  }

  String? get _activeRestrictionNotice {
    final now = DateTime.now();
    final pausedUntil = _currentChildContext.pausedUntil;
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
    final rawMode = _currentChildContext.manualMode;
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
    _liveChildContext = widget.child;
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
      _liveChildContext = widget.child;
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
    _childContextSubscription?.cancel();
    _childContextSubscription = null;
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
    final normalizedModeOverrides =
        _normalizeModeOverrideSets(child.policy.modeOverrides);
    _initialModeOverrides = _cloneModeOverrides(normalizedModeOverrides);
    _blockedCategories = Set<String>.from(normalizedCategories);
    _blockedServices = Set<String>.from(mergedServices);
    _blockedDomains = Set<String>.from(customDomains);
    _blockedPackages = Set<String>.from(_initialBlockedPackages);
    _modeOverrides = _cloneModeOverrides(normalizedModeOverrides);
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
      final appsFuture = _resolvedFirestoreService.getChildInstalledAppsOnce(
        parentId: parentId,
        childId: widget.child.id,
      );
      final observedDomainsFuture =
          _resolvedFirestoreService.getChildObservedAppDomainsOnce(
        parentId: parentId,
        childId: widget.child.id,
      );
      final apps = await appsFuture;
      final observedDomains = await observedDomainsFuture;
      final appsByPackage = <String, InstalledAppInfo>{
        for (final app in apps)
          if (!app.isSystemApp) app.packageName.trim().toLowerCase(): app,
      };
      // Show full installed inventory first, then backfill observed-only
      // packages that may not have synced into inventory yet.
      final mergedAppsByPackage = <String, InstalledAppInfo>{
        ...appsByPackage,
      };
      final observedPackages = observedDomains.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => entry.key.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      for (final packageName in observedPackages) {
        final fromInventory = appsByPackage[packageName];
        if (fromInventory != null) {
          mergedAppsByPackage[packageName] = fromInventory;
          continue;
        }
        mergedAppsByPackage[packageName] = InstalledAppInfo(
          packageName: packageName,
          appName: _fallbackObservedAppName(packageName),
          isSystemApp: false,
          isLaunchable: true,
        );
      }
      final mergedApps = mergedAppsByPackage.values.toList(growable: false);
      mergedApps.sort((a, b) {
        final rankA = _installedPackageRank(a.packageName);
        final rankB = _installedPackageRank(b.packageName);
        if (rankA != rankB) {
          return rankA.compareTo(rankB);
        }
        return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _installedApps = mergedApps;
        _observedDomainsByPackage = observedDomains;
        _installedAppIconBytesCache.clear();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _installedApps = const <InstalledAppInfo>[];
        _observedDomainsByPackage = const <String, List<String>>{};
        _installedAppIconBytesCache.clear();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInstalledApps = false;
        });
      }
    }
  }

  String _fallbackObservedAppName(String packageName) {
    final normalized = packageName.trim().toLowerCase();
    for (final service in ServiceDefinitions.all) {
      final matchesService = service.androidPackages.any(
        (pkg) => pkg.trim().toLowerCase() == normalized,
      );
      if (matchesService) {
        return service.displayName;
      }
    }
    final lastSegment = normalized.split('.').lastWhere(
          (segment) => segment.trim().isNotEmpty,
          orElse: () => normalized,
        );
    final cleaned = lastSegment.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (cleaned.isEmpty) {
      return normalized;
    }
    return cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) => word.length == 1
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  bool _isCategoryBlocked(String categoryId) {
    return _blockedCategories.contains(normalizeCategoryId(categoryId));
  }

  void _startPolicyTelemetryListeners() {
    _effectivePolicySubscription?.cancel();
    _effectivePolicySubscription = null;
    _childContextSubscription?.cancel();
    _childContextSubscription = null;
    _policyApplyAckSubscription?.cancel();
    _policyApplyAckSubscription = null;
    _vpnDiagnosticsSubscription?.cancel();
    _vpnDiagnosticsSubscription = null;

    final parentId = _resolvedParentId?.trim();
    final childId = _currentChildContext.id.trim();
    if (parentId == null || parentId.isEmpty || childId.isEmpty) {
      if (mounted) {
        setState(() {
          _liveChildContext = widget.child;
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

    _childContextSubscription = childRef.snapshots().listen((snapshot) {
      if (!mounted || !snapshot.exists) {
        return;
      }
      try {
        final next = ChildProfile.fromFirestore(snapshot);
        setState(() {
          _liveChildContext = next;
        });
      } catch (_) {
        // Keep current UI state if parsing fails.
      }
    }, onError: (_, __) {});

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
      final candidates = <_PolicyApplyAckSnapshot>[];
      for (final doc in snapshot.docs) {
        final candidate = _PolicyApplyAckSnapshot.fromMap(doc.id, doc.data());
        if (candidate == null) {
          continue;
        }
        candidates.add(candidate);
      }
      final selectedAck = _selectBestPolicyApplyAck(candidates);
      if (_latestPolicyApplyAck == selectedAck) {
        return;
      }
      setState(() {
        _latestPolicyApplyAck = selectedAck;
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

  _PolicyApplyAckSnapshot? _selectBestPolicyApplyAck(
    Iterable<_PolicyApplyAckSnapshot> snapshots,
  ) {
    final candidates = snapshots.toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }

    final linkedDeviceIds = <String>{
      ..._currentChildContext.deviceIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
      ..._currentChildContext.deviceMetadata.keys
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
    };
    final effectiveVersion = _latestEffectivePolicyVersion;
    _PolicyApplyAckSnapshot best = candidates.first;
    var bestPriority = _policyAckPriority(
      best,
      effectiveVersion,
      linkedToChild: linkedDeviceIds.isEmpty ||
          linkedDeviceIds.contains(best.deviceId.trim()),
    );
    for (var i = 1; i < candidates.length; i++) {
      final candidate = candidates[i];
      final candidatePriority = _policyAckPriority(
        candidate,
        effectiveVersion,
        linkedToChild: linkedDeviceIds.isEmpty ||
            linkedDeviceIds.contains(candidate.deviceId.trim()),
      );
      if (candidatePriority > bestPriority ||
          (candidatePriority == bestPriority &&
              candidate.sortTime.isAfter(best.sortTime))) {
        best = candidate;
        bestPriority = candidatePriority;
      }
    }
    return best;
  }

  int _policyAckPriority(
      _PolicyApplyAckSnapshot snapshot, int? effectiveVersion,
      {required bool linkedToChild}) {
    var priority = 0;
    if (linkedToChild) {
      // Prefer linked devices, but never at the expense of obviously stale acks.
      priority += 25;
    }
    if (snapshot.appliedVersion != null) {
      priority += 50;
    }
    if (snapshot.isAppliedSuccess) {
      priority += 200;
    }
    if (snapshot.hasFailureStatus) {
      priority -= 150;
    }

    final appliedVersion = snapshot.appliedVersion;
    if (effectiveVersion != null && appliedVersion != null) {
      final lag = effectiveVersion - appliedVersion;
      if (lag <= 0) {
        priority += 500;
      } else {
        priority -= lag.clamp(0, 200);
      }
    }
    return priority;
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
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
            ),
          ),
          child: const Text(
            'Apps installed on your child\'s phone that can use internet are shown here. '
            'Turn one ON to block that app.',
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
              'App blocking is updating right now. Please try again shortly.',
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
                    : 'No network apps found yet. Open Chrome or WhatsApp on the child phone, then tap refresh.',
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
    final effectiveState = _effectiveInstalledPackageState(app);
    final iconBytes = _installedAppIconBytes(app);
    final observedDomains =
        _observedDomainsByPackage[packageName] ?? const <String>[];
    final domainPreview = observedDomains.take(3).join(', ');

    return Card(
      key: Key('installed_app_row_$packageName'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: effectiveState.blocked
              ? Colors.red.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: effectiveState.blocked
              ? Colors.red.shade700
              : Theme.of(context).colorScheme.primary,
          backgroundImage: iconBytes == null ? null : MemoryImage(iconBytes),
          child: iconBytes == null
              ? Icon(_installedAppIcon(packageName), size: 20)
              : null,
        ),
        title: Text(
          app.appName.isEmpty ? packageName : app.appName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              effectiveState.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: effectiveState.color,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (domainPreview.isNotEmpty)
              Text(
                'Domains: $domainPreview${observedDomains.length > 3 ? ', ...' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        trailing: Switch.adaptive(
          key: Key('installed_app_switch_$packageName'),
          value: effectiveState.blocked,
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
    final match = _serviceMatchForPackage(packageName);
    final matchedServiceId = match.serviceId;
    final matchedCategoryId = match.categoryId;

    final serviceBlocked =
        matchedServiceId != null && _isAppExplicitlyBlocked(matchedServiceId);
    final categoryBlocked = matchedCategoryId != null &&
        _isCategoryBlocked(normalizeCategoryId(matchedCategoryId));
    final packageBlocked = _blockedPackages.contains(packageName);

    final modeContext = _activeModeContext();
    final modeOverride = modeContext.overrideSet;
    final modeBlockedByCategory = matchedCategoryId != null &&
        modeContext.blockedCategories.contains(
          normalizeCategoryId(matchedCategoryId),
        );
    final modeBlockedByService = matchedServiceId != null &&
        (modeOverride?.forceBlockServices
                .map((value) => value.trim().toLowerCase())
                .contains(matchedServiceId) ==
            true);
    final modeBlockedByPackage = modeOverride?.forceBlockPackages
            .map((value) => value.trim().toLowerCase())
            .contains(packageName) ==
        true;
    final modeAllowedByService = matchedServiceId != null &&
        (modeOverride?.forceAllowServices
                .map((value) => value.trim().toLowerCase())
                .contains(matchedServiceId) ==
            true);
    final modeAllowedByPackage = modeOverride?.forceAllowPackages
            .map((value) => value.trim().toLowerCase())
            .contains(packageName) ==
        true;
    final modeAllowed = modeAllowedByService || modeAllowedByPackage;
    final blockedByMode = (modeContext.blocksAll ||
            modeBlockedByCategory ||
            modeBlockedByService ||
            modeBlockedByPackage) &&
        !modeAllowed;

    final blocked =
        categoryBlocked || serviceBlocked || packageBlocked || blockedByMode;
    if (categoryBlocked || serviceBlocked || packageBlocked || blockedByMode) {
      return (blocked: true, status: 'Blocked', color: Colors.red.shade700);
    }
    return (blocked: blocked, status: 'Allowed', color: Colors.green.shade700);
  }

  ({String? serviceId, String? categoryId}) _serviceMatchForPackage(
    String packageName,
  ) {
    for (final service in ServiceDefinitions.all) {
      final packages = service.androidPackages
          .map((pkg) => pkg.trim().toLowerCase())
          .toSet();
      if (packages.contains(packageName)) {
        return (serviceId: service.serviceId, categoryId: service.categoryId);
      }
    }
    return (serviceId: null, categoryId: null);
  }

  ({
    String? modeKey,
    String? modeLabel,
    bool blocksAll,
    Set<String> blockedCategories,
    ModeOverrideSet? overrideSet,
  }) _activeModeContext() {
    final modeKey = _activeModeOverrideKeyForParent();
    final blockedCategories = <String>{};
    var blocksAll = false;
    String? modeLabel;
    switch (modeKey) {
      case 'homework':
      case 'focus':
        blockedCategories.addAll(_homeworkModeBlockedCategories);
        modeLabel = 'Homework Mode';
        break;
      case 'bedtime':
        blocksAll = true;
        modeLabel = 'Bedtime Mode';
        break;
      case 'free':
        modeLabel = 'Free Play';
        break;
    }
    final overrideSet = !RolloutFlags.modeAppOverrides || modeKey == null
        ? null
        : _modeOverrides[modeKey];
    return (
      modeKey: modeKey,
      modeLabel: modeLabel,
      blocksAll: blocksAll,
      blockedCategories: blockedCategories,
      overrideSet: overrideSet,
    );
  }

  String? _activeModeOverrideKeyForParent() {
    final now = DateTime.now();
    final pausedUntil = _currentChildContext.pausedUntil;
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
    final modeContext = _activeModeContext();
    final activeModeKey = modeContext.modeKey;
    final serviceMatch = _serviceMatchForPackage(packageName);
    final modeBlockingPackage = _isModeBlockingPackage(
      packageName: packageName,
      serviceId: serviceMatch.serviceId,
      categoryId: serviceMatch.categoryId,
    );
    setState(() {
      if (enabled) {
        _blockedPackages.add(packageName);
        if (activeModeKey != null && RolloutFlags.modeAppOverrides) {
          _removeModePackageAllowOverride(
            modeKey: activeModeKey,
            packageName: packageName,
          );
        }
      } else {
        _blockedPackages.remove(packageName);
        if (activeModeKey != null && RolloutFlags.modeAppOverrides) {
          if (modeBlockingPackage) {
            _addModePackageAllowOverride(
              modeKey: activeModeKey,
              packageName: packageName,
            );
          } else {
            _removeModePackageAllowOverride(
              modeKey: activeModeKey,
              packageName: packageName,
            );
          }
        }
      }
    });
    unawaited(
      _emitBlockAppsDebugEvent(
        eventType: 'toggle_tapped',
        payload: <String, dynamic>{
          'targetType': 'package',
          'targetId': packageName,
          'targetLabel': appName,
          'enabled': enabled,
          'effectiveBlockedAfterTap': _effectiveInstalledPackageState(
            InstalledAppInfo(
              packageName: packageName,
              appName: appName,
              isSystemApp: false,
            ),
          ).blocked,
        },
      ),
    );
    await _autoSaveToggleChanges();
    if (!enabled &&
        modeBlockingPackage &&
        modeContext.modeLabel != null &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$appName is now allowed for ${modeContext.modeLabel}.',
          ),
        ),
      );
    }
  }

  bool _isModeBlockingPackage({
    required String packageName,
    required String? serviceId,
    required String? categoryId,
  }) {
    final modeContext = _activeModeContext();
    final modeOverride = modeContext.overrideSet;
    final normalizedPackage = packageName.trim().toLowerCase();
    final normalizedService = serviceId?.trim().toLowerCase();
    final normalizedCategory =
        categoryId == null ? null : normalizeCategoryId(categoryId);
    final modeBlockedByCategory = normalizedCategory != null &&
        modeContext.blockedCategories.contains(normalizedCategory);
    final modeBlockedByService = normalizedService != null &&
        (modeOverride?.forceBlockServices
                .map((value) => value.trim().toLowerCase())
                .contains(normalizedService) ==
            true);
    final modeBlockedByPackage = modeOverride?.forceBlockPackages
            .map((value) => value.trim().toLowerCase())
            .contains(normalizedPackage) ==
        true;
    final modeAllowedByService = normalizedService != null &&
        (modeOverride?.forceAllowServices
                .map((value) => value.trim().toLowerCase())
                .contains(normalizedService) ==
            true);
    final modeAllowedByPackage = modeOverride?.forceAllowPackages
            .map((value) => value.trim().toLowerCase())
            .contains(normalizedPackage) ==
        true;
    final modeAllowed = modeAllowedByService || modeAllowedByPackage;
    return (modeContext.blocksAll ||
            modeBlockedByCategory ||
            modeBlockedByService ||
            modeBlockedByPackage) &&
        !modeAllowed;
  }

  void _addModePackageAllowOverride({
    required String modeKey,
    required String packageName,
  }) {
    final normalizedMode = modeKey.trim().toLowerCase();
    final normalizedPackage = packageName.trim().toLowerCase();
    final current = _modeOverrides[normalizedMode] ?? const ModeOverrideSet();
    final nextAllowPackages = <String>{
      ...current.forceAllowPackages
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty),
      normalizedPackage,
    }.toList()
      ..sort();
    final nextBlockPackages = current.forceBlockPackages
        .map((value) => value.trim().toLowerCase())
        .where(
          (value) => value.isNotEmpty && value != normalizedPackage,
        )
        .toSet()
        .toList()
      ..sort();
    final updated = current.copyWith(
      forceAllowPackages: nextAllowPackages,
      forceBlockPackages: nextBlockPackages,
    );
    if (updated.isEmpty) {
      _modeOverrides.remove(normalizedMode);
    } else {
      _modeOverrides[normalizedMode] = updated;
    }
  }

  void _removeModePackageAllowOverride({
    required String modeKey,
    required String packageName,
  }) {
    final normalizedMode = modeKey.trim().toLowerCase();
    final normalizedPackage = packageName.trim().toLowerCase();
    final current = _modeOverrides[normalizedMode];
    if (current == null) {
      return;
    }
    final nextAllowPackages = current.forceAllowPackages
        .map((value) => value.trim().toLowerCase())
        .where(
          (value) => value.isNotEmpty && value != normalizedPackage,
        )
        .toSet()
        .toList()
      ..sort();
    final updated = current.copyWith(forceAllowPackages: nextAllowPackages);
    if (updated.isEmpty) {
      _modeOverrides.remove(normalizedMode);
    } else {
      _modeOverrides[normalizedMode] = updated;
    }
  }

  Widget _buildCategoryCard(ContentCategory category) {
    final categoryState = _effectiveCategoryState(category.id);
    final isBlocked = categoryState.blocked;
    final iconColor = _categoryColor(category.id);
    final enforcementBadge = _buildEnforcementBadgeForCategory(category.id);
    final modeSourceBadge = categoryState.blockedByMode
        ? _buildModeSourceBadge(categoryState.modeLabel)
        : null;
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
                      Text(
                        category.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (enforcementBadge != null || modeSourceBadge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (enforcementBadge != null) enforcementBadge,
                              if (modeSourceBadge != null) modeSourceBadge,
                            ],
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        _categoryExamples(category.id),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        categoryState.status,
                        style: TextStyle(
                          color: categoryState.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
    final effectiveState = _effectiveServiceState(
      appKey: appKey,
      categoryId: categoryId,
    );
    final effectiveBlocked = effectiveState.blocked;
    final statusText = effectiveState.status;
    final statusColor = effectiveState.color;

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
            value: effectiveBlocked,
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
      final saveBlockedCategories = Set<String>.from(_blockedCategories);
      final saveBlockedServices = Set<String>.from(_blockedServices);
      final saveBlockedDomains = Set<String>.from(_blockedDomains);
      final saveBlockedPackages = Set<String>.from(_blockedPackages);
      final saveModeOverrides = _cloneModeOverrides(_modeOverrides);
      unawaited(
        _emitBlockAppsDebugEvent(
          eventType: 'policy_save_started',
          payload: <String, dynamic>{
            'origin': debugOrigin,
            'blockedCategoriesCount': saveBlockedCategories.length,
            'blockedServicesCount': saveBlockedServices.length,
            'blockedDomainsCount': saveBlockedDomains.length,
            'blockedPackagesCount': saveBlockedPackages.length,
          },
        ),
      );

      final sourceChild = _currentChildContext;
      final updatedPolicy = sourceChild.policy.copyWith(
        blockedCategories: _orderedBlockedCategories(saveBlockedCategories),
        blockedServices: _orderedBlockedServices(saveBlockedServices),
        blockedDomains: _orderedBlockedDomains(saveBlockedDomains),
        blockedPackages: _orderedBlockedPackages(saveBlockedPackages),
        modeOverrides: saveModeOverrides,
      );
      final updatedChild = sourceChild.copyWith(
        policy: updatedPolicy,
        nextDnsControls: _hasNextDnsProfile
            ? _buildNextDnsControlsPayload()
            : sourceChild.nextDnsControls,
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
          sourceChild.deviceIds.isNotEmpty) {
        final remoteCommandService = RemoteCommandService();
        for (final deviceId in sourceChild.deviceIds) {
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
        childId: sourceChild.id,
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
          _initialBlockedCategories = Set<String>.from(saveBlockedCategories);
          _initialBlockedServices = Set<String>.from(saveBlockedServices);
          _initialBlockedDomains = Set<String>.from(saveBlockedDomains);
          _initialBlockedPackages = Set<String>.from(saveBlockedPackages);
          _initialModeOverrides = _cloneModeOverrides(saveModeOverrides);
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
    return _effectiveServiceState(
      appKey: appKey,
      categoryId: categoryId,
    ).blocked;
  }

  ({
    bool blocked,
    String status,
    Color color,
  }) _effectiveServiceState({
    required String appKey,
    String? categoryId,
  }) {
    final normalizedApp = appKey.trim().toLowerCase();
    final resolvedCategory = categoryId == null || categoryId.trim().isEmpty
        ? _categoryIdForService(normalizedApp)
        : normalizeCategoryId(categoryId);
    final categoryBlocked =
        resolvedCategory != null && _isCategoryBlocked(resolvedCategory);
    final explicitBlocked = _blockedServices.contains(normalizedApp);

    final modeContext = _activeModeContext();
    final modeOverride = modeContext.overrideSet;
    final modeBlockedByCategory = resolvedCategory != null &&
        modeContext.blockedCategories.contains(resolvedCategory);
    final modeBlockedByOverride = modeOverride?.forceBlockServices
            .map((value) => value.trim().toLowerCase())
            .contains(normalizedApp) ==
        true;
    final modeAllowedByOverride = modeOverride?.forceAllowServices
            .map((value) => value.trim().toLowerCase())
            .contains(normalizedApp) ==
        true;
    final blockedByMode = (modeContext.blocksAll ||
            modeBlockedByCategory ||
            modeBlockedByOverride) &&
        !modeAllowedByOverride;
    final blocked = categoryBlocked || explicitBlocked || blockedByMode;

    if (categoryBlocked) {
      return (
        blocked: true,
        status: 'Blocked by category',
        color: Colors.red.shade700,
      );
    }
    if (explicitBlocked) {
      return (
        blocked: true,
        status: 'Blocked individually',
        color: Colors.red.shade700,
      );
    }
    if (blockedByMode) {
      final modeLabel = modeContext.modeLabel ?? 'active mode';
      return (
        blocked: true,
        status: 'Blocked from $modeLabel',
        color: Colors.deepOrange.shade700,
      );
    }
    if (modeAllowedByOverride) {
      return (
        blocked: false,
        status: 'Allowed by manual override',
        color: Colors.green.shade700,
      );
    }
    return (blocked: blocked, status: 'Allowed', color: Colors.green.shade700);
  }

  ({
    bool blocked,
    bool blockedByMode,
    bool blockedManually,
    bool allowedByManualOverride,
    String status,
    Color color,
    String? modeLabel,
  }) _effectiveCategoryState(String categoryId) {
    final normalizedCategory = normalizeCategoryId(categoryId);
    final blockedManually = _blockedCategories.contains(normalizedCategory);
    final modeContext = _activeModeContext();
    final modeOverride = modeContext.overrideSet;
    final modeLabel = modeContext.modeLabel;
    final servicesForCategory = _serviceIdsForCategory(normalizedCategory);
    final modeBlockedByCategory = modeContext.blocksAll ||
        modeContext.blockedCategories.contains(normalizedCategory);
    final modeBlockedByService = servicesForCategory.any(
      (serviceId) =>
          modeOverride?.forceBlockServices
              .map((value) => value.trim().toLowerCase())
              .contains(serviceId) ==
          true,
    );
    final modeForceAllowedServices = servicesForCategory
        .where(
          (serviceId) =>
              modeOverride?.forceAllowServices
                  .map((value) => value.trim().toLowerCase())
                  .contains(serviceId) ==
              true,
        )
        .toSet();
    final modeAllowsAllKnownServices = servicesForCategory.isNotEmpty &&
        modeForceAllowedServices.length == servicesForCategory.length;
    final modeWouldBlock = modeBlockedByCategory || modeBlockedByService;
    final blockedByMode = modeWouldBlock && !modeAllowsAllKnownServices;
    final allowedByManualOverride =
        modeWouldBlock && !blockedManually && modeAllowsAllKnownServices;
    final blocked = blockedManually || blockedByMode;

    if (blockedManually) {
      return (
        blocked: true,
        blockedByMode: false,
        blockedManually: true,
        allowedByManualOverride: false,
        status: 'Blocked manually',
        color: Colors.red.shade700,
        modeLabel: null,
      );
    }
    if (blockedByMode) {
      return (
        blocked: true,
        blockedByMode: true,
        blockedManually: false,
        allowedByManualOverride: false,
        status: 'Blocked from ${modeLabel ?? 'current mode'}',
        color: Colors.deepOrange.shade700,
        modeLabel: modeLabel,
      );
    }
    if (allowedByManualOverride) {
      return (
        blocked: false,
        blockedByMode: false,
        blockedManually: false,
        allowedByManualOverride: true,
        status: 'Allowed by manual override',
        color: Colors.green.shade700,
        modeLabel: null,
      );
    }
    return (
      blocked: blocked,
      blockedByMode: false,
      blockedManually: false,
      allowedByManualOverride: false,
      status: 'Allowed',
      color: Colors.green.shade700,
      modeLabel: null,
    );
  }

  Set<String> _serviceIdsForCategory(String categoryId) {
    return ServiceDefinitions.servicesForCategory(categoryId)
        .map((serviceId) => serviceId.trim().toLowerCase())
        .where((serviceId) => serviceId.isNotEmpty)
        .toSet();
  }

  void _addModeCategoryAllowOverrides({
    required String modeKey,
    required String categoryId,
  }) {
    final normalizedMode = modeKey.trim().toLowerCase();
    final services = _serviceIdsForCategory(categoryId);
    if (services.isEmpty) {
      return;
    }
    final current = _modeOverrides[normalizedMode] ?? const ModeOverrideSet();
    final nextAllowServices = <String>{
      ...current.forceAllowServices
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty),
      ...services,
    }.toList()
      ..sort();
    final nextBlockServices = current.forceBlockServices
        .map((value) => value.trim().toLowerCase())
        .where(
          (value) => value.isNotEmpty && !services.contains(value),
        )
        .toSet()
        .toList()
      ..sort();
    final updated = current.copyWith(
      forceAllowServices: nextAllowServices,
      forceBlockServices: nextBlockServices,
    );
    if (updated.isEmpty) {
      _modeOverrides.remove(normalizedMode);
    } else {
      _modeOverrides[normalizedMode] = updated;
    }
  }

  void _removeModeCategoryAllowOverrides({
    required String modeKey,
    required String categoryId,
  }) {
    final normalizedMode = modeKey.trim().toLowerCase();
    final services = _serviceIdsForCategory(categoryId);
    if (services.isEmpty) {
      return;
    }
    final current = _modeOverrides[normalizedMode];
    if (current == null) {
      return;
    }
    final nextAllowServices = current.forceAllowServices
        .map((value) => value.trim().toLowerCase())
        .where(
          (value) => value.isNotEmpty && !services.contains(value),
        )
        .toSet()
        .toList()
      ..sort();
    final updated = current.copyWith(forceAllowServices: nextAllowServices);
    if (updated.isEmpty) {
      _modeOverrides.remove(normalizedMode);
    } else {
      _modeOverrides[normalizedMode] = updated;
    }
  }

  String? _categoryIdForService(String appKey) {
    final normalized = appKey.trim().toLowerCase();
    final service = ServiceDefinitions.byId[normalized];
    final serviceCategory = service?.categoryId.trim();
    if (serviceCategory != null && serviceCategory.isNotEmpty) {
      return normalizeCategoryId(serviceCategory);
    }
    for (final entry in _serviceOrderByCategory.entries) {
      if (entry.value.contains(normalized)) {
        return normalizeCategoryId(entry.key);
      }
    }
    return null;
  }

  bool _isModeBlockingService(
    String appKey, {
    String? categoryId,
  }) {
    final normalized = appKey.trim().toLowerCase();
    final modeContext = _activeModeContext();
    final modeOverride = modeContext.overrideSet;
    final resolvedCategory = categoryId == null || categoryId.trim().isEmpty
        ? _categoryIdForService(normalized)
        : normalizeCategoryId(categoryId);
    final modeBlockedByCategory = resolvedCategory != null &&
        modeContext.blockedCategories.contains(resolvedCategory);
    final modeBlockedByOverride = modeOverride?.forceBlockServices
            .map((value) => value.trim().toLowerCase())
            .contains(normalized) ==
        true;
    final modeAllowedByOverride = modeOverride?.forceAllowServices
            .map((value) => value.trim().toLowerCase())
            .contains(normalized) ==
        true;
    return (modeContext.blocksAll ||
            modeBlockedByCategory ||
            modeBlockedByOverride) &&
        !modeAllowedByOverride;
  }

  void _addModeServiceAllowOverride({
    required String modeKey,
    required String serviceId,
  }) {
    final normalizedMode = modeKey.trim().toLowerCase();
    final normalizedService = serviceId.trim().toLowerCase();
    final current = _modeOverrides[normalizedMode] ?? const ModeOverrideSet();
    final nextAllowServices = <String>{
      ...current.forceAllowServices
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty),
      normalizedService,
    }.toList()
      ..sort();
    final nextBlockServices = current.forceBlockServices
        .map((value) => value.trim().toLowerCase())
        .where(
          (value) => value.isNotEmpty && value != normalizedService,
        )
        .toSet()
        .toList()
      ..sort();
    final updated = current.copyWith(
      forceAllowServices: nextAllowServices,
      forceBlockServices: nextBlockServices,
    );
    if (updated.isEmpty) {
      _modeOverrides.remove(normalizedMode);
    } else {
      _modeOverrides[normalizedMode] = updated;
    }
  }

  void _removeModeServiceAllowOverride({
    required String modeKey,
    required String serviceId,
  }) {
    final normalizedMode = modeKey.trim().toLowerCase();
    final normalizedService = serviceId.trim().toLowerCase();
    final current = _modeOverrides[normalizedMode];
    if (current == null) {
      return;
    }
    final nextAllowServices = current.forceAllowServices
        .map((value) => value.trim().toLowerCase())
        .where(
          (value) => value.isNotEmpty && value != normalizedService,
        )
        .toSet()
        .toList()
      ..sort();
    final updated = current.copyWith(forceAllowServices: nextAllowServices);
    if (updated.isEmpty) {
      _modeOverrides.remove(normalizedMode);
    } else {
      _modeOverrides[normalizedMode] = updated;
    }
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

    final normalizedServiceId = appKey.trim().toLowerCase();
    final service = ServiceDefinitions.byId[normalizedServiceId];
    if (service == null) {
      return;
    }

    final categoryBlocked =
        categoryId != null && _isCategoryBlocked(categoryId);
    final modeContext = _activeModeContext();
    final activeModeKey = modeContext.modeKey;
    final modeBlockingThisService = _isModeBlockingService(
      normalizedServiceId,
      categoryId: categoryId,
    );
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
        _blockedServices.add(normalizedServiceId);
        if (activeModeKey != null && RolloutFlags.modeAppOverrides) {
          _removeModeServiceAllowOverride(
            modeKey: activeModeKey,
            serviceId: normalizedServiceId,
          );
        }
      } else {
        _blockedServices.remove(normalizedServiceId);
        if (activeModeKey != null && RolloutFlags.modeAppOverrides) {
          if (modeBlockingThisService) {
            _addModeServiceAllowOverride(
              modeKey: activeModeKey,
              serviceId: normalizedServiceId,
            );
          } else {
            _removeModeServiceAllowOverride(
              modeKey: activeModeKey,
              serviceId: normalizedServiceId,
            );
          }
        }
      }
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
    if (!enabled && categoryBlocked && !modeBlockingThisService && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_appLabel(appKey)} is still blocked because ${_prettyLabel(categoryId)} is ON.',
          ),
        ),
      );
    } else if (!enabled &&
        modeBlockingThisService &&
        modeContext.modeLabel != null &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_appLabel(appKey)} is now allowed for ${modeContext.modeLabel}.',
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

    final normalizedCategoryId = normalizeCategoryId(categoryId);
    final modeContext = _activeModeContext();
    final activeModeKey = modeContext.modeKey;
    final blockedByModeBeforeToggle =
        _effectiveCategoryState(normalizedCategoryId).blockedByMode;

    setState(() {
      if (enabled) {
        _blockedCategories.add(normalizedCategoryId);
        _expandedCategoryIds.add(normalizedCategoryId);
        if (activeModeKey != null && RolloutFlags.modeAppOverrides) {
          _removeModeCategoryAllowOverrides(
            modeKey: activeModeKey,
            categoryId: normalizedCategoryId,
          );
        }
      } else {
        removeCategoryAndAliases(_blockedCategories, normalizedCategoryId);
        if (activeModeKey != null && RolloutFlags.modeAppOverrides) {
          if (blockedByModeBeforeToggle) {
            _addModeCategoryAllowOverrides(
              modeKey: activeModeKey,
              categoryId: normalizedCategoryId,
            );
          } else {
            _removeModeCategoryAllowOverrides(
              modeKey: activeModeKey,
              categoryId: normalizedCategoryId,
            );
          }
        }
      }
    });
    unawaited(
      _emitBlockAppsDebugEvent(
        eventType: 'toggle_tapped',
        payload: <String, dynamic>{
          'targetType': 'category',
          'targetId': normalizedCategoryId,
          'targetLabel': _prettyLabel(normalizedCategoryId),
          'enabled': enabled,
          'effectiveBlockedAfterTap':
              _effectiveCategoryState(normalizedCategoryId).blocked,
        },
      ),
    );
    await _autoSaveToggleChanges();
    await _syncNextDnsCategoryForLocalToggle(
      localCategoryId: normalizeCategoryId(categoryId),
      blocked: enabled,
    );
    if (enabled && mounted) {
      _showNewConnectionsHint();
    }
    if (!enabled &&
        blockedByModeBeforeToggle &&
        modeContext.modeLabel != null &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_prettyLabel(normalizedCategoryId)} is now allowed for ${modeContext.modeLabel}.',
          ),
        ),
      );
    }
  }

  void _showNewConnectionsHint() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'New blocks apply to new connections. If a site is already open, '
          'close and reopen the browser.',
        ),
      ),
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
        return category?.description ?? 'Restricted by current controls';
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

  IconData _installedAppIcon(String packageName) {
    switch (packageName) {
      case 'com.whatsapp':
      case 'com.whatsapp.w4b':
        return Icons.chat_rounded;
      case 'com.instagram.android':
        return Icons.camera_alt_rounded;
      case 'com.google.android.youtube':
      case 'com.google.android.apps.youtube.music':
        return Icons.play_circle_fill_rounded;
      case 'com.snapchat.android':
        return Icons.tag_faces_rounded;
      case 'com.pubg.imobile':
      case 'com.dts.freefireth':
        return Icons.sports_esports_rounded;
      case 'in.mohalla.sharechat':
      case 'com.boloindya.boloindya':
      case 'com.eterno':
        return Icons.groups_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  Uint8List? _installedAppIconBytes(InstalledAppInfo app) {
    final packageName = app.packageName.trim().toLowerCase();
    if (_installedAppIconBytesCache.containsKey(packageName)) {
      return _installedAppIconBytesCache[packageName];
    }

    final raw = app.appIconBase64?.trim();
    if (raw == null || raw.isEmpty) {
      _installedAppIconBytesCache[packageName] = null;
      return null;
    }

    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) {
        _installedAppIconBytesCache[packageName] = null;
        return null;
      }
      _installedAppIconBytesCache[packageName] = bytes;
      return bytes;
    } catch (_) {
      _installedAppIconBytesCache[packageName] = null;
      return null;
    }
  }

  Schedule? _activeScheduleAt(DateTime now) {
    final today = Day.fromDateTime(now);
    final yesterday = Day.fromDateTime(now.subtract(const Duration(days: 1)));
    for (final schedule in _currentChildContext.policy.schedules) {
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

  Map<String, ModeOverrideSet> _normalizeModeOverrideSets(
    Map<String, ModeOverrideSet> source,
  ) {
    final normalized = <String, ModeOverrideSet>{};
    for (final entry in source.entries) {
      final modeKey = entry.key.trim().toLowerCase();
      if (modeKey.isEmpty) {
        continue;
      }
      final value = entry.value;
      final normalizedValue = ModeOverrideSet(
        forceBlockServices: value.forceBlockServices
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort(),
        forceAllowServices: value.forceAllowServices
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort(),
        forceBlockPackages: value.forceBlockPackages
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort(),
        forceAllowPackages: value.forceAllowPackages
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort(),
        forceBlockDomains: value.forceBlockDomains
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort(),
        forceAllowDomains: value.forceAllowDomains
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort(),
      );
      if (normalizedValue.isEmpty) {
        continue;
      }
      normalized[modeKey] = normalizedValue;
    }
    return normalized;
  }

  Map<String, ModeOverrideSet> _cloneModeOverrides(
    Map<String, ModeOverrideSet> source,
  ) {
    return _normalizeModeOverrideSets(source);
  }

  bool _sameModeOverrides(
    Map<String, ModeOverrideSet> left,
    Map<String, ModeOverrideSet> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      final rightValue = right[entry.key];
      if (rightValue == null) {
        return false;
      }
      if (!_sameModeOverrideSet(entry.value, rightValue)) {
        return false;
      }
    }
    return true;
  }

  bool _sameModeOverrideSet(ModeOverrideSet left, ModeOverrideSet right) {
    bool sameList(List<String> a, List<String> b) {
      final setA = a
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      final setB = b
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      return _setEquals(setA, setB);
    }

    return sameList(left.forceBlockServices, right.forceBlockServices) &&
        sameList(left.forceAllowServices, right.forceAllowServices) &&
        sameList(left.forceBlockPackages, right.forceBlockPackages) &&
        sameList(left.forceAllowPackages, right.forceAllowPackages) &&
        sameList(left.forceBlockDomains, right.forceBlockDomains) &&
        sameList(left.forceAllowDomains, right.forceAllowDomains);
  }

  void _hydrateNextDnsControls() {
    final controls = _currentChildContext.nextDnsControls;
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
      childId: _currentChildContext.id,
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
            'Could not update ${_prettyLabel(localCategoryId)} right now.',
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
                ? 'Could not block $domain right now.'
                : 'Could not unblock $domain right now.',
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
        const SnackBar(
            content: Text('Could not update app control right now.')),
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
        const SnackBar(
            content: Text('Could not update web controls right now.')),
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
              'ADVANCED WEB CONTROLS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Connected profile: $profileId',
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
              subtitle: const Text('Reduce easy bypass tricks'),
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

  Widget _buildModeSourceBadge(String? modeLabel) {
    final label = modeLabel?.trim().isNotEmpty == true
        ? modeLabel!.trim()
        : 'current mode';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'from $label',
        style: TextStyle(
          color: Colors.deepOrange.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
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
        'Advanced',
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

  String get normalizedApplyStatus => applyStatus.trim().toLowerCase();

  bool get isAppliedSuccess => normalizedApplyStatus == 'applied';

  bool get hasFailureStatus {
    final status = normalizedApplyStatus;
    return status == 'failed' || status == 'error' || status == 'mismatch';
  }

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
