import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/child_profile.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
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
  })  : _firestoreService = firestoreService ?? FirestoreService(),
        _vpnService = vpnService ?? VpnService(),
        _authService = authService,
        _parentIdResolver = parentIdResolver;

  final FirestoreService _firestoreService;
  final VpnServiceBase _vpnService;
  AuthService? _authService;
  final String? Function()? _parentIdResolver;

  StreamSubscription<List<ChildProfile>>? _childrenSubscription;
  SyncResult? _lastSyncResult;
  bool _isSyncing = false;
  String? _listeningParentId;

  SyncResult? get lastSyncResult => _lastSyncResult;
  bool get isSyncing => _isSyncing;

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
    _listeningParentId = parentId;

    _childrenSubscription =
        _firestoreService.getChildrenStream(parentId).listen(
      _onChildrenUpdated,
      onError: (Object error) {
        debugPrint('[PolicyVpnSync] Stream error: $error');
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
    _listeningParentId = null;
  }

  Future<void> _onChildrenUpdated(List<ChildProfile> children) async {
    debugPrint(
        '[PolicyVpnSync] Firestore policy update: ${children.length} children.');
    await _syncToVpn(children);
  }

  /// Manually trigger a policy sync (used for Sync Now + foreground resume).
  Future<SyncResult> syncNow() async {
    final parentId = _resolveParentId();
    if (parentId == null || parentId.isEmpty) {
      final result = SyncResult.error('Not logged in');
      _lastSyncResult = result;
      notifyListeners();
      return result;
    }

    try {
      final children = await _firestoreService.getChildrenOnce(parentId);
      return await _syncToVpn(children);
    } catch (error) {
      final result = SyncResult.error(error.toString());
      _lastSyncResult = result;
      notifyListeners();
      return result;
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
        final result = SyncResult.empty();
        _lastSyncResult = result;
        _isSyncing = false;
        notifyListeners();
        return result;
      }

      if (children.isEmpty) {
        final cleared = await _vpnService.updateFilterRules(
          blockedCategories: const <String>[],
          blockedDomains: const <String>[],
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
}
