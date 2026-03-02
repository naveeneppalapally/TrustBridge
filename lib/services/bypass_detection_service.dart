import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/bypass_alert_dedup_service.dart';
import '../services/device_admin_service.dart';
import '../services/pairing_service.dart';
import '../services/vpn_service.dart';

/// Detects bypass signals on child devices and logs alerts for parents.
class BypassDetectionService {
  BypassDetectionService({
    FirebaseFirestore? firestore,
    PairingService? pairingService,
    VpnServiceBase? vpnService,
    DeviceAdminService? deviceAdminService,
    BypassAlertDedupService? dedupService,
    DateTime Function()? nowProvider,
    Future<void> Function(Map<String, dynamic> payload)? eventWriter,
    Future<void> Function(Map<String, dynamic> payload)? notificationWriter,
  })  : _firestoreOverride = firestore,
        _pairingServiceOverride = pairingService,
        _vpnServiceOverride = vpnService,
        _deviceAdminServiceOverride = deviceAdminService,
        _dedupServiceOverride = dedupService,
        _nowProvider = nowProvider ?? DateTime.now,
        _eventWriterOverride = eventWriter,
        _notificationWriterOverride = notificationWriter;

  static const String _localQueueKey = 'bypass_event_local_queue';

  final FirebaseFirestore? _firestoreOverride;
  final PairingService? _pairingServiceOverride;
  final VpnServiceBase? _vpnServiceOverride;
  final DeviceAdminService? _deviceAdminServiceOverride;
  final BypassAlertDedupService? _dedupServiceOverride;
  final DateTime Function() _nowProvider;
  final Future<void> Function(Map<String, dynamic> payload)?
      _eventWriterOverride;
  final Future<void> Function(Map<String, dynamic> payload)?
      _notificationWriterOverride;

  Timer? _vpnMonitorTimer;
  Timer? _privateDnsTimer;
  bool? _lastVpnRunning;
  DateTime? _vpnOffSince;
  int _vpnOffConsecutiveChecks = 0;
  bool _vpnDisabledAlertSentForCurrentOutage = false;
  String? _lastPrivateDnsMode;

  final List<Map<String, dynamic>> _queuedEvents = <Map<String, dynamic>>[];

  static const Duration _vpnDisabledAlertGrace = Duration(seconds: 70);
  static const int _vpnDisabledMinConsecutiveChecks = 3;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  PairingService get _pairingService =>
      _pairingServiceOverride ?? PairingService();

  VpnServiceBase get _vpnService => _vpnServiceOverride ?? VpnService();

  DeviceAdminService get _deviceAdminService =>
      _deviceAdminServiceOverride ?? DeviceAdminService();

  BypassAlertDedupService get _dedupService =>
      _dedupServiceOverride ??
      BypassAlertDedupService(firestore: _firestoreOverride);

  @visibleForTesting
  int get queuedEventCount => _queuedEvents.length;

  /// Starts lightweight bypass monitoring loops.
  Future<void> startMonitoring() async {
    await _hydrateLocalQueue();
    await flushQueuedEvents();

    _vpnMonitorTimer?.cancel();
    _vpnMonitorTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkVpnState(),
    );

    await _checkVpnState();
  }

  /// Stops active monitoring timers.
  void stopMonitoring() {
    _vpnMonitorTimer?.cancel();
    _privateDnsTimer?.cancel();
    _vpnMonitorTimer = null;
    _privateDnsTimer = null;
  }

  /// Logs a bypass event to Firestore.
  ///
  /// Falls back to local queue when network/write fails.
  Future<void> logBypassEvent(String type) async {
    final deviceId = await _pairingService.getOrCreateDeviceId();
    final childId = await _pairingService.getPairedChildId();
    final parentId = await _pairingService.getPairedParentId();
    if (childId == null || childId.isEmpty) {
      return;
    }

    final payload = <String, dynamic>{
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'timestampEpochMs': _nowProvider().millisecondsSinceEpoch,
      'deviceId': deviceId,
      'childId': childId,
      'parentId': parentId,
      'read': false,
    };

    try {
      if (_eventWriterOverride != null) {
        await _eventWriterOverride!(payload);
      } else {
        await _firestore
            .collection('bypass_events')
            .doc(deviceId)
            .collection('events')
            .add(payload);
      }
    } catch (_) {
      await _enqueueLocal(payload);
    }
  }

  /// Creates a parent notification queue item for a bypass event.
  Future<void> alertParent(String type) async {
    final parentId = await _pairingService.getPairedParentId();
    final deviceId = await _pairingService.getOrCreateDeviceId();
    final childId = await _pairingService.getPairedChildId();
    if (parentId == null || parentId.isEmpty) {
      return;
    }

    final decision = await _dedupService.getAlertDecision(deviceId, type);
    if (!decision.shouldSend) {
      return;
    }

    final title = decision.isEscalated && decision.escalationMessage != null
        ? decision.escalationMessage!
        : _titleForType(type);

    final payload = <String, dynamic>{
      'parentId': parentId,
      if (childId != null && childId.trim().isNotEmpty) 'childId': childId.trim(),
      'deviceId': deviceId,
      'title': title,
      'body': title,
      'route': '/parent/bypass-alerts',
      'eventType': type,
      'processed': false,
      'sentAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_notificationWriterOverride != null) {
        await _notificationWriterOverride!(payload);
      } else {
        await _firestore.collection('notification_queue').add(payload);
      }
      await _dedupService.recordAlert(deviceId, type);
    } catch (_) {
      // Notification is best effort; bypass log is the source of truth.
    }
  }

  /// Periodically checks Android Private DNS mode for unexpected changes.
  Future<void> startPrivateDnsMonitoring() async {
    _lastPrivateDnsMode = await _deviceAdminService.getPrivateDnsMode();
    _privateDnsTimer?.cancel();
    _privateDnsTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => runPrivateDnsCheckOnce(),
    );
  }

  /// Single private DNS check iteration (public for tests).
  Future<void> runPrivateDnsCheckOnce() async {
    final current = await _deviceAdminService.getPrivateDnsMode();
    if (_lastPrivateDnsMode != null &&
        current != null &&
        _lastPrivateDnsMode != current) {
      await logBypassEvent('private_dns_changed');
      await alertParent('private_dns_changed');
    }
    _lastPrivateDnsMode = current;
  }

  /// Flushes locally queued events to Firestore.
  Future<void> flushQueuedEvents() async {
    if (_queuedEvents.isEmpty) {
      return;
    }

    final remaining = <Map<String, dynamic>>[];
    for (final payload in _queuedEvents) {
      try {
        if (_eventWriterOverride != null) {
          await _eventWriterOverride!(payload);
        } else {
          final deviceId = payload['deviceId'] as String?;
          if (deviceId == null || deviceId.trim().isEmpty) {
            continue;
          }
          await _firestore
              .collection('bypass_events')
              .doc(deviceId)
              .collection('events')
              .add(payload);
        }
      } catch (_) {
        remaining.add(payload);
      }
    }

    _queuedEvents
      ..clear()
      ..addAll(remaining);
    await _persistLocalQueue();
  }

  Future<void> _checkVpnState() async {
    try {
      final status = await _vpnService.getStatus();
      final isRunning = status.isRunning;
      if (isRunning) {
        _lastVpnRunning = true;
        _vpnOffSince = null;
        _vpnOffConsecutiveChecks = 0;
        _vpnDisabledAlertSentForCurrentOutage = false;
        return;
      }

      // Initial unknown state should not create an alert.
      if (_lastVpnRunning == null) {
        _lastVpnRunning = false;
        _vpnOffSince = _nowProvider();
        _vpnOffConsecutiveChecks = 1;
        return;
      }

      _lastVpnRunning = false;
      _vpnOffConsecutiveChecks += 1;
      _vpnOffSince ??= _nowProvider();

      if (_vpnDisabledAlertSentForCurrentOutage) {
        return;
      }

      final offDuration = _nowProvider().difference(_vpnOffSince!);
      if (_vpnOffConsecutiveChecks < _vpnDisabledMinConsecutiveChecks ||
          offDuration < _vpnDisabledAlertGrace) {
        return;
      }

      // Confirm once more to avoid false alerts from transient status reads.
      await Future<void>.delayed(const Duration(seconds: 2));
      final confirmStatus = await _vpnService.getStatus();
      if (confirmStatus.isRunning) {
        _lastVpnRunning = true;
        _vpnOffSince = null;
        _vpnOffConsecutiveChecks = 0;
        _vpnDisabledAlertSentForCurrentOutage = false;
        return;
      }

      await logBypassEvent('vpn_disabled');
      await alertParent('vpn_disabled');
      _vpnDisabledAlertSentForCurrentOutage = true;
    } catch (_) {
      // Silent monitoring failure.
    }
  }

  String _titleForType(String type) {
    switch (type) {
      case 'vpn_disabled':
        return '⚠️ Protection was turned off on your child\'s phone';
      case 'uninstall_attempt':
        return '🚨 Someone tried to remove TrustBridge from your child\'s phone';
      case 'private_dns_changed':
        return '⚠️ DNS settings changed on your child\'s phone';
      case 'device_offline_24h':
        return '🔴 Child device has been offline for 24+ hours';
      default:
        return '⚠️ Protection event detected on your child\'s phone';
    }
  }

  Future<void> _enqueueLocal(Map<String, dynamic> payload) async {
    final serializable = payload.map((key, value) {
      if (value is FieldValue) {
        return MapEntry(key, null);
      }
      return MapEntry(key, value);
    });
    _queuedEvents.add(serializable);
    await _persistLocalQueue();
  }

  Future<void> _persistLocalQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _queuedEvents.map(jsonEncode).toList(growable: false);
      await prefs.setStringList(_localQueueKey, encoded);
    } catch (_) {
      // Queue persistence is best effort.
    }
  }

  Future<void> _hydrateLocalQueue() async {
    if (_queuedEvents.isNotEmpty) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_localQueueKey) ?? const <String>[];
      for (final item in raw) {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          _queuedEvents.add(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    } catch (_) {
      // Ignore hydration failures.
    }
  }
}
