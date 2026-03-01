import 'dart:async';
import 'package:trustbridge_app/core/utils/app_logger.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:workmanager/workmanager.dart';

import '../models/app_mode.dart';
import 'app_mode_service.dart';
import 'notification_service.dart';
import 'pairing_service.dart';
import 'vpn_service.dart';

/// Parent-visible command execution result model.
class CommandResult {
  const CommandResult({
    required this.commandId,
    required this.status,
    this.executedAt,
  });

  final String commandId;
  final String status;
  final DateTime? executedAt;
}

/// Sends and executes remote commands for child protection actions.
class RemoteCommandService {
  static const String taskName = 'trustbridge_remote_command_poll';
  static const String _uniqueTaskName =
      'trustbridge_remote_command_poll_unique';
  static const Duration _pollFrequency = Duration(minutes: 15);
  static const String commandRestartVpn = 'restartVpn';
  static const String commandClearPairingAndStopProtection =
      'clearPairingAndStopProtection';

  RemoteCommandService({
    FirebaseFirestore? firestore,
    PairingService? pairingService,
    VpnServiceBase? vpnService,
    AppModeService? appModeService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _pairingService = pairingService ?? PairingService(),
        _vpnService = vpnService ?? VpnService(),
        _appModeService = appModeService ?? AppModeService();

  final FirebaseFirestore _firestore;
  final PairingService _pairingService;
  final VpnServiceBase _vpnService;
  final AppModeService _appModeService;

  /// Registers periodic command polling.
  static Future<void> initialize() async {
    try {
      await Workmanager().registerPeriodicTask(
        _uniqueTaskName,
        taskName,
        frequency: _pollFrequency,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } catch (_) {
      // Registration is best effort.
    }
  }

  /// Parent sends a restart protection command.
  Future<String> sendRestartVpnCommand(String deviceId) async {
    return _sendCommand(
      deviceId: deviceId,
      command: commandRestartVpn,
    );
  }

  /// Parent sends a cleanup command after child profile deletion/unlink.
  Future<String> sendClearPairingAndStopProtectionCommand(
    String deviceId, {
    String? childId,
    String? reason,
  }) async {
    return _sendCommand(
      deviceId: deviceId,
      command: commandClearPairingAndStopProtection,
      extraData: <String, dynamic>{
        if (childId != null && childId.trim().isNotEmpty)
          'childId': childId.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  Future<String> _sendCommand({
    required String deviceId,
    required String command,
    Map<String, dynamic> extraData = const <String, dynamic>{},
  }) async {
    var parentId = (await _pairingService.getPairedParentId())?.trim();
    if (parentId == null || parentId.isEmpty) {
      try {
        parentId = FirebaseAuth.instance.currentUser?.uid.trim();
      } catch (_) {
        parentId = null;
      }
    }
    if (parentId == null || parentId.isEmpty) {
      throw StateError('Parent must be signed in to send commands.');
    }

    final ref = _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('pendingCommands')
        .doc();
    await ref.set(<String, dynamic>{
      'commandId': ref.id,
      'parentId': parentId,
      'command': command,
      'status': 'pending',
      'attempts': 0,
      'sentAt': FieldValue.serverTimestamp(),
      ...extraData,
    });
    return ref.id;
  }

  /// Child processes pending command queue.
  Future<void> processPendingCommands() async {
    final mode = await _appModeService.getMode();
    if (mode == AppMode.parent) {
      AppLogger.debug(
        '[RemoteCommandService] Skip command polling in parent mode.',
      );
      return;
    }

    final deviceId = await _pairingService.getOrCreateDeviceId();
    final pairedParentId = (await _pairingService.getPairedParentId())?.trim();
    var query = _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('pendingCommands')
        .where('status', isEqualTo: 'pending');
    if (pairedParentId != null && pairedParentId.isNotEmpty) {
      query = query.where('parentId', isEqualTo: pairedParentId);
    }
    final snapshot = await query.get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final command = (data['command'] as String?) ?? '';
      final attempts = _readInt(data['attempts']);

      if (attempts >= 3) {
        await _markCommandResult(
          doc.reference,
          status: 'failed',
          attempts: attempts,
          error: 'Max attempts reached',
        );
        continue;
      }

      try {
        final executed = await _executeCommand(
          command: command,
          payload: data,
        );
        await _markCommandResult(
          doc.reference,
          status: executed ? 'executed' : 'failed',
          attempts: attempts,
        );
      } catch (error) {
        await _markCommandResult(
          doc.reference,
          status: 'failed',
          attempts: attempts,
          error: error.toString(),
        );
      }
    }
  }

  Future<void> _markCommandResult(
    DocumentReference<Map<String, dynamic>> reference, {
    required String status,
    required int attempts,
    String? error,
  }) async {
    try {
      await reference.update(<String, dynamic>{
        'status': status,
        'attempts': attempts + 1,
        'executedAt': FieldValue.serverTimestamp(),
        if (error != null && error.trim().isNotEmpty) 'error': error.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (updateError) {
      AppLogger.debug(
          '[RemoteCommandService] command result update failed: $updateError');
    }
  }

  Future<bool> _executeCommand({
    required String command,
    required Map<String, dynamic> payload,
  }) async {
    switch (command) {
      case commandRestartVpn:
        return _restartVpnWithPairingContext();
      case commandClearPairingAndStopProtection:
        return _clearPairingAndStopProtection(payload);
      default:
        return false;
    }
  }

  Future<bool> _restartVpnWithPairingContext() async {
    final parentId = (await _pairingService.getPairedParentId())?.trim();
    final childId = (await _pairingService.getPairedChildId())?.trim();

    return _vpnService.restartVpn(
      parentId: (parentId == null || parentId.isEmpty) ? null : parentId,
      childId: (childId == null || childId.isEmpty) ? null : childId,
      usePersistedRules: true,
    );
  }

  Future<bool> _clearPairingAndStopProtection(
    Map<String, dynamic> payload,
  ) async {
    final targetChildId = (payload['childId'] as String?)?.trim();
    final localChildId = (await _pairingService.getPairedChildId())?.trim();
    if (targetChildId != null &&
        targetChildId.isNotEmpty &&
        localChildId != null &&
        localChildId.isNotEmpty &&
        targetChildId != localChildId) {
      // Command was intended for an earlier child assignment on this device.
      return true;
    }

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
      return false;
    }

    try {
      await NotificationService().showLocalNotification(
        title: 'Protection turned off',
        body:
            'This phone is no longer paired. Ask your parent to reconnect setup.',
        route: '/child/setup',
      );
    } catch (_) {
      // Best-effort user visibility.
    }

    return true;
  }

  /// Parent watches command status stream by command id.
  Stream<CommandResult> watchCommandResult(String commandId) {
    return _firestore
        .collectionGroup('pendingCommands')
        .where('commandId', isEqualTo: commandId)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return CommandResult(commandId: commandId, status: 'pending');
      }
      final data = snapshot.docs.first.data();
      return CommandResult(
        commandId: commandId,
        status: (data['status'] as String?) ?? 'pending',
        executedAt: _readDateTime(data['executedAt']),
      );
    });
  }

  int _readInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return 0;
  }

  DateTime? _readDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return null;
  }
}
