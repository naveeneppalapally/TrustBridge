import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/l10n/app_localizations.dart';
import 'package:trustbridge_app/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/screens/child_detail_screen.dart';
import 'package:trustbridge_app/screens/parent_settings_screen.dart';
import 'package:trustbridge_app/services/app_mode_service.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/heartbeat_service.dart';
import 'package:trustbridge_app/services/performance_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';
import 'package:trustbridge_app/utils/app_lock_guard.dart';
import 'package:trustbridge_app/utils/spring_animation.dart';
import 'package:trustbridge_app/widgets/child_card.dart';
import 'package:trustbridge_app/widgets/empty_state.dart';
import 'package:trustbridge_app/widgets/skeleton_loaders.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
    this.onShellTabRequested,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;
  final ValueChanged<int>? onShellTabRequested;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const Duration _deviceOnlineWindow = Duration(minutes: 2);
  static const Duration _deviceWarningWindow = Duration(minutes: 10);
  static const Duration _deviceCriticalWindow = Duration(hours: 24);
  static const Duration _policyAckAtRiskWindow = Duration(minutes: 10);
  static const Duration _policyAckUnprotectedWindow = Duration(minutes: 30);
  AuthService? _authService;
  FirestoreService? _firestoreService;
  Stream<List<ChildProfile>>? _childrenStream;
  Stream<List<AccessRequest>>? _pendingRequestsStream;
  Stream<Map<String, dynamic>?>? _parentProfileStream;
  String? _streamsParentId;
  final PerformanceService _performanceService = PerformanceService();
  PerformanceTrace? _dashboardLoadTrace;
  Stopwatch? _dashboardLoadStopwatch;
  bool _isUpdatingPauseAll = false;
  bool _fabVisible = false;
  String _lastHealthFingerprint = '';
  final Map<String, _ChildDeviceHealth> _deviceHealthByChildId =
      <String, _ChildDeviceHealth>{};
  final Set<String> _offline24hAlertedDeviceIds = <String>{};
  Timer? _deviceHealthRefreshTimer;
  List<ChildProfile> _latestChildrenForHealth = const <ChildProfile>[];
  String? _latestParentIdForHealth;
  bool _isRefreshingDeviceHealth = false;
  StreamSubscription<Map<String, DeviceStatusSnapshot>>?
      _deviceHeartbeatSubscription;
  String _heartbeatSubscriptionFingerprint = '';
  Map<String, DeviceStatusSnapshot> _latestDeviceStatusByDeviceId =
      const <String, DeviceStatusSnapshot>{};
  String _usageSubscriptionFingerprint = '';
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _usageReportSubscriptionsByChildId =
      <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
  final Map<String, _ChildUsageSnapshot> _latestUsageByChildId =
      <String, _ChildUsageSnapshot>{};
  String _policyAckSubscriptionFingerprint = '';
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _policyAckSubscriptionsByChildId =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, _ChildPolicyAckSnapshot> _latestPolicyAckByChildId =
      <String, _ChildPolicyAckSnapshot>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startDashboardLoadTrace());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fabVisible = true;
      });
    });
    _deviceHealthRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshDeviceHealthFromLatestState()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceHealthRefreshTimer?.cancel();
    _deviceHeartbeatSubscription?.cancel();
    for (final subscription in _usageReportSubscriptionsByChildId.values) {
      subscription.cancel();
    }
    _usageReportSubscriptionsByChildId.clear();
    for (final subscription in _policyAckSubscriptionsByChildId.values) {
      subscription.cancel();
    }
    _policyAckSubscriptionsByChildId.clear();
    unawaited(_stopDashboardLoadTrace());
    super.dispose();
  }

  Future<void> _startDashboardLoadTrace() async {
    final trace = await _performanceService.startTrace('dashboard_load');
    if (!mounted) {
      await _performanceService.stopTrace(trace);
      return;
    }
    _dashboardLoadTrace = trace;
    _dashboardLoadStopwatch = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_stopDashboardLoadTrace());
    });
  }

  Future<void> _stopDashboardLoadTrace() async {
    final trace = _dashboardLoadTrace;
    if (trace == null) {
      return;
    }
    _dashboardLoadTrace = null;
    final stopwatch = _dashboardLoadStopwatch;
    _dashboardLoadStopwatch = null;
    if (stopwatch != null) {
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.annotateThreshold(
        trace: trace,
        name: 'dashboard_load_ms',
        actualValue: stopwatch.elapsedMilliseconds,
        warningValue: PerformanceThresholds.dashboardLoadWarningMs,
      );
    }
    await _performanceService.stopTrace(trace);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      context.read<PolicyVpnSyncService?>()?.syncNow();
    }
  }

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  String? get _parentId {
    return widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
  }

  void _ensureParentStreams(String parentId) {
    if (_streamsParentId == parentId &&
        _childrenStream != null &&
        _pendingRequestsStream != null &&
        _parentProfileStream != null) {
      return;
    }

    _streamsParentId = parentId;
    _childrenStream = _resolvedFirestoreService.getChildrenStream(parentId);
    _pendingRequestsStream =
        _resolvedFirestoreService.getPendingRequestsStream(parentId);
    _parentProfileStream = _resolvedFirestoreService.watchParentProfile(
      parentId,
    );
  }

  Future<void> _handleSignOut() async {
    await _resolvedAuthService.signOut();
    await AppModeService().clearMode();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed('/welcome');
  }

  Future<void> _openSettings() async {
    await guardedNavigate(
      context,
      () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ParentSettingsScreen(
              authService: widget.authService,
              firestoreService: widget.firestoreService,
              parentIdOverride: widget.parentIdOverride,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestsAction() {
    final l10n = _l10n(context);
    final pendingRequestsStream = _pendingRequestsStream;
    if (pendingRequestsStream == null) {
      return IconButton(
        key: const Key('dashboard_requests_button'),
        icon: const Icon(Icons.notifications_outlined),
        tooltip: l10n.accessRequestsTitle,
        onPressed: () {
          Navigator.of(context).pushNamed('/parent-requests');
        },
      );
    }

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>('dashboard_pending_${_streamsParentId ?? 'none'}'),
      stream: pendingRequestsStream,
      builder:
          (BuildContext context, AsyncSnapshot<List<AccessRequest>> snapshot) {
        final pendingCount = snapshot.data?.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            IconButton(
              key: const Key('dashboard_requests_button'),
              icon: const Icon(Icons.notifications_outlined),
              tooltip: l10n.accessRequestsTitle,
              onPressed: () {
                Navigator.of(context).pushNamed('/parent-requests');
              },
            ),
            if (pendingCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  key: const Key('dashboard_requests_badge'),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      pendingCount > 9 ? '9+' : '$pendingCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderMenu() {
    final l10n = _l10n(context);
    return PopupMenuButton<String>(
      key: const Key('dashboard_header_menu'),
      icon: const Icon(Icons.more_horiz),
      tooltip: 'More actions',
      onSelected: (String value) async {
        switch (value) {
          case 'analytics':
            Navigator.of(context).pushNamed('/dns-analytics');
            break;
          case 'settings':
            await _openSettings();
            break;
          case 'signout':
            await _handleSignOut();
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'analytics',
          child: Text(l10n.analyticsTitle),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Text(l10n.settingsTitle),
        ),
        const PopupMenuItem<String>(
          value: 'signout',
          child: Text('Sign out'),
        ),
      ],
    );
  }

  String _greetingForTime(DateTime now) {
    final hour = now.hour;
    if (hour < 12) {
      return 'Good Morning';
    }
    if (hour < 17) {
      return 'Good Afternoon';
    }
    return 'Good Evening';
  }

  String _resolveParentName(Map<String, dynamic>? parentProfile) {
    final nestedProfile = _asMap(parentProfile?['parentProfile']);
    final nestedName = _stringOrNull(nestedProfile['displayName']);
    if (nestedName != null && nestedName.isNotEmpty) {
      return nestedName;
    }

    final rootName = _stringOrNull(parentProfile?['displayName']);
    if (rootName != null && rootName.isNotEmpty) {
      return rootName;
    }

    final email = _stringOrNull(parentProfile?['email']) ?? '';
    if (email.contains('@')) {
      final prefix = email.split('@').first.trim();
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
    }

    return 'Parent';
  }

  bool _isShieldActive(Map<String, dynamic>? parentProfile) {
    final preferences = _asMap(parentProfile?['preferences']);
    return preferences['vpnProtectionEnabled'] == true;
  }

  bool _isPausedNow(ChildProfile child) {
    final pausedUntil = child.pausedUntil;
    return pausedUntil != null && pausedUntil.isAfter(DateTime.now());
  }

  Future<void> _toggleChildPause(ChildProfile child) async {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return;
    }

    final willResume = _isPausedNow(child);
    final pausedUntil =
        willResume ? null : DateTime.now().add(const Duration(hours: 1));

    try {
      await _resolvedFirestoreService.setChildPause(
        parentId: parentId,
        childId: child.id,
        pausedUntil: pausedUntil,
      );
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(willResume
              ? 'Internet resumed for ${child.nickname}'
              : 'Internet paused for ${child.nickname}'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update child pause state: $error')),
      );
    }
  }

  void _openLocateStub(ChildProfile child) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Live location for ${child.nickname} is unavailable right now.'),
      ),
    );
  }

  void _openManageDevicesStub() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Device management is unavailable right now.'),
      ),
    );
  }

  Future<void> _togglePauseAllDevices({
    required bool pauseAll,
    required String parentId,
  }) async {
    if (_isUpdatingPauseAll) {
      return;
    }

    setState(() {
      _isUpdatingPauseAll = true;
    });
    try {
      if (pauseAll) {
        await _resolvedFirestoreService.pauseAllChildren(parentId);
      } else {
        await _resolvedFirestoreService.resumeAllChildren(parentId);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pauseAll
                ? 'All child devices are now paused.'
                : 'All child devices resumed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update pause-all: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingPauseAll = false;
        });
      }
    }
  }

  void _openScheduleTabFromQuickAction() {
    final callback = widget.onShellTabRequested;
    if (callback != null) {
      callback(1);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Open Modes from parent shell to configure bedtime.'),
      ),
    );
  }

  double _screenTimeProgress(List<ChildProfile> children) {
    if (children.isEmpty) {
      return 0;
    }

    var totalDailyScreenTimeMinutes = 0;
    var totalDailyLimitMinutes = 0;
    for (final child in children) {
      final usage = _latestUsageByChildId[child.id];
      final estimatedDailyMs = usage?.estimatedDailyScreenTimeMs ?? 0;
      totalDailyScreenTimeMinutes +=
          estimatedDailyMs ~/ Duration.millisecondsPerMinute;
      totalDailyLimitMinutes += _dailyUsageLimitMinutes(child);
    }

    if (totalDailyLimitMinutes <= 0) {
      return 0;
    }
    return (totalDailyScreenTimeMinutes / totalDailyLimitMinutes)
        .clamp(0.0, 1.0);
  }

  String _screenTimeLabel(List<ChildProfile> children) {
    var totalEstimatedDailyMs = 0;
    for (final child in children) {
      totalEstimatedDailyMs +=
          _latestUsageByChildId[child.id]?.estimatedDailyScreenTimeMs ?? 0;
    }
    if (totalEstimatedDailyMs <= 0) {
      return '--';
    }
    return _formatDurationCompact(
        Duration(milliseconds: totalEstimatedDailyMs));
  }

  String _blockedAttemptsLabel(List<ChildProfile> children) {
    return '${_blockedAttemptsCount(children)}';
  }

  int _blockedAttemptsCount(List<ChildProfile> children) {
    if (children.isEmpty) {
      return 0;
    }
    var totalBlocked = 0;
    for (final child in children) {
      for (final deviceId in child.deviceIds) {
        totalBlocked +=
            _latestDeviceStatusByDeviceId[deviceId]?.queriesBlocked ?? 0;
      }
    }
    return totalBlocked;
  }

  int _dailyUsageLimitMinutes(ChildProfile child) {
    switch (child.ageBand) {
      case AgeBand.young:
        return 120;
      case AgeBand.middle:
        return 150;
      case AgeBand.teen:
        return 180;
    }
  }

  int? _usageMinutesForChildCard(String childId) {
    final usage = _latestUsageByChildId[childId];
    if (usage == null || !usage.hasData) {
      return null;
    }
    return usage.estimatedDailyScreenTimeMs ~/ Duration.millisecondsPerMinute;
  }

  String _formatDurationCompact(Duration duration) {
    final totalMinutes = duration.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) {
      return '${minutes}m';
    }
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }

  void _ensureUsageReportSubscriptions(List<ChildProfile> children) {
    final childIds = children
        .map((child) => child.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    final nextFingerprint = childIds.join('|');
    if (nextFingerprint == _usageSubscriptionFingerprint) {
      return;
    }
    _usageSubscriptionFingerprint = nextFingerprint;

    final nextChildIdSet = childIds.toSet();
    final staleChildIds = _usageReportSubscriptionsByChildId.keys
        .where((childId) => !nextChildIdSet.contains(childId))
        .toList(growable: false);

    for (final childId in staleChildIds) {
      _usageReportSubscriptionsByChildId.remove(childId)?.cancel();
      _latestUsageByChildId.remove(childId);
    }

    for (final childId in childIds) {
      if (_usageReportSubscriptionsByChildId.containsKey(childId)) {
        continue;
      }
      final subscription = _resolvedFirestoreService.firestore
          .collection('children')
          .doc(childId)
          .collection('usage_reports')
          .doc('latest')
          .snapshots()
          .listen((snapshot) {
        if (!mounted) {
          return;
        }
        if (!snapshot.exists) {
          if (_latestUsageByChildId.remove(childId) != null) {
            setState(() {});
          }
          return;
        }
        final data = snapshot.data();
        if (data == null || data.isEmpty) {
          if (_latestUsageByChildId.remove(childId) != null) {
            setState(() {});
          }
          return;
        }

        final usage = _ChildUsageSnapshot.fromMap(data);
        final existing = _latestUsageByChildId[childId];
        if (existing == usage) {
          return;
        }
        _latestUsageByChildId[childId] = usage;
        setState(() {});
      }, onError: (Object error, StackTrace stackTrace) {
        // Usage report access can be absent or temporarily denied; the dashboard
        // should still load live presence and VPN telemetry without crashing.
        if (!mounted) {
          return;
        }
        if (_latestUsageByChildId.remove(childId) != null) {
          setState(() {});
        }
      });
      _usageReportSubscriptionsByChildId[childId] = subscription;
    }
  }

  void _ensurePolicyAckSubscriptions(List<ChildProfile> children) {
    final childIds = children
        .map((child) => child.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    final nextFingerprint = childIds.join('|');
    if (nextFingerprint == _policyAckSubscriptionFingerprint) {
      return;
    }
    _policyAckSubscriptionFingerprint = nextFingerprint;

    final nextChildIdSet = childIds.toSet();
    final staleChildIds = _policyAckSubscriptionsByChildId.keys
        .where((childId) => !nextChildIdSet.contains(childId))
        .toList(growable: false);

    for (final childId in staleChildIds) {
      _policyAckSubscriptionsByChildId.remove(childId)?.cancel();
      _latestPolicyAckByChildId.remove(childId);
    }

    for (final childId in childIds) {
      if (_policyAckSubscriptionsByChildId.containsKey(childId)) {
        continue;
      }
      final subscription = _resolvedFirestoreService.firestore
          .collection('children')
          .doc(childId)
          .collection('policy_apply_acks')
          .snapshots()
          .listen((snapshot) {
        if (!mounted) {
          return;
        }
        if (snapshot.docs.isEmpty) {
          final removed = _latestPolicyAckByChildId.remove(childId) != null;
          if (removed) {
            setState(() {});
            unawaited(_refreshDeviceHealthFromLatestState());
          }
          return;
        }

        _ChildPolicyAckSnapshot? newest;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data.isEmpty) {
            continue;
          }
          final candidate = _ChildPolicyAckSnapshot.fromMap(data);
          if (candidate == null) {
            continue;
          }
          if (newest == null || candidate.sortTime.isAfter(newest.sortTime)) {
            newest = candidate;
          }
        }

        if (newest == null) {
          final removed = _latestPolicyAckByChildId.remove(childId) != null;
          if (removed) {
            setState(() {});
            unawaited(_refreshDeviceHealthFromLatestState());
          }
          return;
        }

        final existing = _latestPolicyAckByChildId[childId];
        if (existing == newest) {
          return;
        }
        _latestPolicyAckByChildId[childId] = newest;
        setState(() {});
        unawaited(_refreshDeviceHealthFromLatestState());
      }, onError: (Object error, StackTrace stackTrace) {
        if (!mounted) {
          return;
        }
        if (_latestPolicyAckByChildId.remove(childId) != null) {
          setState(() {});
          unawaited(_refreshDeviceHealthFromLatestState());
        }
      });
      _policyAckSubscriptionsByChildId[childId] = subscription;
    }
  }

  Map<String, dynamic> _asMap(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }
    if (rawValue is Map) {
      return rawValue.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  String? _stringOrNull(Object? rawValue) {
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return rawValue.trim();
    }
    return null;
  }

  String _childrenHealthFingerprint(List<ChildProfile> children) {
    if (children.isEmpty) {
      return 'none';
    }
    final tokens = <String>[];
    for (final child in children) {
      final deviceIds = child.deviceIds.toList()..sort();
      final ack = _latestPolicyAckByChildId[child.id];
      tokens.add(
        '${child.id}:${deviceIds.join(',')}:'
        '${ack?.applyStatus ?? ''}:'
        '${ack?.vpnRunning == true ? 1 : 0}:'
        '${ack?.usageAccessGranted == false ? 0 : 1}:'
        '${ack?.sortTime.millisecondsSinceEpoch ?? 0}',
      );
    }
    tokens.sort();
    return tokens.join('|');
  }

  Future<void> _refreshDeviceHealth({
    required List<ChildProfile> children,
    required String parentId,
  }) async {
    if (_isRefreshingDeviceHealth) {
      return;
    }
    _isRefreshingDeviceHealth = true;
    final nextState = <String, _ChildDeviceHealth>{};
    try {
      final now = DateTime.now();
      for (final child in children) {
        Duration? mostRecentHeartbeatAge;
        String? mostRecentDeviceId;

        for (final deviceId in child.deviceIds) {
          Duration? age;
          final cachedLastSeen =
              _latestDeviceStatusByDeviceId[deviceId]?.lastSeen;
          if (cachedLastSeen != null) {
            age = now.difference(cachedLastSeen);
          } else {
            try {
              age = await HeartbeatService.timeSinceLastSeen(deviceId);
            } catch (_) {
              // Heartbeat lookup is best-effort and may be unavailable in tests.
              continue;
            }
          }
          if (age == null) {
            continue;
          }
          if (mostRecentHeartbeatAge == null || age < mostRecentHeartbeatAge) {
            mostRecentHeartbeatAge = age;
            mostRecentDeviceId = deviceId;
          }
        }

        if (mostRecentHeartbeatAge == null || mostRecentDeviceId == null) {
          // No heartbeat received yet (device just paired). Show a
          // non-alarming pending/connecting state instead of offline.
          nextState[child.id] = child.deviceIds.isNotEmpty
              ? const _ChildDeviceHealth.pending()
              : const _ChildDeviceHealth.offline();
          continue;
        }

        if (mostRecentHeartbeatAge > _deviceCriticalWindow) {
          nextState[child.id] = const _ChildDeviceHealth.critical();
          if (_offline24hAlertedDeviceIds.add(mostRecentDeviceId)) {
            try {
              await _resolvedFirestoreService.logDeviceOffline24hAlert(
                parentId: parentId,
                childId: child.id,
                childNickname: child.nickname,
                deviceId: mostRecentDeviceId,
              );
            } catch (_) {
              // Best effort alerting.
            }
          }
        } else if (mostRecentHeartbeatAge > _deviceWarningWindow) {
          nextState[child.id] = const _ChildDeviceHealth.warning();
        } else if (mostRecentHeartbeatAge > _deviceOnlineWindow) {
          nextState[child.id] = const _ChildDeviceHealth.offline();
        } else {
          nextState[child.id] = _protectionHealthForOnlineChild(child.id, now);
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _deviceHealthByChildId
          ..clear()
          ..addAll(nextState);
      });
    } finally {
      _isRefreshingDeviceHealth = false;
    }
  }

  _ChildDeviceHealth _protectionHealthForOnlineChild(String childId, DateTime now) {
    final ack = _latestPolicyAckByChildId[childId];
    if (ack == null) {
      return const _ChildDeviceHealth.atRiskNoAck();
    }

    final ackAge = now.difference(ack.sortTime);
    if (!ack.vpnRunning || ack.hasFailureStatus) {
      return const _ChildDeviceHealth.unprotected();
    }
    if (ackAge > _policyAckUnprotectedWindow) {
      return const _ChildDeviceHealth.unprotected();
    }
    if (ackAge > _policyAckAtRiskWindow) {
      return const _ChildDeviceHealth.atRiskStaleAck();
    }
    if (ack.usageAccessGranted == false) {
      return const _ChildDeviceHealth.atRiskPermission();
    }
    return const _ChildDeviceHealth.protected();
  }

  Future<void> _refreshDeviceHealthFromLatestState() async {
    final parentId = _latestParentIdForHealth;
    if (parentId == null || parentId.trim().isEmpty) {
      return;
    }
    if (_latestChildrenForHealth.isEmpty) {
      return;
    }
    await _refreshDeviceHealth(
      children: _latestChildrenForHealth,
      parentId: parentId,
    );
  }

  void _ensureHeartbeatSubscription({
    required List<ChildProfile> children,
    required String parentId,
  }) {
    final allDeviceIds = children
        .expand((child) => child.deviceIds)
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    final childIdByDeviceId = <String, String>{};
    for (final child in children) {
      for (final rawDeviceId in child.deviceIds) {
        final deviceId = rawDeviceId.trim();
        if (deviceId.isEmpty) {
          continue;
        }
        childIdByDeviceId.putIfAbsent(deviceId, () => child.id);
      }
    }

    final nextFingerprint = allDeviceIds.join('|');
    if (nextFingerprint == _heartbeatSubscriptionFingerprint) {
      return;
    }
    _heartbeatSubscriptionFingerprint = nextFingerprint;

    _deviceHeartbeatSubscription?.cancel();
    _deviceHeartbeatSubscription = null;
    _latestDeviceStatusByDeviceId = const <String, DeviceStatusSnapshot>{};

    if (allDeviceIds.isEmpty) {
      return;
    }

    _deviceHeartbeatSubscription = _resolvedFirestoreService
        .watchDeviceStatuses(
          allDeviceIds,
          parentId: parentId,
          childIdByDeviceId: childIdByDeviceId,
        )
        .listen((statusMap) {
      _latestDeviceStatusByDeviceId = statusMap;
      unawaited(
        _refreshDeviceHealth(
          children: _latestChildrenForHealth,
          parentId: parentId,
        ),
      );
    }, onError: (Object error, StackTrace stackTrace) {
      // Presence data is best-effort. Permission gaps or transient backend
      // failures should not crash the dashboard.
      _latestDeviceStatusByDeviceId = const <String, DeviceStatusSnapshot>{};
      if (!mounted) {
        return;
      }
      unawaited(
        _refreshDeviceHealth(
          children: _latestChildrenForHealth,
          parentId: parentId,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final parentId = _parentId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).cardColor;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    if (parentId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.appTitle)),
        body: Center(child: Text(l10n.notLoggedInMessage)),
      );
    }
    _ensureParentStreams(parentId);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _parentProfileStream,
        builder: (
          BuildContext context,
          AsyncSnapshot<Map<String, dynamic>?> parentSnapshot,
        ) {
          final parentProfile = parentSnapshot.data;
          final parentName = _resolveParentName(parentProfile);
          final greeting = _greetingForTime(DateTime.now());
          final shieldActive = _isShieldActive(parentProfile);

          return StreamBuilder<List<ChildProfile>>(
            key: ValueKey<String>(
              'dashboard_children_${_streamsParentId ?? 'none'}',
            ),
            stream: _childrenStream,
            builder: (context, snapshot) {
              final width = MediaQuery.sizeOf(context).width;
              final isTablet = width >= 600;

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return _buildLoadingState(
                  backgroundColor: backgroundColor,
                  isTablet: isTablet,
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 52,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Unable to load dashboard',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: () => setState(() {}),
                          child: Text(l10n.retryButton),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final children = snapshot.data ?? const <ChildProfile>[];
              _latestChildrenForHealth = children;
              _latestParentIdForHealth = parentId;
              _ensureHeartbeatSubscription(
                children: children,
                parentId: parentId,
              );
              _ensureUsageReportSubscriptions(children);
              _ensurePolicyAckSubscriptions(children);
              final healthFingerprint = _childrenHealthFingerprint(children);
              if (healthFingerprint != _lastHealthFingerprint) {
                _lastHealthFingerprint = healthFingerprint;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) {
                    return;
                  }
                  unawaited(
                    _refreshDeviceHealth(
                      children: children,
                      parentId: parentId,
                    ),
                  );
                });
              }
              final screenTimeLabel = _screenTimeLabel(children);
              final blockedAttemptsLabel = _blockedAttemptsLabel(children);
              final allChildrenPaused =
                  children.isNotEmpty && children.every(_isPausedNow);

              if (children.isEmpty) {
                return CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      floating: false,
                      expandedHeight: 64,
                      backgroundColor: backgroundColor,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      title: Text(l10n.dashboardTitle),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isTablet ? 24 : 16,
                          16,
                          isTablet ? 24 : 16,
                          0,
                        ),
                        child: _DashboardHeader(
                          greeting: greeting,
                          parentName: parentName,
                          requestsAction: _buildRequestsAction(),
                          menuAction: _buildHeaderMenu(),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isTablet ? 24 : 16,
                          16,
                          isTablet ? 24 : 16,
                          0,
                        ),
                        child: _TrustSummaryCard(
                          key: const Key('dashboard_trust_summary_card'),
                          surfaceColor: surfaceColor,
                          isDark: isDark,
                          shieldActive: shieldActive,
                          totalScreenTime: screenTimeLabel,
                          blockedAttempts: blockedAttemptsLabel,
                          progress: _screenTimeProgress(children),
                        ),
                      ),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: const Text(
                            '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'),
                        title: 'Add your first child',
                        subtitle: 'Get started by adding a child profile.',
                        actionLabel: l10n.addChildButton,
                        onAction: () {
                          Navigator.of(context).push(
                            SpringAnimation.slidePageRoute(
                              builder: (_) => const AddChildScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              }

              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    expandedHeight: 64,
                    backgroundColor: backgroundColor,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    title: Text(l10n.dashboardTitle),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 24 : 16,
                        16,
                        isTablet ? 24 : 16,
                        0,
                      ),
                      child: _DashboardHeader(
                        greeting: greeting,
                        parentName: parentName,
                        requestsAction: _buildRequestsAction(),
                        menuAction: _buildHeaderMenu(),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 24 : 16,
                        16,
                        isTablet ? 24 : 16,
                        0,
                      ),
                      child: _TrustSummaryCard(
                        key: const Key('dashboard_trust_summary_card'),
                        surfaceColor: surfaceColor,
                        isDark: isDark,
                        shieldActive: shieldActive,
                        totalScreenTime: screenTimeLabel,
                        blockedAttempts: blockedAttemptsLabel,
                        progress: _screenTimeProgress(children),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 24 : 16,
                        18,
                        isTablet ? 24 : 16,
                        10,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'MANAGED DEVICES',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.w800,
                                    ),
                          ),
                          const Spacer(),
                          TextButton(
                            key: const Key('dashboard_view_all_devices_button'),
                            onPressed: _openManageDevicesStub,
                            child: const Text('View All'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      isTablet ? 24 : 16,
                      0,
                      isTablet ? 24 : 16,
                      12,
                    ),
                    sliver: isTablet
                        ? SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.95,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final child = children[index];
                                final health =
                                    _deviceHealthByChildId[child.id] ??
                                        const _ChildDeviceHealth.offline();
                                return ChildCard(
                                  child: child,
                                  usageMinutesOverride:
                                      _usageMinutesForChildCard(child.id),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      SpringAnimation.slidePageRoute(
                                        builder: (_) => ChildDetailScreen(
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                                  onPauseInternet: () =>
                                      _toggleChildPause(child),
                                  onResumeInternet: () =>
                                      _toggleChildPause(child),
                                  onLocate: () => _openLocateStub(child),
                                  onlineOverride: health.online,
                                  deviceHealthStatusLabel: health.label,
                                  deviceHealthStatusColor: health.color,
                                );
                              },
                              childCount: children.length,
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final child = children[index];
                                final health =
                                    _deviceHealthByChildId[child.id] ??
                                        const _ChildDeviceHealth.offline();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: ChildCard(
                                    child: child,
                                    usageMinutesOverride:
                                        _usageMinutesForChildCard(child.id),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        SpringAnimation.slidePageRoute(
                                          builder: (_) => ChildDetailScreen(
                                            child: child,
                                          ),
                                        ),
                                      );
                                    },
                                    onPauseInternet: () =>
                                        _toggleChildPause(child),
                                    onResumeInternet: () =>
                                        _toggleChildPause(child),
                                    onLocate: () => _openLocateStub(child),
                                    onlineOverride: health.online,
                                    deviceHealthStatusLabel: health.label,
                                    deviceHealthStatusColor: health.color,
                                  ),
                                );
                              },
                              childCount: children.length,
                            ),
                          ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 24 : 16,
                        8,
                        isTablet ? 24 : 16,
                        16,
                      ),
                      child: _SecurityQuickActionsCard(
                        pauseAllEnabled: allChildrenPaused,
                        pauseAllBusy: _isUpdatingPauseAll,
                        onPauseAllChanged: (bool value) {
                          unawaited(
                            _togglePauseAllDevices(
                              pauseAll: value,
                              parentId: parentId,
                            ),
                          );
                        },
                        onBedtimeTap: _openScheduleTabFromQuickAction,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 24 : 16,
                        0,
                        isTablet ? 24 : 16,
                        100,
                      ),
                      child: InkWell(
                        key: const Key('dashboard_connect_new_device_cta'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: _openManageDevicesStub,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.5),
                              style: BorderStyle.solid,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Connect New Device',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            SpringAnimation.slidePageRoute(
              builder: (_) => const AddChildScreen(),
            ),
          );
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 420),
          curve: SpringAnimation.springCurve,
          scale: _fabVisible ? 1.0 : 0.8,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildLoadingState({
    required Color backgroundColor,
    required bool isTablet,
  }) {
    final l10n = _l10n(context);
    final horizontalPadding = isTablet ? 24.0 : 16.0;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          floating: false,
          expandedHeight: 64,
          backgroundColor: backgroundColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(l10n.dashboardTitle),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              0,
            ),
            child: const Column(
              children: <Widget>[
                SkeletonCard(height: 90),
                SizedBox(height: 16),
                SkeletonCard(height: 170),
                SizedBox(height: 16),
                SkeletonCard(height: 90),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              100,
            ),
            child: const Column(
              children: <Widget>[
                SkeletonChildCard(),
                SizedBox(height: 12),
                SkeletonChildCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.greeting,
    required this.parentName,
    required this.requestsAction,
    required this.menuAction,
  });

  final String greeting;
  final String parentName;
  final Widget requestsAction;
  final Widget menuAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                parentName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
        requestsAction,
        menuAction,
      ],
    );
  }
}

class _TrustSummaryCard extends StatelessWidget {
  const _TrustSummaryCard({
    super.key,
    required this.surfaceColor,
    required this.isDark,
    required this.shieldActive,
    required this.totalScreenTime,
    required this.blockedAttempts,
    required this.progress,
  });

  final Color surfaceColor;
  final bool isDark;
  final bool shieldActive;
  final String totalScreenTime;
  final String blockedAttempts;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Trust Summary',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: shieldActive
                      ? const Color(0xFF1E88E5).withValues(alpha: 0.14)
                      : Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  shieldActive ? 'SHIELD ACTIVE' : 'SHIELD OFF',
                  style: TextStyle(
                    color: shieldActive
                        ? const Color(0xFF1E88E5)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TrustMetricTile(
                  label: 'TOTAL SCREEN TIME',
                  valueKey: const Key('dashboard_metric_total_screen_time_value'),
                  value: totalScreenTime,
                  trailingLabel: 'Today',
                  valueColor: Theme.of(context).textTheme.titleLarge?.color ??
                      Theme.of(context).colorScheme.onSurface,
                  progress: progress,
                  progressColor: Theme.of(context).colorScheme.primary,
                  progressTrackColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TrustMetricTile(
                  label: 'BLOCKED ATTEMPTS',
                  valueKey: const Key('dashboard_metric_blocked_attempts_value'),
                  value: blockedAttempts,
                  trailingLabel: 'From child VPN telemetry',
                  valueColor: blockedAttempts == '0'
                      ? const Color(0xFF00A86B)
                      : Theme.of(context).colorScheme.error,
                  progress: 0,
                  progressColor: Colors.transparent,
                  progressTrackColor: Colors.transparent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustMetricTile extends StatelessWidget {
  const _TrustMetricTile({
    required this.label,
    this.valueKey,
    required this.value,
    required this.trailingLabel,
    required this.valueColor,
    required this.progress,
    required this.progressColor,
    required this.progressTrackColor,
  });

  final String label;
  final Key? valueKey;
  final String value;
  final String trailingLabel;
  final Color valueColor;
  final double progress;
  final Color progressColor;
  final Color progressTrackColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            key: valueKey,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
          ),
          const SizedBox(height: 10),
          if (progress > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: progress,
                backgroundColor: progressTrackColor,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
          if (progress > 0) const SizedBox(height: 8),
          Text(
            trailingLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _SecurityQuickActionsCard extends StatelessWidget {
  const _SecurityQuickActionsCard({
    required this.pauseAllEnabled,
    required this.pauseAllBusy,
    required this.onPauseAllChanged,
    required this.onBedtimeTap,
  });

  final bool pauseAllEnabled;
  final bool pauseAllBusy;
  final ValueChanged<bool> onPauseAllChanged;
  final VoidCallback onBedtimeTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Security Quick-Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        Card(
          key: const Key('dashboard_security_quick_actions_card'),
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFEF4444).withValues(
                    alpha: 0.14,
                  ),
                  child: const Icon(
                    Icons.pause_circle_outline,
                    color: Color(0xFFEF4444),
                    size: 18,
                  ),
                ),
                title: const Text('Pause All Devices'),
                subtitle: const Text('Instantly stop all screen time'),
                trailing: Switch(
                  key: const Key('dashboard_pause_all_switch'),
                  value: pauseAllEnabled,
                  onChanged: pauseAllBusy ? null : onPauseAllChanged,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('dashboard_bedtime_schedule_button'),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF6366F1).withValues(
                    alpha: 0.14,
                  ),
                  child: const Icon(
                    Icons.nights_stay_outlined,
                    color: Color(0xFF6366F1),
                    size: 18,
                  ),
                ),
                title: const Text('Bedtime Schedule'),
                subtitle: const Text('Active starting at 9:00 PM'),
                trailing: IconButton(
                  onPressed: onBedtimeTap,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                onTap: onBedtimeTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

AppLocalizations _l10n(BuildContext context) {
  return AppLocalizations.of(context) ?? AppLocalizationsEn();
}

class _ChildUsageSnapshot {
  const _ChildUsageSnapshot({
    required this.totalScreenTimeMs,
    required this.averageDailyScreenTimeMs,
    this.uploadedAt,
  });

  final int totalScreenTimeMs;
  final int averageDailyScreenTimeMs;
  final DateTime? uploadedAt;

  bool get hasData => totalScreenTimeMs > 0 || averageDailyScreenTimeMs > 0;

  int get estimatedDailyScreenTimeMs {
    if (averageDailyScreenTimeMs > 0) {
      return averageDailyScreenTimeMs;
    }
    if (totalScreenTimeMs > 0) {
      return totalScreenTimeMs ~/ 7;
    }
    return 0;
  }

  factory _ChildUsageSnapshot.fromMap(Map<String, dynamic> data) {
    return _ChildUsageSnapshot(
      totalScreenTimeMs: _toInt(data['totalScreenTimeMs']),
      averageDailyScreenTimeMs: _toInt(data['averageDailyScreenTimeMs']),
      uploadedAt: _toDateTime(data['uploadedAt']),
    );
  }

  static int _toInt(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return 0;
  }

  static DateTime? _toDateTime(Object? rawValue) {
    if (rawValue is Timestamp) {
      return rawValue.toDate();
    }
    if (rawValue is DateTime) {
      return rawValue;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _ChildUsageSnapshot &&
        other.totalScreenTimeMs == totalScreenTimeMs &&
        other.averageDailyScreenTimeMs == averageDailyScreenTimeMs &&
        other.uploadedAt == uploadedAt;
  }

  @override
  int get hashCode =>
      Object.hash(totalScreenTimeMs, averageDailyScreenTimeMs, uploadedAt);
}

class _ChildPolicyAckSnapshot {
  const _ChildPolicyAckSnapshot({
    required this.appliedAt,
    required this.updatedAt,
    required this.applyStatus,
    required this.vpnRunning,
    required this.usageAccessGranted,
  });

  final DateTime? appliedAt;
  final DateTime? updatedAt;
  final String applyStatus;
  final bool vpnRunning;
  final bool? usageAccessGranted;

  DateTime get sortTime =>
      updatedAt ?? appliedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasFailureStatus {
    final normalized = applyStatus.trim().toLowerCase();
    return normalized == 'failed' ||
        normalized == 'error' ||
        normalized == 'mismatch';
  }

  static _ChildPolicyAckSnapshot? fromMap(Map<String, dynamic> data) {
    final applyStatus = (data['applyStatus'] as String?)?.trim();
    if (applyStatus == null || applyStatus.isEmpty) {
      return null;
    }
    return _ChildPolicyAckSnapshot(
      appliedAt: _ChildUsageSnapshot._toDateTime(data['appliedAt']),
      updatedAt: _ChildUsageSnapshot._toDateTime(data['updatedAt']),
      applyStatus: applyStatus,
      vpnRunning: data['vpnRunning'] == true,
      usageAccessGranted: data.containsKey('usageAccessGranted')
          ? data['usageAccessGranted'] == true
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _ChildPolicyAckSnapshot &&
        other.appliedAt == appliedAt &&
        other.updatedAt == updatedAt &&
        other.applyStatus == applyStatus &&
        other.vpnRunning == vpnRunning &&
        other.usageAccessGranted == usageAccessGranted;
  }

  @override
  int get hashCode => Object.hash(
        appliedAt,
        updatedAt,
        applyStatus,
        vpnRunning,
        usageAccessGranted,
      );
}

class _ChildDeviceHealth {
  const _ChildDeviceHealth({
    required this.online,
    required this.label,
    required this.color,
  });

  const _ChildDeviceHealth.protected()
      : online = true,
        label = 'Protected',
        color = const Color(0xFF22C55E);

  const _ChildDeviceHealth.atRiskNoAck()
      : online = true,
        label = 'At Risk',
        color = Colors.orange;

  const _ChildDeviceHealth.atRiskStaleAck()
      : online = true,
        label = 'At Risk',
        color = Colors.orange;

  const _ChildDeviceHealth.atRiskPermission()
      : online = true,
        label = 'At Risk',
        color = Colors.orange;

  const _ChildDeviceHealth.unprotected()
      : online = true,
        label = 'Unprotected',
        color = Colors.red;

  const _ChildDeviceHealth.pending()
      : online = false,
        label = 'Connecting\u2026',
        color = const Color(0xFF3B82F6);

  const _ChildDeviceHealth.offline()
      : online = false,
        label = null,
        color = Colors.grey;

  const _ChildDeviceHealth.warning()
      : online = false,
        label = 'Not seen recently',
        color = Colors.orange;

  const _ChildDeviceHealth.critical()
      : online = false,
        label = 'May be offline or removed',
        color = Colors.red;

  final bool online;
  final String? label;
  final Color color;
}
