import 'dart:async';
import 'dart:collection';
import 'package:trustbridge_app/core/utils/app_logger.dart';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/access_request.dart';
import '../models/blocklist_source.dart';
import '../models/child_profile.dart';
import '../config/service_definitions.dart';
import 'auth_service.dart';
import 'blocklist_sync_service.dart';
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
    BlocklistSyncService? blocklistSyncService,
    AuthService? authService,
    String? Function()? parentIdResolver,
    String? blocklistDatabasePathOverride,
    Duration exceptionRefreshGrace = const Duration(seconds: 1),
  })  : _firestoreService = firestoreService ?? FirestoreService(),
        _vpnService = vpnService ?? VpnService(),
        _blocklistSyncService = blocklistSyncService,
        _authService = authService,
        _parentIdResolver = parentIdResolver,
        _blocklistDatabasePathOverride = blocklistDatabasePathOverride,
        _exceptionRefreshGrace = exceptionRefreshGrace;

  final FirestoreService _firestoreService;
  final VpnServiceBase _vpnService;
  BlocklistSyncService? _blocklistSyncService;
  final PerformanceService _performanceService = PerformanceService();
  AuthService? _authService;
  final String? Function()? _parentIdResolver;
  final String? _blocklistDatabasePathOverride;
  final Duration _exceptionRefreshGrace;

  StreamSubscription<List<ChildProfile>>? _childrenSubscription;
  StreamSubscription<List<AccessRequest>>? _accessRequestsSubscription;
  Timer? _exceptionRefreshTimer;
  bool _didReceiveInitialAccessRequestsSnapshot = false;
  SyncResult? _lastSyncResult;
  bool _isSyncing = false;
  String? _listeningParentId;
  String? _lastAppliedRuleSignature;
  DateTime? _nextExceptionRefreshAt;
  final Queue<List<ChildProfile>> _pendingSyncChildren =
      Queue<List<ChildProfile>>();

  SyncResult? get lastSyncResult => _lastSyncResult;
  bool get isSyncing => _isSyncing;
  DateTime? get nextExceptionRefreshAt => _nextExceptionRefreshAt;

  BlocklistSyncService get _resolvedBlocklistSyncService {
    _blocklistSyncService ??= BlocklistSyncService();
    return _blocklistSyncService!;
  }

  /// Handles category-enable side effects for local blocklist enforcement.
  Future<void> onCategoryEnabled(BlocklistCategory category) async {
    await _resolvedBlocklistSyncService.syncAll(
      <BlocklistCategory>[category],
      forceRefresh: false,
    );
    await _refreshVpnRulesFromLatestPolicies();
  }

  /// Handles category-disable side effects for local blocklist enforcement.
  Future<void> onCategoryDisabled(BlocklistCategory category) async {
    await _resolvedBlocklistSyncService.onCategoryDisabled(category);
    await _refreshVpnRulesFromLatestPolicies();
  }

  /// Adds a custom blocked domain to local blocklist storage.
  Future<void> addCustomBlockedDomain(String domain) async {
    final normalized = _normalizeCustomDomain(domain);
    if (!_isValidCustomDomain(normalized)) {
      throw ArgumentError.value(
        domain,
        'domain',
        'Domain must be a valid host (e.g., reddit.com).',
      );
    }

    final db = await _openBlocklistDatabase();
    try {
      await db.insert(
        'blocked_domains',
        <String, Object>{
          'domain': normalized,
          'category': 'custom',
          'source_id': 'custom',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } finally {
      await db.close();
    }
    await _refreshVpnRulesFromLatestPolicies();
  }

  /// Removes a custom blocked domain from local blocklist storage.
  Future<void> removeCustomBlockedDomain(String domain) async {
    final normalized = _normalizeCustomDomain(domain);
    if (normalized.isEmpty) {
      return;
    }

    final db = await _openBlocklistDatabase();
    try {
      await db.delete(
        'blocked_domains',
        where: 'domain = ? AND source_id = ?',
        whereArgs: <Object>[normalized, 'custom'],
      );
    } finally {
      await db.close();
    }
    await _refreshVpnRulesFromLatestPolicies();
  }

  String? _resolveParentId() {
    final overridden = _parentIdResolver?.call()?.trim();
    if (overridden != null && overridden.isNotEmpty) {
      return overridden;
    }
    _authService ??= AuthService();
    return _authService?.currentUser?.uid;
  }

  Future<void> _refreshVpnRulesFromLatestPolicies() async {
    final parentId = _resolveParentId();
    if (parentId == null || parentId.isEmpty) {
      return;
    }

    final children = await _firestoreService.getChildrenOnce(parentId);
    await _syncToVpn(children);
  }

  /// Start listening to policy changes and auto-sync to active VPN.
  void startListening() {
    final parentId = _resolveParentId();
    if (parentId == null || parentId.isEmpty) {
      AppLogger.debug('[PolicyVpnSync] No user logged in; listener not started.');
      return;
    }

    if (_childrenSubscription != null && _listeningParentId == parentId) {
      return;
    }

    AppLogger.debug('[PolicyVpnSync] Starting listener for parentId=$parentId');
    _childrenSubscription?.cancel();
    _accessRequestsSubscription?.cancel();
    _listeningParentId = parentId;
    _didReceiveInitialAccessRequestsSnapshot = false;

    _childrenSubscription =
        _firestoreService.getChildrenStream(parentId).listen(
      _onChildrenUpdated,
      onError: (Object error) {
        AppLogger.debug('[PolicyVpnSync] Stream error: $error');
        _lastSyncResult = SyncResult.error(error.toString());
        notifyListeners();
      },
    );

    _accessRequestsSubscription =
        _firestoreService.getAllRequestsStream(parentId).listen(
      _onAccessRequestsUpdated,
      onError: (Object error) {
        AppLogger.debug('[PolicyVpnSync] Access request stream error: $error');
        _lastSyncResult = SyncResult.error(error.toString());
        notifyListeners();
      },
    );
  }

  /// Stop listening to policy changes (call on logout).
  void stopListening() {
    AppLogger.debug('[PolicyVpnSync] Stopping listener');
    _childrenSubscription?.cancel();
    _childrenSubscription = null;
    _accessRequestsSubscription?.cancel();
    _accessRequestsSubscription = null;
    _didReceiveInitialAccessRequestsSnapshot = false;
    _listeningParentId = null;
    _lastAppliedRuleSignature = null;
    _clearExceptionRefreshSchedule();
    _pendingSyncChildren.clear();
  }

  Future<void> _onChildrenUpdated(List<ChildProfile> children) async {
    AppLogger.debug(
        '[PolicyVpnSync] Firestore policy update: ${children.length} children.');
    await _syncToVpn(children);
  }

  Future<void> _onAccessRequestsUpdated(List<AccessRequest> requests) async {
    if (!_didReceiveInitialAccessRequestsSnapshot) {
      _didReceiveInitialAccessRequestsSnapshot = true;
      return;
    }

    AppLogger.debug(
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
      _enqueuePendingSync(children);
      return _lastSyncResult ?? SyncResult.empty();
    }

    _isSyncing = true;
    notifyListeners();

    SyncResult result;
    try {
      final vpnRunning = await _vpnService.isVpnRunning();
      if (!vpnRunning) {
        _clearExceptionRefreshSchedule();
        // Even when VPN is not running, still persist the merged rules so
        // they are immediately applied when the VPN starts later.
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
        final ruleSignature = _ruleSignature(
          blockedCategories: const <String>[],
          blockedDomains: const <String>[],
          temporaryAllowedDomains: temporaryAllowedDomains,
        );
        if (_lastAppliedRuleSignature == ruleSignature) {
          result = SyncResult(
            success: true,
            childrenSynced: 0,
            totalDomains: 0,
            totalCategories: 0,
            timestamp: DateTime.now(),
          );
          _lastSyncResult = result;
          _isSyncing = false;
          notifyListeners();
          if (_pendingSyncChildren.isNotEmpty) {
            final nextChildren = _pendingSyncChildren.removeFirst();
            unawaited(_syncToVpn(nextChildren));
          }
          return result;
        }
        final cleared = await _replaceVpnRules(
          blockedCategories: const <String>[],
          blockedDomains: const <String>[],
          temporaryAllowedDomains: temporaryAllowedDomains,
        );
        if (cleared) {
          _lastAppliedRuleSignature = ruleSignature;
        }
        result = SyncResult(
          success: cleared,
          childrenSynced: 0,
          totalDomains: 0,
          totalCategories: 0,
          error: cleared ? null : 'Failed to clear VPN rules',
          timestamp: DateTime.now(),
        );
      } else {
        final mergedCategories = <String>{};
        final mergedDomains = <String>{};

        for (final child in children) {
          mergedCategories.addAll(child.policy.blockedCategories);
          mergedDomains.addAll(
            ServiceDefinitions.resolveDomains(
              blockedCategories: child.policy.blockedCategories,
              blockedServices: child.policy.blockedServices,
              customBlockedDomains: child.policy.blockedDomains,
            ),
          );
        }

        final categories = mergedCategories.toList()..sort();
        final domains = mergedDomains.toList()..sort();
        final ruleSignature = _ruleSignature(
          blockedCategories: categories,
          blockedDomains: domains,
          temporaryAllowedDomains: temporaryAllowedDomains,
        );
        if (_lastAppliedRuleSignature == ruleSignature) {
          result = SyncResult(
            success: true,
            childrenSynced: children.length,
            totalDomains: domains.length,
            totalCategories: categories.length,
            timestamp: DateTime.now(),
          );
          _lastSyncResult = result;
          _isSyncing = false;
          notifyListeners();
          if (_pendingSyncChildren.isNotEmpty) {
            final nextChildren = _pendingSyncChildren.removeFirst();
            unawaited(_syncToVpn(nextChildren));
          }
          return result;
        }

        final updated = await _replaceVpnRules(
          blockedCategories: categories,
          blockedDomains: domains,
          temporaryAllowedDomains: temporaryAllowedDomains,
        );
        if (updated) {
          _lastAppliedRuleSignature = ruleSignature;
        }

        result = SyncResult(
          success: updated,
          childrenSynced: children.length,
          totalDomains: domains.length,
          totalCategories: categories.length,
          error: updated ? null : 'VPN updateFilterRules returned false',
          timestamp: DateTime.now(),
        );
      }
    } catch (error) {
      result = SyncResult.error(error.toString());
    }

    _lastSyncResult = result;
    _isSyncing = false;
    notifyListeners();
    if (_pendingSyncChildren.isNotEmpty) {
      final nextChildren = _pendingSyncChildren.removeFirst();
      unawaited(_syncToVpn(nextChildren));
    }
    return result;
  }

  Future<bool> _replaceVpnRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    required List<String> temporaryAllowedDomains,
  }) async {
    return _vpnService.updateFilterRules(
      blockedCategories: blockedCategories,
      blockedDomains: blockedDomains,
      temporaryAllowedDomains: temporaryAllowedDomains,
    );
  }

  String _ruleSignature({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    required List<String> temporaryAllowedDomains,
  }) {
    final categories = blockedCategories
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final domains = blockedDomains
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final allowed = temporaryAllowedDomains
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return <String>[
      categories.join(','),
      domains.join(','),
      allowed.join(','),
    ].join('||');
  }

  void _enqueuePendingSync(List<ChildProfile> children) {
    final signature = _syncSignature(children);
    if (_pendingSyncChildren.isNotEmpty) {
      final lastSignature = _syncSignature(_pendingSyncChildren.last);
      if (lastSignature == signature) {
        return;
      }
    }
    _pendingSyncChildren.addLast(List<ChildProfile>.from(children));
  }

  String _syncSignature(List<ChildProfile> children) {
    final childSignatures = children.map((child) {
      final categories = child.policy.blockedCategories.toList()..sort();
      final services = child.policy.blockedServices.toList()..sort();
      final domains = ServiceDefinitions.resolveDomains(
        blockedCategories: categories,
        blockedServices: services,
        customBlockedDomains: child.policy.blockedDomains,
      ).toList()
        ..sort();
      return '${child.id}:${categories.join(',')}:${services.join(',')}:${domains.join(',')}';
    }).toList()
      ..sort();
    return childSignatures.join('||');
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

  String _normalizeCustomDomain(String domain) {
    var normalized = domain.trim().toLowerCase();
    if (normalized.startsWith('http://')) {
      normalized = normalized.substring('http://'.length);
    } else if (normalized.startsWith('https://')) {
      normalized = normalized.substring('https://'.length);
    }
    if (normalized.startsWith('www.')) {
      normalized = normalized.substring(4);
    }
    final slashIndex = normalized.indexOf('/');
    if (slashIndex >= 0) {
      normalized = normalized.substring(0, slashIndex);
    }
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _isValidCustomDomain(String value) {
    if (value.isEmpty || value.contains(' ')) {
      return false;
    }
    final pattern = RegExp(r'^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$');
    if (!pattern.hasMatch(value)) {
      return false;
    }
    return !value.contains('..');
  }

  Future<Database> _openBlocklistDatabase() async {
    final path = _blocklistDatabasePathOverride ?? await _resolveDbPath();
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE blocked_domains (
  domain TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  source_id TEXT NOT NULL
)
''');
        await db.execute('''
CREATE TABLE blocklist_meta (
  source_id TEXT PRIMARY KEY,
  last_synced INTEGER NOT NULL,
  domain_count INTEGER NOT NULL DEFAULT 0
)
''');
      },
    );
  }

  Future<String> _resolveDbPath() async {
    final databasesPath = await getDatabasesPath();
    return p.join(databasesPath, 'trustbridge_blocklist.db');
  }
}
