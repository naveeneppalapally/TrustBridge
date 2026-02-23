import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'pairing_service.dart';
import 'vpn_service.dart';

/// Periodic child-device heartbeat service.
class HeartbeatService {
  static const String taskName = 'trustbridge_heartbeat';
  static const String _uniqueTaskName = 'trustbridge_heartbeat_unique';
  static const Duration _preferredFrequency = Duration(minutes: 10);
  static const Duration _fallbackFrequency = Duration(minutes: 15);

  static FirebaseFirestore? _firestoreOverride;
  static PairingService? _pairingServiceOverride;
  static VpnServiceBase? _vpnServiceOverride;
  static DateTime Function() _nowProvider = DateTime.now;

  static FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  static PairingService get _pairingService =>
      _pairingServiceOverride ?? PairingService();

  static VpnServiceBase get _vpnService => _vpnServiceOverride ?? VpnService();

  /// Test-only dependency override.
  @visibleForTesting
  static void configureForTesting({
    FirebaseFirestore? firestore,
    PairingService? pairingService,
    VpnServiceBase? vpnService,
    DateTime Function()? nowProvider,
  }) {
    _firestoreOverride = firestore;
    _pairingServiceOverride = pairingService;
    _vpnServiceOverride = vpnService;
    _nowProvider = nowProvider ?? DateTime.now;
  }

  /// Registers periodic heartbeat task.
  static Future<void> initialize() async {
    try {
      await Workmanager().registerPeriodicTask(
        _uniqueTaskName,
        taskName,
        frequency: _preferredFrequency,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } catch (_) {
      // Android periodic jobs often enforce a 15-minute minimum.
      try {
        await Workmanager().registerPeriodicTask(
          _uniqueTaskName,
          taskName,
          frequency: _fallbackFrequency,
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        );
      } catch (_) {
        // Registration is best effort.
      }
    }
  }

  /// Sends a single heartbeat to Firestore.
  static Future<void> sendHeartbeat() async {
    try {
      var parentId = await _pairingService.getPairedParentId();
      var childId = await _pairingService.getPairedChildId();
      if ((parentId == null || parentId.trim().isEmpty) ||
          (childId == null || childId.trim().isEmpty)) {
        final recovered = await _pairingService.recoverPairingFromCloud();
        parentId = recovered?.parentId;
        childId = recovered?.childId;
      }
      final normalizedParentId = parentId?.trim();
      final normalizedChildId = childId?.trim();
      if (normalizedParentId == null ||
          normalizedParentId.isEmpty ||
          normalizedChildId == null ||
          normalizedChildId.isEmpty) {
        return;
      }
      if (_pairingServiceOverride == null &&
          FirebaseAuth.instance.currentUser == null) {
        debugPrint(
          '[Heartbeat] Skipped: no signed-in Firebase session for child mode.',
        );
        return;
      }
      if (_pairingServiceOverride == null) {
        final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
        if (authUid != null &&
            authUid.isNotEmpty &&
            authUid != normalizedParentId) {
          debugPrint(
            '[Heartbeat] Parent mismatch detected. '
            'expectedParentId=$normalizedParentId currentUid=$authUid',
          );
        }
      }

      final deviceId = await _pairingService.getOrCreateDeviceId();

      DocumentSnapshot<Map<String, dynamic>> childSnapshot;
      try {
        childSnapshot =
            await _firestore.collection('children').doc(normalizedChildId).get();
      } catch (error) {
        debugPrint('[Heartbeat] child lookup failed: $error');
        return;
      }
      if (!childSnapshot.exists) {
        debugPrint(
          '[Heartbeat] Child profile missing; clearing local pairing and '
          'protection childId=$normalizedChildId deviceId=$deviceId',
        );
        await _clearStalePairingAndProtection();
        return;
      }
      final childData = childSnapshot.data() ?? const <String, dynamic>{};
      final childParentId = (childData['parentId'] as String?)?.trim();
      if (childParentId == null ||
          childParentId.isEmpty ||
          childParentId != normalizedParentId) {
        debugPrint(
          '[Heartbeat] Child profile ownership mismatch; clearing local '
          'pairing/protection childId=$normalizedChildId '
          'expectedParent=$normalizedParentId actualParent=$childParentId',
        );
        await _clearStalePairingAndProtection();
        return;
      }
      final rawDeviceIds = childData['deviceIds'];
      if (rawDeviceIds is List) {
        final registeredDeviceIds = rawDeviceIds
            .map((raw) => raw?.toString().trim() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        if (!registeredDeviceIds.contains(deviceId)) {
          debugPrint(
            '[Heartbeat] Device is no longer assigned to child profile; '
            'clearing local pairing/protection childId=$normalizedChildId '
            'deviceId=$deviceId',
          );
          await _clearStalePairingAndProtection();
          return;
        }
      }

      final status = await _vpnService.getStatus();
      const buildName = String.fromEnvironment(
        'FLUTTER_BUILD_NAME',
        defaultValue: 'dev',
      );
      final nowEpochMs = _nowProvider().millisecondsSinceEpoch;

      // Keep child linkage healthy even if pairing was interrupted earlier.
      await _firestore
          .collection('children')
          .doc(normalizedChildId)
          .collection('devices')
          .doc(deviceId)
          .set(
        <String, dynamic>{
          'parentId': normalizedParentId,
          // Keep this record compatible with Firestore rules for
          // children/{childId}/devices/{deviceId}. Heartbeat telemetry lives
          // in the root /devices collection.
          'pairedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      try {
        await _firestore.collection('children').doc(normalizedChildId).update(
          <String, dynamic>{
            'deviceIds': FieldValue.arrayUnion(<String>[deviceId]),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      } catch (error) {
        // Non-fatal for heartbeat; device-level docs still carry online status.
        debugPrint('[Heartbeat] child linkage refresh skipped: $error');
      }

      await _firestore.collection('devices').doc(deviceId).set(
        <String, dynamic>{
          'deviceId': deviceId,
          'parentId': normalizedParentId,
          'childId': normalizedChildId,
          'lastSeen': FieldValue.serverTimestamp(),
          'lastSeenEpochMs': nowEpochMs,
          'vpnActive': status.isRunning,
          'queriesProcessed': status.queriesProcessed,
          'queriesBlocked': status.queriesBlocked,
          'queriesAllowed': status.queriesAllowed,
          'upstreamFailureCount': status.upstreamFailureCount,
          'fallbackQueryCount': status.fallbackQueryCount,
          'blockedCategoryCount': status.blockedCategoryCount,
          'blockedDomainCount': status.blockedDomainCount,
          'vpnStatusUpdatedAt': FieldValue.serverTimestamp(),
          'appVersion': buildName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (error) {
      // Heartbeat failures are intentionally silent.
      debugPrint('[Heartbeat] send failed: $error');
    }
  }

  static Future<void> _clearStalePairingAndProtection() async {
    try {
      await _vpnService.updateFilterRules(
        blockedCategories: const <String>[],
        blockedDomains: const <String>[],
        temporaryAllowedDomains: const <String>[],
      );
    } catch (_) {
      // Best-effort cleanup.
    }
    try {
      await _vpnService.stopVpn();
    } catch (_) {
      // Best-effort cleanup.
    }
    try {
      await _pairingService.clearLocalPairing();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  /// Returns elapsed duration since last heartbeat, or null if never seen.
  static Future<Duration?> timeSinceLastSeen(String deviceId) async {
    if (deviceId.trim().isEmpty) {
      return null;
    }
    final snapshot = await _firestore.collection('devices').doc(deviceId).get();
    if (!snapshot.exists) {
      return null;
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final lastSeen = _readDateTime(data['lastSeen']) ??
        _readEpochDateTime(data['lastSeenEpochMs']);
    if (lastSeen == null) {
      return null;
    }
    return _nowProvider().difference(lastSeen);
  }

  /// True when no heartbeat for more than 30 minutes.
  static bool isOffline(DateTime? lastSeen) {
    if (lastSeen == null) {
      return false;
    }
    return _nowProvider().difference(lastSeen) > const Duration(minutes: 30);
  }

  /// True when no heartbeat for more than 24 hours.
  static bool isProbablyGone(DateTime? lastSeen) {
    if (lastSeen == null) {
      return false;
    }
    return _nowProvider().difference(lastSeen) > const Duration(hours: 24);
  }

  static DateTime? _readDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return null;
  }

  static DateTime? _readEpochDateTime(Object? raw) {
    if (raw is int && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is num && raw.toInt() > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    return null;
  }
}
