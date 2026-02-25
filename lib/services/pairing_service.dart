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

  /// Caller is authenticated but missing permission for the pairing operation.
  permissionDenied,

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

/// Canonical child/parent linkage resolved from pairing storage or cloud.
class PairingContext {
  /// Creates a pairing context.
  const PairingContext({
    required this.childId,
    required this.parentId,
  });

  /// Paired child profile id.
  final String childId;

  /// Owning parent uid.
  final String parentId;
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

    final parentId = (_currentUserIdResolver?.call() ??
            FirebaseAuth.instance.currentUser?.uid)
        ?.trim();
    if (parentId == null || parentId.isEmpty) {
      throw StateError('Parent must be signed in to generate pairing codes.');
    }

    final childSnapshot =
        await _firestore.collection('children').doc(trimmedChildId).get();
    if (!childSnapshot.exists) {
      throw StateError(
          'Child profile not found. Please refresh and try again.');
    }
    final childData = childSnapshot.data() ?? const <String, dynamic>{};
    final childParentId = (childData['parentId'] as String?)?.trim();
    if (childParentId == null ||
        childParentId.isEmpty ||
        childParentId != parentId) {
      throw StateError(
        'You can only generate setup codes for your own child profiles.',
      );
    }

    final code = await _generateUniqueSixDigitCode();
    final expiresAt = _nowProvider().add(_expiryWindow);

    await _firestore
        .collection('pairing_codes')
        .doc(code)
        .set(<String, dynamic>{
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
        final codeRef =
            _firestore.collection('pairing_codes').doc(normalizedCode);
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

      await _secureStorage.write(key: _pairedChildIdKey, value: childId);
      await _secureStorage.write(key: _pairedParentIdKey, value: parentId);
      await _appModeService.setMode(AppMode.child);

      try {
        await _saveDeviceRecord(
          childId: childId!,
          parentId: parentId!,
          deviceId: normalizedDeviceId,
        );
      } catch (_) {
        // Non-fatal in child pairing bootstrap.
      }

      final childRef = _firestore.collection('children').doc(childId);
      try {
        await childRef.set(
          <String, dynamic>{
            'parentId': parentId,
            'deviceIds': FieldValue.arrayUnion(<String>[normalizedDeviceId]),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {
        // Non-fatal in child pairing bootstrap. Device record still allows access.
      }

      return PairingResult.success(
        childId: childId!,
        parentId: parentId!,
      );
      // Note: The caller (child setup screen) should trigger an immediate
      // HeartbeatService.sendHeartbeat() after receiving this success result
      // so that the parent dashboard shows the device as online right away.
    } on _PairingGuardException catch (error) {
      return PairingResult.failure(error.error);
    } on FirebaseException catch (error) {
      final code = error.code.trim().toLowerCase();
      if (code == 'permission-denied' || code == 'unauthenticated') {
        return PairingResult.failure(PairingError.permissionDenied);
      }
      return PairingResult.failure(PairingError.networkError);
    } catch (_) {
      return PairingResult.failure(PairingError.networkError);
    }
  }

  /// Returns persisted device ID or creates one on first run.
  Future<String> getOrCreateDeviceId() async {
    User? authUser;
    String? authUid;
    var isAnonymousSession = false;
    try {
      authUser = FirebaseAuth.instance.currentUser;
      authUid = authUser?.uid.trim();
      isAnonymousSession = authUser?.isAnonymous == true;
    } catch (_) {
      authUser = null;
      authUid = null;
      isAnonymousSession = false;
    }

    final existing = (await _secureStorage.read(key: _deviceIdKey))?.trim();

    // For anonymous bootstrap sessions, keep deviceId aligned to auth uid so
    // Firestore rules can authorize child-device document writes.
    if (isAnonymousSession && authUid != null && authUid.isNotEmpty) {
      if (existing == null || existing.isEmpty || existing != authUid) {
        await _secureStorage.write(key: _deviceIdKey, value: authUid);
      }
      return authUid;
    }

    if (existing != null && existing.isNotEmpty) {
      if (_isLegacyAuthBoundDeviceId(
        existingDeviceId: existing,
        currentAuthUid: authUid,
      )) {
        final migrated = const Uuid().v4();
        await _secureStorage.write(key: _deviceIdKey, value: migrated);
        return migrated;
      }
      return existing;
    }

    final generated = const Uuid().v4();
    await _secureStorage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  bool _isLegacyAuthBoundDeviceId({
    required String existingDeviceId,
    required String? currentAuthUid,
  }) {
    if (currentAuthUid == null || currentAuthUid.isEmpty) {
      return false;
    }
    if (existingDeviceId != currentAuthUid) {
      return false;
    }
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{12}$',
    );
    return !uuidPattern.hasMatch(existingDeviceId);
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

  /// Attempts to recover pairing context from cloud using this device ID.
  ///
  /// This is used when local secure storage is stale or cleared unexpectedly.
  Future<PairingContext?> recoverPairingFromCloud() async {
    final deviceId = await getOrCreateDeviceId();
    if (deviceId.trim().isEmpty) {
      return null;
    }

    try {
      final childrenSnapshot = await _firestore
          .collection('children')
          .where('deviceIds', arrayContains: deviceId)
          .limit(1)
          .get();
      if (childrenSnapshot.docs.isNotEmpty) {
        final doc = childrenSnapshot.docs.first;
        final parentId = (doc.data()['parentId'] as String?)?.trim();
        final childId = doc.id.trim();
        if (parentId != null && parentId.isNotEmpty && childId.isNotEmpty) {
          await _secureStorage.write(key: _pairedChildIdKey, value: childId);
          await _secureStorage.write(key: _pairedParentIdKey, value: parentId);
          return PairingContext(childId: childId, parentId: parentId);
        }
      }
    } catch (_) {
      // Continue with secondary lookup strategy.
    }

    try {
      final deviceSnapshot = await _firestore
          .collectionGroup('devices')
          .where(FieldPath.documentId, isEqualTo: deviceId)
          .limit(1)
          .get();
      if (deviceSnapshot.docs.isEmpty) {
        return null;
      }

      final deviceDoc = deviceSnapshot.docs.first;
      final childDocRef = deviceDoc.reference.parent.parent;
      final childId = childDocRef?.id.trim();
      var parentId = (deviceDoc.data()['parentId'] as String?)?.trim();
      final childSnapshot = childDocRef == null ? null : await childDocRef.get();

      if (childSnapshot == null || !childSnapshot.exists) {
        return null;
      }

      if ((parentId == null || parentId.isEmpty) &&
          childDocRef != null &&
          childDocRef.path.isNotEmpty) {
        final childData = childSnapshot.data();
        final rawParentId = childData?['parentId'];
        if (rawParentId is String && rawParentId.trim().isNotEmpty) {
          parentId = rawParentId.trim();
        }
      }

      final childData = childSnapshot.data() ?? const <String, dynamic>{};
      final rawDeviceIds = childData['deviceIds'];
      if (rawDeviceIds is List) {
        final registeredDeviceIds = rawDeviceIds
            .map((raw) => raw?.toString().trim() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        if (registeredDeviceIds.isNotEmpty &&
            !registeredDeviceIds.contains(deviceId)) {
          return null;
        }
      }

      if (childId == null ||
          childId.isEmpty ||
          parentId == null ||
          parentId.isEmpty) {
        return null;
      }

      await _secureStorage.write(key: _pairedChildIdKey, value: childId);
      await _secureStorage.write(key: _pairedParentIdKey, value: parentId);
      return PairingContext(childId: childId, parentId: parentId);
    } catch (_) {
      return null;
    }
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
