import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:workmanager/workmanager.dart';

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

  RemoteCommandService({
    FirebaseFirestore? firestore,
    PairingService? pairingService,
    VpnServiceBase? vpnService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _pairingService = pairingService ?? PairingService(),
        _vpnService = vpnService ?? VpnService();

  final FirebaseFirestore _firestore;
  final PairingService _pairingService;
  final VpnServiceBase _vpnService;

  /// Registers periodic command polling.
  static Future<void> initialize() async {
    try {
      await Workmanager().registerPeriodicTask(
        _uniqueTaskName,
        taskName,
        frequency: _pollFrequency,
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } catch (_) {
      // Registration is best effort.
    }
  }

  /// Parent sends a restart protection command.
  Future<String> sendRestartVpnCommand(String deviceId) async {
    final ref = _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('pendingCommands')
        .doc();
    await ref.set(<String, dynamic>{
      'commandId': ref.id,
      'command': 'restartVpn',
      'status': 'pending',
      'attempts': 0,
      'sentAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Child processes pending command queue.
  Future<void> processPendingCommands() async {
    final deviceId = await _pairingService.getOrCreateDeviceId();
    final snapshot = await _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('pendingCommands')
        .where('status', isEqualTo: 'pending')
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final command = (data['command'] as String?) ?? '';
      final attempts = _readInt(data['attempts']);

      if (command != 'restartVpn') {
        await doc.reference.update(<String, dynamic>{
          'status': 'failed',
          'error': 'Unknown command',
          'executedAt': FieldValue.serverTimestamp(),
        });
        continue;
      }

      if (attempts >= 3) {
        await doc.reference.update(<String, dynamic>{
          'status': 'failed',
          'error': 'Max attempts reached',
          'executedAt': FieldValue.serverTimestamp(),
        });
        continue;
      }

      try {
        final executed = await _vpnService.restartVpn();
        await doc.reference.update(<String, dynamic>{
          'status': executed ? 'executed' : 'failed',
          'attempts': attempts + 1,
          'executedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        await doc.reference.update(<String, dynamic>{
          'status': 'failed',
          'attempts': attempts + 1,
          'executedAt': FieldValue.serverTimestamp(),
        });
      }
    }
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
