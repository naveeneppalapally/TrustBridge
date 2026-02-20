import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/app_mode.dart';
import 'app_mode_service.dart';
import 'notification_service.dart';

/// Pairing errors returned by child setup flow.
enum PairingError {
  /// Code not found or malformed.
  invalidCode,

  /// Code exists but is expired.
  expiredCode,

  /// Code has already been consumed.
  alreadyUsed,

  /// Unexpected network/runtime issue.
  networkError,
}

/// Result object for pairing validation attempts.
class PairingResult {
  /// Creates a pairing result.
  const PairingResult({
    required this.success,
    this.childId,
    this.parentId,
    this.error,
  });

  /// Success flag.
  final bool success;

  /// Paired child profile id on success.
  final String? childId;

  /// Parent uid associated with the pairing.
  final String? parentId;

  /// Failure reason when [success] is false.
  final PairingError? error;

  /// Convenience success constructor.
  factory PairingResult.success({
    required String childId,
    required String parentId,
  }) {
    return PairingResult(
      success: true,
      childId: childId,
      parentId: parentId,
    );
  }

  /// Convenience error constructor.
  factory PairingResult.failure(PairingError error) {
    return PairingResult(
      success: false,
      error: error,
    );
  }
}

class _PairingGuardException implements Exception {
  const _PairingGuardException(this.error);

  final PairingError error;
}

/// Parent-child device pairing service.
class PairingService {
  PairingService({
    FirebaseFirestore? firestore,
    FlutterSecureStorage? secureStorage,
    AppModeService? appModeService,
    String? Function()? currentUserIdResolver,
    Future<String?> Function()? fcmTokenProvider,
    String Function()? deviceModelProvider,
    DateTime Function()? nowProvider,
  })  : _firestoreOverride = firestore,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _appModeServiceOverride = appModeService,
        _currentUserIdResolver = currentUserIdResolver,
        _fcmTokenProvider = fcmTokenProvider,
        _deviceModelProvider = deviceModelProvider,
        _nowProvider = nowProvider ?? DateTime.now;

  static const String _deviceIdKey = 'pairing_device_id';
  static const String _pairedChildIdKey = 'paired_child_id';
  static const String _pairedParentIdKey = 'paired_parent_id';
  static const Duration _expiryWindow = Duration(minutes: 15);

  final FirebaseFirestore? _firestoreOverride;
  final FlutterSecureStorage _secureStorage;
  final AppModeService? _appModeServiceOverride;
  final String? Function()? _currentUserIdResolver;
  final Future<String?> Function()? _fcmTokenProvider;
  final String Function()? _deviceModelProvider;
  final DateTime Function() _nowProvider;

  final Random _random = Random.secure();

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  AppModeService get _appModeService =>
      _appModeServiceOverride ?? AppModeService();

  /// Generates and persists a 6-digit pairing code for a child profile.
  Future<String> generatePairingCode(String childId) async {
    final trimmedChildId = childId.trim();
    if (trimmedChildId.isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final parentId = (_currentUserIdResolver?.call() ?? FirebaseAuth.instance.currentUser?.uid)
        ?.trim();
    if (parentId == null || parentId.isEmpty) {
      throw StateError('Parent must be signed in to generate pairing codes.');
    }

    final code = await _generateUniqueSixDigitCode();
    final expiresAt = _nowProvider().add(_expiryWindow);

    await _firestore.collection('pairing_codes').doc(code).set(<String, dynamic>{
      'code': code,
      'childId': trimmedChildId,
      'parentId': parentId,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'used': false,
    });

    return code;
  }

  /// Validates a pairing code and links this device to child profile.
  Future<PairingResult> validateAndPair(String code, String deviceId) async {
    final normalizedCode = code.trim();
    final normalizedDeviceId = deviceId.trim();
    if (!_isSixDigitCode(normalizedCode)) {
      return PairingResult.failure(PairingError.invalidCode);
    }
    if (normalizedDeviceId.isEmpty) {
      return PairingResult.failure(PairingError.networkError);
    }

    try {
      String? childId;
      String? parentId;

      await _firestore.runTransaction((transaction) async {
        final codeRef = _firestore.collection('pairing_codes').doc(normalizedCode);
        final codeSnapshot = await transaction.get(codeRef);
        if (!codeSnapshot.exists) {
          throw const _PairingGuardException(PairingError.invalidCode);
        }

        final data = codeSnapshot.data() ?? const <String, dynamic>{};
        final used = data['used'] == true;
        if (used) {
          throw const _PairingGuardException(PairingError.alreadyUsed);
        }

        final expiresAt = _asDateTime(data['expiresAt']);
        if (expiresAt == null || !expiresAt.isAfter(_nowProvider())) {
          throw const _PairingGuardException(PairingError.expiredCode);
        }

        final resolvedChildId = (data['childId'] as String?)?.trim() ?? '';
        final resolvedParentId = (data['parentId'] as String?)?.trim() ?? '';
        if (resolvedChildId.isEmpty || resolvedParentId.isEmpty) {
          throw const _PairingGuardException(PairingError.invalidCode);
        }

        childId = resolvedChildId;
        parentId = resolvedParentId;

        transaction.update(codeRef, <String, dynamic>{
          'used': true,
          'usedAt': FieldValue.serverTimestamp(),
          'usedByDeviceId': normalizedDeviceId,
        });
      });

      if (childId == null || parentId == null) {
        return PairingResult.failure(PairingError.networkError);
      }

      final childRef = _firestore.collection('children').doc(childId);
      await childRef.set(
        <String, dynamic>{
          'parentId': parentId,
          'deviceIds': FieldValue.arrayUnion(<String>[normalizedDeviceId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await _secureStorage.write(key: _pairedChildIdKey, value: childId);
      await _secureStorage.write(key: _pairedParentIdKey, value: parentId);
      await _appModeService.setMode(AppMode.child);

      await _saveDeviceRecord(
        childId: childId!,
        parentId: parentId!,
        deviceId: normalizedDeviceId,
      );

      return PairingResult.success(
        childId: childId!,
        parentId: parentId!,
      );
    } on _PairingGuardException catch (error) {
      return PairingResult.failure(error.error);
    } on FirebaseException {
      return PairingResult.failure(PairingError.networkError);
    } catch (_) {
      return PairingResult.failure(PairingError.networkError);
    }
  }

  /// Returns persisted device ID or creates one on first run.
  Future<String> getOrCreateDeviceId() async {
    final existing = (await _secureStorage.read(key: _deviceIdKey))?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = const Uuid().v4();
    await _secureStorage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  /// Reads the paired child identifier stored locally.
  Future<String?> getPairedChildId() async {
    final value = await _secureStorage.read(key: _pairedChildIdKey);
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  /// Reads the paired parent identifier stored locally.
  Future<String?> getPairedParentId() async {
    final value = await _secureStorage.read(key: _pairedParentIdKey);
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  /// Clears local pairing identifiers for recovery from interrupted setup.
  Future<void> clearLocalPairing() async {
    await _secureStorage.delete(key: _pairedChildIdKey);
    await _secureStorage.delete(key: _pairedParentIdKey);
  }

  /// Watches pairing-code usage state.
  Stream<bool> watchCodeUsed(String code) {
    final normalizedCode = code.trim();
    if (!_isSixDigitCode(normalizedCode)) {
      return const Stream<bool>.empty();
    }
    return _firestore
        .collection('pairing_codes')
        .doc(normalizedCode)
        .snapshots()
        .map((snapshot) => snapshot.data()?['used'] == true);
  }

  Future<void> _saveDeviceRecord({
    required String childId,
    required String parentId,
    required String deviceId,
  }) async {
    final fcmToken =
        await (_fcmTokenProvider?.call() ?? NotificationService().getToken());
    final record = <String, dynamic>{
      'parentId': parentId,
      'model': _deviceModelProvider?.call() ?? _deviceModel(),
      'osVersion': Platform.operatingSystemVersion,
      'fcmToken': fcmToken,
      'pairedAt': FieldValue.serverTimestamp(),
    };

    await _firestore
        .collection('children')
        .doc(childId)
        .collection('devices')
        .doc(deviceId)
        .set(record, SetOptions(merge: true));
  }

  Future<String> _generateUniqueSixDigitCode() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final candidate = _generateSixDigitCode();
      final snapshot =
          await _firestore.collection('pairing_codes').doc(candidate).get();
      if (!snapshot.exists) {
        return candidate;
      }
    }
    return _generateSixDigitCode();
  }

  String _generateSixDigitCode() {
    return _random.nextInt(1000000).toString().padLeft(6, '0');
  }

  bool _isSixDigitCode(String code) {
    return RegExp(r'^\d{6}$').hasMatch(code);
  }

  DateTime? _asDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  String _deviceModel() {
    return Platform.isAndroid ? 'Android Device' : Platform.operatingSystem;
  }
}
