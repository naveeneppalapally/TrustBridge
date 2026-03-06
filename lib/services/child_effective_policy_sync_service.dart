import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:trustbridge_app/core/utils/app_logger.dart';

import 'pairing_service.dart';
import 'vpn_service.dart';

class ChildEffectivePolicySyncService {
  ChildEffectivePolicySyncService._();

  static final ChildEffectivePolicySyncService instance =
      ChildEffectivePolicySyncService._();

  final PairingService _pairingService = PairingService();
  final VpnServiceBase _vpnService = VpnService();
  FirebaseFirestore? _firestore;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? _childId;
  String? _parentId;
  String? _listeningChildId;
  bool _starting = false;
  int? _lastForwardedVersion;
  String? _lastForwardedSignature;

  Future<void> start() async {
    if (_starting) {
      return;
    }
    _starting = true;
    try {
      await _ensureContext();
      final childId = _childId?.trim() ?? '';
      if (childId.isEmpty) {
        await stop();
        return;
      }
      final firestore = _resolvedFirestore;
      if (firestore == null) {
        return;
      }
      if (_subscription != null && _listeningChildId == childId) {
        return;
      }

      await _subscription?.cancel();
      _subscription = null;

      _subscription = firestore
          .collection('children')
          .doc(childId)
          .collection('effective_policy')
          .doc('current')
          .snapshots()
          .listen(
        (snapshot) {
          final data = snapshot.data();
          if (data == null || data.isEmpty) {
            return;
          }
          unawaited(
            _forwardPolicyToNative(
              data,
              source: 'effective_policy_listener',
            ),
          );
        },
        onError: (Object error) {
          AppLogger.debug('[ChildPolicySync] listener error: $error');
        },
      );
      AppLogger.debug(
        '[ChildPolicySync] started childId=$childId parentId=${_parentId ?? ''}',
      );
      _listeningChildId = childId;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _listeningChildId = null;
  }

  Future<bool> handlePolicyUpdatePush({
    Map<String, dynamic>? payload,
    String source = 'fcm',
  }) async {
    await _ensureContext(payload: payload);
    await start();

    final childId = _childId?.trim() ?? '';
    if (childId.isEmpty) {
      return false;
    }
    final firestore = _resolvedFirestore;
    if (firestore == null) {
      return false;
    }

    // Fetch trigger only. Native service remains the single policy-apply owner.
    try {
      if (_vpnService is VpnService) {
        await (_vpnService as VpnService).syncEffectivePolicyNow(
          parentId: _parentId,
          childId: _childId,
        );
      }
    } catch (_) {
      // Best-effort wake-up path.
    }

    final snapshot = await firestore
        .collection('children')
        .doc(childId)
        .collection('effective_policy')
        .doc('current')
        .get();
    final data = snapshot.data();
    if (data == null || data.isEmpty) {
      return false;
    }

    return _forwardPolicyToNative(
      data,
      source: source,
    );
  }

  Future<bool> _forwardPolicyToNative(
    Map<String, dynamic> rawPolicy, {
    required String source,
  }) async {
    final childId = _childId?.trim() ?? '';
    if (childId.isEmpty) {
      return false;
    }
    final parentId = _parentId?.trim();

    final payload = <String, dynamic>{...rawPolicy};
    payload['childId'] = childId;
    if (parentId != null && parentId.isNotEmpty) {
      payload['parentId'] = parentId;
    }
    final incomingVersion = _readPolicyVersion(payload['version']);
    final incomingSignature = incomingVersion != null && incomingVersion > 0
        ? 'v:$incomingVersion'
        : payload.toString();
    if (_lastForwardedSignature == incomingSignature) {
      AppLogger.debug(
        '[ChildPolicySync] skip duplicate payload source=$source '
        'childId=$childId signature=$incomingSignature',
      );
      return true;
    }
    if (incomingVersion != null &&
        incomingVersion > 0 &&
        _lastForwardedVersion != null &&
        incomingVersion <= _lastForwardedVersion!) {
      AppLogger.debug(
        '[ChildPolicySync] skip stale payload source=$source '
        'childId=$childId version=$incomingVersion '
        'last=$_lastForwardedVersion',
      );
      return true;
    }

    final applied = await _vpnService.applyPolicy(
      policyJson: payload,
      parentId: parentId,
      childId: childId,
    );
    if (applied) {
      _lastForwardedSignature = incomingSignature;
      if (incomingVersion != null && incomingVersion > 0) {
        _lastForwardedVersion = incomingVersion;
      }
    }
    AppLogger.debug(
      '[ChildPolicySync] forwarded to native source=$source '
      'childId=$childId applied=$applied',
    );
    return applied;
  }

  Future<void> _ensureContext({Map<String, dynamic>? payload}) async {
    final payloadChildId = (payload?['childId'] as String?)?.trim() ?? '';
    final payloadParentId = (payload?['parentId'] as String?)?.trim() ?? '';
    String? nextChildId = _childId;
    if (payloadChildId.isNotEmpty) {
      nextChildId = payloadChildId;
    } else if ((_childId?.isEmpty ?? true)) {
      nextChildId = (await _pairingService.getPairedChildId())?.trim();
    }
    final normalizedChildId = nextChildId?.trim();
    if (normalizedChildId != _childId) {
      _lastForwardedVersion = null;
      _lastForwardedSignature = null;
    }
    _childId = normalizedChildId;
    if (payloadParentId.isNotEmpty) {
      _parentId = payloadParentId;
    } else if ((_parentId?.isEmpty ?? true)) {
      _parentId = (await _pairingService.getPairedParentId())?.trim();
    }
  }

  FirebaseFirestore? get _resolvedFirestore {
    try {
      if (Firebase.apps.isEmpty) {
        return null;
      }
    } catch (_) {
      return null;
    }
    _firestore ??= FirebaseFirestore.instance;
    return _firestore;
  }

  int? _readPolicyVersion(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String) {
      return int.tryParse(rawValue);
    }
    return null;
  }
}
