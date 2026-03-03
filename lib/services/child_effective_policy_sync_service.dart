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
  bool _starting = false;

  Future<void> start() async {
    if (_subscription != null || _starting) {
      return;
    }
    _starting = true;
    try {
      await _ensureContext();
      final childId = _childId?.trim() ?? '';
      if (childId.isEmpty) {
        return;
      }
      final firestore = _resolvedFirestore;
      if (firestore == null) {
        return;
      }

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
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
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

    final applied = await _vpnService.applyPolicy(
      policyJson: payload,
      parentId: parentId,
      childId: childId,
    );
    AppLogger.debug(
      '[ChildPolicySync] forwarded to native source=$source '
      'childId=$childId applied=$applied',
    );
    return applied;
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
}
