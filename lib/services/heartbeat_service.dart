import 'package:cloud_firestore/cloud_firestore.dart';
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
      final deviceId = await _pairingService.getOrCreateDeviceId();
      final status = await _vpnService.getStatus();
      const buildName = String.fromEnvironment(
        'FLUTTER_BUILD_NAME',
        defaultValue: 'dev',
      );

      await _firestore.collection('devices').doc(deviceId).set(
        <String, dynamic>{
          'lastSeen': FieldValue.serverTimestamp(),
          'lastSeenEpochMs': _nowProvider().millisecondsSinceEpoch,
          'vpnActive': status.isRunning,
          'appVersion': buildName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Heartbeat failures are intentionally silent.
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
