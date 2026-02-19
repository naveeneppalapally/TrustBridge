import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/access_request.dart';
import '../models/child_profile.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'performance_service.dart';
import 'vpn_service.dart';

/// Sync result for tracking outcomes and diagnostics.
class SyncResult {
  const SyncResult({
    required this.success,
    required this.childrenSynced,
    required this.totalDomains,
    required this.totalCategories,
    this.error,
    required this.timestamp,
  });

  final bool success;
  final int childrenSynced;
  final int totalDomains;
  final int totalCategories;
  final String? error;
  final DateTime timestamp;

  factory SyncResult.empty() => SyncResult(
        success: true,
        childrenSynced: 0,
        totalDomains: 0,
        totalCategories: 0,
        timestamp: DateTime.now(),
      );

  factory SyncResult.error(String message) => SyncResult(
        success: false,
        childrenSynced: 0,
        totalDomains: 0,
        totalCategories: 0,
        error: message,
        timestamp: DateTime.now(),
      );
}

class PolicyVpnSyncService extends ChangeNotifier {
  PolicyVpnSyncService({
    FirestoreService? firestoreService,
    VpnServiceBase? vpnService,
    AuthService? authService,
    String? Function()? parentIdResolver,
    Duration exceptionRefreshGrace = const Duration(seconds: 1),
  })  : _firestoreService = firestoreService ?? FirestoreService(),
        _vpnService = vpnService ?? VpnService(),
        _authService = authService,
        _parentIdResolver = parentIdResolver,
        _exceptionRefreshGrace = exceptionRefreshGrace;

  final FirestoreService _firestoreService;
  final VpnServiceBase _vpnService;
  final PerformanceService _performanceService = PerformanceService();
  AuthService? _authService;
  final String? Function()? _parentIdResolver;
  final Duration _exceptionRefreshGrace;

  StreamSubscription<List<ChildProfile>>? _childrenSubscription;
  StreamSubscription<List<AccessRequest>>? _accessRequestsSubscription;
  Timer? _exceptionRefreshTimer;
  bool _didReceiveInitialAccessRequestsSnapshot = false;
  SyncResult? _lastSyncResult;
  bool _isSyncing = false;
  String? _listeningParentId;
  DateTime? _nextExceptionRefreshAt;

  SyncResult? get lastSyncResult => _lastSyncResult;
  bool get isSyncing => _isSyncing;
  DateTime? get nextExceptionRefreshAt => _nextExceptionRefreshAt;

  String? _resolveParentId() {
    final overridden = _parentIdResolver?.call()?.trim();
    if (overridden != null && overridden.isNotEmpty) {
      return overridden;
    }
    _authService ??= AuthService();
    return _authService?.currentUser?.uid;
  }

  /// Start listening to policy changes and auto-sync to active VPN.
  void startListening() {
    final parentId = _resolveParentId();
    if (parentId == null || parentId.isEmpty) {
      debugPrint('[PolicyVpnSync] No user logged in; listener not started.');
      return;
    }

    if (_childrenSubscription != null && _listeningParentId == parentId) {
      return;
    }

    debugPrint('[PolicyVpnSync] Starting listener for parentId=$parentId');
    _childrenSubscription?.cancel();
    _accessRequestsSubscription?.cancel();
    _listeningParentId = parentId;
    _didReceiveInitialAccessRequestsSnapshot = false;

    _childrenSubscription =
        _firestoreService.getChildrenStream(parentId).listen(
      _onChildrenUpdated,
      onError: (Object error) {
        debugPrint('[PolicyVpnSync] Stream error: $error');
        _lastSyncResult = SyncResult.error(error.toString());
        notifyListeners();
      },
    );

    _accessRequestsSubscription =
        _firestoreService.getAllRequestsStream(parentId).listen(
      _onAccessRequestsUpdated,
      onError: (Object error) {
        debugPrint('[PolicyVpnSync] Access request stream error: $error');
        _lastSyncResult = SyncResult.error(error.toString());
        notifyListeners();
      },
    );
  }

  /// Stop listening to policy changes (call on logout).
  void stopListening() {
    debugPrint('[PolicyVpnSync] Stopping listener');
    _childrenSubscription?.cancel();
    _childrenSubscription = null;
    _accessRequestsSubscription?.cancel();
    _accessRequestsSubscription = null;
    _didReceiveInitialAccessRequestsSnapshot = false;
    _listeningParentId = null;
    _clearExceptionRefreshSchedule();
  }

  Future<void> _onChildrenUpdated(List<ChildProfile> children) async {
    debugPrint(
        '[PolicyVpnSync] Firestore policy update: ${children.length} children.');
    await _syncToVpn(children);
  }

  Future<void> _onAccessRequestsUpdated(List<AccessRequest> requests) async {
    if (!_didReceiveInitialAccessRequestsSnapshot) {
      _didReceiveInitialAccessRequestsSnapshot = true;
      return;
    }

    debugPrint(
      '[PolicyVpnSync] Access request update: ${requests.length} requests.',
    );
    await syncNow();
  }

  /// Manually trigger a policy sync (used for Sync Now + foreground resume).
  Future<SyncResult> syncNow() async {
    final trace = await _performanceService.startTrace('policy_sync');
    final stopwatch = Stopwatch()..start();
    final parentId = _resolveParentId();
    if (parentId == null || parentId.isEmpty) {
      final result = SyncResult.error('Not logged in');
      _lastSyncResult = result;
      notifyListeners();
      await _recordSyncTraceMetrics(trace, result);
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.annotateThreshold(
        trace: trace,
        name: 'policy_sync_ms',
        actualValue: stopwatch.elapsedMilliseconds,
        warningValue: PerformanceThresholds.policySyncWarningMs,
      );
      await _performanceService.stopTrace(trace);
      return result;
    }

    try {
      final children = await _firestoreService.getChildrenOnce(parentId);
      final result = await _syncToVpn(children);
      await _recordSyncTraceMetrics(trace, result);
      return result;
    } catch (error) {
      final result = SyncResult.error(error.toString());
      _lastSyncResult = result;
      notifyListeners();
      await _recordSyncTraceMetrics(trace, result);
      return result;
    } finally {
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.annotateThreshold(
        trace: trace,
        name: 'policy_sync_ms',
        actualValue: stopwatch.elapsedMilliseconds,
        warningValue: PerformanceThresholds.policySyncWarningMs,
      );
      await _performanceService.stopTrace(trace);
    }
  }

  Future<void> _recordSyncTraceMetrics(
    PerformanceTrace trace,
    SyncResult result,
  ) async {
    await _performanceService.setMetric(
      trace,
      'children_synced',
      result.childrenSynced,
    );
    await _performanceService.setMetric(
      trace,
      'categories_synced',
      result.totalCategories,
    );
    await _performanceService.setMetric(
      trace,
      'domains_synced',
      result.totalDomains,
    );
    await _performanceService.setMetric(
      trace,
      'sync_success',
      result.success ? 1 : 0,
    );
    if (result.error != null && result.error!.isNotEmpty) {
      await _performanceService.setAttribute(trace, 'sync_error', 'yes');
    }
  }

  /// Merge all child policies and push to VPN engine.
  Future<SyncResult> _syncToVpn(List<ChildProfile> children) async {
    if (_isSyncing) {
      return _lastSyncResult ?? SyncResult.empty();
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final vpnRunning = await _vpnService.isVpnRunning();
      if (!vpnRunning) {
        _clearExceptionRefreshSchedule();
        final result = SyncResult.empty();
        _lastSyncResult = result;
        _isSyncing = false;
        notifyListeners();
        return result;
      }

      final parentId = _resolveParentId();
      final temporaryAllowedDomains = parentId == null || parentId.isEmpty
          ? const <String>[]
          : await _firestoreService.getActiveApprovedExceptionDomains(
              parentId: parentId,
            );
      final nextExceptionExpiry = parentId == null || parentId.isEmpty
          ? null
          : await _firestoreService.getNextApprovedExceptionExpiry(
              parentId: parentId,
            );
      _scheduleExceptionRefresh(nextExceptionExpiry);

      if (children.isEmpty) {
        final cleared = await _vpnService.updateFilterRules(
          blockedCategories: const <String>[],
          blockedDomains: const <String>[],
          temporaryAllowedDomains: temporaryAllowedDomains,
        );
        final result = SyncResult(
          success: cleared,
          childrenSynced: 0,
          totalDomains: 0,
          totalCategories: 0,
          error: cleared ? null : 'Failed to clear VPN rules',
          timestamp: DateTime.now(),
        );
        _lastSyncResult = result;
        _isSyncing = false;
        notifyListeners();
        return result;
      }

      final mergedCategories = <String>{};
      final mergedDomains = <String>{};

      for (final child in children) {
        mergedCategories.addAll(child.policy.blockedCategories);
        mergedDomains.addAll(child.policy.blockedDomains);
      }

      final categories = mergedCategories.toList()..sort();
      final domains = mergedDomains.toList()..sort();

      final updated = await _vpnService.updateFilterRules(
        blockedCategories: categories,
        blockedDomains: domains,
        temporaryAllowedDomains: temporaryAllowedDomains,
      );

      final result = SyncResult(
        success: updated,
        childrenSynced: children.length,
        totalDomains: domains.length,
        totalCategories: categories.length,
        error: updated ? null : 'VPN updateFilterRules returned false',
        timestamp: DateTime.now(),
      );
      _lastSyncResult = result;
      _isSyncing = false;
      notifyListeners();
      return result;
    } catch (error) {
      final result = SyncResult.error(error.toString());
      _lastSyncResult = result;
      _isSyncing = false;
      notifyListeners();
      return result;
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }

  void _clearExceptionRefreshSchedule() {
    _exceptionRefreshTimer?.cancel();
    _exceptionRefreshTimer = null;
    _nextExceptionRefreshAt = null;
  }

  void _scheduleExceptionRefresh(DateTime? nextExpiry) {
    _clearExceptionRefreshSchedule();

    if (nextExpiry == null) {
      return;
    }

    final now = DateTime.now();
    if (!nextExpiry.isAfter(now)) {
      return;
    }

    final delay = nextExpiry.difference(now) + _exceptionRefreshGrace;
    _nextExceptionRefreshAt = now.add(delay);
    _exceptionRefreshTimer = Timer(delay, () {
      _clearExceptionRefreshSchedule();
      if (_listeningParentId == null) {
        return;
      }
      unawaited(syncNow());
    });
  }
}
