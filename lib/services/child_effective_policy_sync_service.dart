import 'dart:async';
import 'package:trustbridge_app/core/utils/app_logger.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'pairing_service.dart';
import 'vpn_service.dart';

class ChildEffectivePolicySyncService {
  ChildEffectivePolicySyncService._();

  static final ChildEffectivePolicySyncService instance =
      ChildEffectivePolicySyncService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PairingService _pairingService = PairingService();
  final VpnServiceBase _vpnService = VpnService();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? _childId;
  String? _parentId;
  String? _deviceId;
  int? _lastAppliedVersion;
  bool _starting = false;
  List<String> _cachedCategories = const <String>[];
  List<String> _cachedDomains = const <String>[];
  List<String> _cachedAllowedDomains = const <String>[];

  Future<void> start() async {
    if (_subscription != null || _starting) {
      return;
    }
    _starting = true;
    try {
      final childId = (await _pairingService.getPairedChildId())?.trim() ?? '';
      final parentId =
          (await _pairingService.getPairedParentId())?.trim() ?? '';
      if (childId.isEmpty || parentId.isEmpty) {
        return;
      }

      _childId = childId;
      _parentId = parentId;

      _subscription = _firestore
          .collection('children')
          .doc(childId)
          .collection('effective_policy')
          .doc('current')
          .snapshots()
          .listen(
        (snapshot) {
          unawaited(_applySnapshot(snapshot));
        },
        onError: (Object error) {
          AppLogger.debug('[ChildPolicySync] listener error: $error');
        },
      );
      AppLogger.debug(
          '[ChildPolicySync] started childId=$childId parentId=$parentId');
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _deviceId = null;
    _lastAppliedVersion = null;
  }

  Future<bool> handlePolicyUpdatePush({
    Map<String, dynamic>? payload,
    String source = 'fcm',
  }) async {
    await _ensureContext(payload: payload);
    final childId = _childId?.trim() ?? '';
    if (childId.isEmpty) {
      return false;
    }

    try {
      if (_vpnService is VpnService) {
        await (_vpnService as VpnService).syncEffectivePolicyNow(
          parentId: _parentId,
          childId: _childId,
        );
      }
    } catch (_) {
      // Best-effort native wake-up path.
    }

    // Optimistic apply to reduce perceived latency while fresh policy fetch runs.
    if (_cachedCategories.isNotEmpty ||
        _cachedDomains.isNotEmpty ||
        _cachedAllowedDomains.isNotEmpty) {
      try {
        await _vpnService.updateFilterRules(
          blockedCategories: _cachedCategories,
          blockedDomains: _cachedDomains,
          temporaryAllowedDomains: _cachedAllowedDomains,
          parentId: _parentId,
          childId: _childId,
        );
      } catch (_) {
        // Best-effort optimistic path.
      }
    }

    final snapshot = await _firestore
        .collection('children')
        .doc(childId)
        .collection('effective_policy')
        .doc('current')
        .get();
    if (!snapshot.exists) {
      return false;
    }
    await _applySnapshot(snapshot);
    AppLogger.debug(
        '[ChildPolicySync] push handled source=$source childId=$childId');
    return true;
  }

  Future<void> _applySnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!snapshot.exists) {
      return;
    }
    final data = snapshot.data();
    if (data == null) {
      return;
    }

    final expectedParentId = _parentId;
    final snapshotParentId = (data['parentId'] as String?)?.trim() ?? '';
    if (expectedParentId != null &&
        expectedParentId.isNotEmpty &&
        snapshotParentId.isNotEmpty &&
        snapshotParentId != expectedParentId) {
      return;
    }

    final version = _toInt(data['version']);
    if (version != null &&
        _lastAppliedVersion != null &&
        version <= _lastAppliedVersion!) {
      return;
    }

    final categories = _toStringList(data['blockedCategories']);
    final services = _toStringList(data['blockedServices']);
    var domains = _toStringList(data['blockedDomainsResolved']);
    if (domains.isEmpty) {
      domains = _toStringList(data['blockedDomains']);
    }
    var allowedDomains = _toStringList(data['temporaryAllowedDomainsResolved']);
    if (allowedDomains.isEmpty) {
      allowedDomains = _toStringList(data['temporaryAllowedDomains']);
    }
    var packages = _toStringList(data['blockedPackagesResolved']);
    if (packages.isEmpty) {
      packages = _toStringList(data['blockedPackages']);
    }

    final currentChildId = _childId;
    final currentParentId = _parentId;
    final applyStopwatch = Stopwatch()..start();
    var vpnRunning = false;
    var updated = false;
    String? applyError;
    String applyStatus = 'failed';

    try {
      vpnRunning = await _vpnService.isVpnRunning();
      if (!vpnRunning) {
        final hasPermission = await _vpnService.hasVpnPermission();
        if (hasPermission) {
          await _vpnService.startVpn(
            blockedCategories: categories,
            blockedDomains: domains,
            parentId: currentParentId,
            childId: currentChildId,
          );
          vpnRunning = await _vpnService.isVpnRunning();
        }
      }

      updated = await _vpnService.updateFilterRules(
        blockedCategories: categories,
        blockedDomains: domains,
        temporaryAllowedDomains: allowedDomains,
        parentId: currentParentId,
        childId: currentChildId,
      );
      if (updated) {
        vpnRunning = await _vpnService.isVpnRunning();
        if (!vpnRunning) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          vpnRunning = await _vpnService.isVpnRunning();
        }
      }

      if (updated && !vpnRunning) {
        applyError = 'rules updated but VPN is not running';
      }
      applyStatus = updated && vpnRunning ? 'applied' : 'failed';
      if (!updated && applyError == null) {
        applyError = 'updateFilterRules returned false';
      }
      if (updated && vpnRunning && version != null) {
        _lastAppliedVersion = version;
      }
      if (updated) {
        _cachedCategories = List<String>.from(categories);
        _cachedDomains = List<String>.from(domains);
        _cachedAllowedDomains = List<String>.from(allowedDomains);
      }
      AppLogger.debug(
        '[ChildPolicySync] applied version=${version ?? -1} '
        'cats=${categories.length} domains=${domains.length} allowed=${allowedDomains.length} '
        'updated=$updated vpnRunning=$vpnRunning',
      );
    } catch (error) {
      applyStatus = 'error';
      applyError = '$error';
      AppLogger.debug('[ChildPolicySync] apply failed: $error');
    } finally {
      applyStopwatch.stop();
      await _writePolicyApplyAck(
        appliedVersion: version,
        applyStatus: applyStatus,
        vpnRunning: vpnRunning,
        blockedCategoriesCount: categories.length,
        blockedServicesCount: services.length,
        blockedDomainsCount: domains.length,
        blockedPackagesCount: packages.length,
        applyLatencyMs: applyStopwatch.elapsedMilliseconds,
        error: applyError,
      );
    }
  }

  Future<void> _writePolicyApplyAck({
    required int? appliedVersion,
    required String applyStatus,
    required bool vpnRunning,
    required int blockedCategoriesCount,
    required int blockedServicesCount,
    required int blockedDomainsCount,
    required int blockedPackagesCount,
    required int applyLatencyMs,
    required String? error,
  }) async {
    final childId = _childId?.trim();
    if (childId == null || childId.isEmpty) {
      return;
    }
    final deviceId = await _resolveDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      return;
    }

    final parentId = _parentId?.trim();
    final payload = <String, dynamic>{
      'parentId': parentId,
      'childId': childId,
      'deviceId': deviceId,
      'appliedVersion': appliedVersion ?? DateTime.now().millisecondsSinceEpoch,
      'appliedAt': FieldValue.serverTimestamp(),
      'vpnRunning': vpnRunning,
      'appliedBlockedDomainsCount': blockedDomainsCount,
      'appliedBlockedPackagesCount': blockedPackagesCount,
      'applyLatencyMs': applyLatencyMs < 0 ? 0 : applyLatencyMs,
      'ruleCounts': <String, dynamic>{
        'categoriesExpected': blockedCategoriesCount,
        'servicesExpected': blockedServicesCount,
        'domainsExpected': blockedDomainsCount,
        'packagesExpected': blockedPackagesCount,
      },
      'applyStatus': applyStatus,
      'error': error,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await _firestore
          .collection('children')
          .doc(childId)
          .collection('policy_apply_acks')
          .doc(deviceId)
          .set(payload, SetOptions(merge: true));
    } catch (error) {
      AppLogger.debug(
          '[ChildPolicySync] policy_apply_acks write failed: $error');
    }
  }

  Future<String?> _resolveDeviceId() async {
    final cached = _deviceId?.trim();
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    try {
      final next = (await _pairingService.getOrCreateDeviceId()).trim();
      if (next.isEmpty) {
        return null;
      }
      _deviceId = next;
      return next;
    } catch (_) {
      return null;
    }
  }

  int? _toInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  List<String> _toStringList(Object? raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((Object? value) => value?.toString().trim().toLowerCase() ?? '')
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> _ensureContext({Map<String, dynamic>? payload}) async {
    final payloadChildId = (payload?['childId'] as String?)?.trim() ?? '';
    final payloadParentId = (payload?['parentId'] as String?)?.trim() ?? '';
    if (payloadChildId.isNotEmpty) {
      _childId = payloadChildId;
    } else if ((_childId?.isEmpty ?? true)) {
      _childId = (await _pairingService.getPairedChildId())?.trim();
    }
    if (payloadParentId.isNotEmpty) {
      _parentId = payloadParentId;
    } else if ((_parentId?.isEmpty ?? true)) {
      _parentId = (await _pairingService.getPairedParentId())?.trim();
    }
  }
}
