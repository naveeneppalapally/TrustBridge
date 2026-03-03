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

  /// Too many failed attempts from the same device in a short window.
  tooManyAttempts,

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

class _PairingTransactionOutcome {
  const _PairingTransactionOutcome({
    required this.success,
    this.childId,
    this.parentId,
    this.error,
  });

  final bool success;
  final String? childId;
  final String? parentId;
  final PairingError? error;

  const _PairingTransactionOutcome.success({
    required String childId,
    required String parentId,
  }) : this(
          success: true,
          childId: childId,
          parentId: parentId,
        );

  const _PairingTransactionOutcome.failure(PairingError error)
      : this(
          success: false,
          error: error,
        );
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
  static const Duration _lookupAttemptWindow = Duration(minutes: 10);
  static const int _maxLookupAttemptsPerWindow = 5;
  static const int pairingCodeLength = 8;
  static const String _pairingAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static final RegExp _pairingCodePattern = RegExp(
    '^[$_pairingAlphabet]{$pairingCodeLength}\$',
  );

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

  /// Normalizes raw user input into uppercase, non-ambiguous pairing chars.
  static String normalizePairingCodeInput(String raw) {
    final upper = raw.trim().toUpperCase();
    if (upper.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    for (final rune in upper.runes) {
      final character = String.fromCharCode(rune);
      if (_pairingAlphabet.contains(character)) {
        buffer.write(character);
      }
    }
    return buffer.toString();
  }

  /// Returns true when [code] matches the secure pairing format.
  static bool isValidPairingCode(String code) {
    return _pairingCodePattern.hasMatch(code.trim().toUpperCase());
  }

  /// Returns true when [character] is allowed in a pairing code.
  static bool isAllowedPairingCharacter(String character) {
    if (character.length != 1) {
      return false;
    }
    return _pairingAlphabet.contains(character.toUpperCase());
  }

  /// Generates and persists an 8-character secure pairing code.
  Future<String> generatePairingCode(
    String childId, {
    String? parentIdOverride,
  }) async {
    final trimmedChildId = childId.trim();
    if (trimmedChildId.isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final overrideParentId = parentIdOverride?.trim();
    final parentId = (overrideParentId != null && overrideParentId.isNotEmpty)
        ? overrideParentId
        : (_currentUserIdResolver?.call() ??
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

    final code = await _generateUniquePairingCode();
    final expiresAt = _nowProvider().add(_expiryWindow);
    final createdAt = Timestamp.fromDate(_nowProvider());

    await _firestore
        .collection('pairing_codes')
        .doc(code)
        .set(<String, dynamic>{
      'code': code,
      'childId': trimmedChildId,
      'parentId': parentId,
      'createdAt': createdAt,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'used': false,
      'lookupAttempts': 0,
      'firstAttemptAt': null,
      'lookupDeviceId': null,
    });

    return code;
  }

  /// Validates a pairing code and links this device to child profile.
  Future<PairingResult> validateAndPair(String code, String deviceId) async {
    final normalizedCode = normalizePairingCodeInput(code);
    final normalizedDeviceId = deviceId.trim();
    if (!isValidPairingCode(normalizedCode)) {
      return PairingResult.failure(PairingError.invalidCode);
    }
    if (normalizedDeviceId.isEmpty) {
      return PairingResult.failure(PairingError.networkError);
    }

    try {
      var authUid = '';
      try {
        authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      } catch (_) {
        authUid = '';
      }
      if (authUid.isEmpty) {
        authUid = _currentUserIdResolver?.call()?.trim() ?? '';
      }
      final lookupDeviceId = authUid.isNotEmpty ? authUid : normalizedDeviceId;
      final outcome =
          await _firestore.runTransaction<_PairingTransactionOutcome>(
        (transaction) async {
          final now = _nowProvider();
          final codeRef = _firestore.collection('pairing_codes').doc(
                normalizedCode,
              );
          final codeSnapshot = await transaction.get(codeRef);
          if (!codeSnapshot.exists) {
            return const _PairingTransactionOutcome.failure(
              PairingError.invalidCode,
            );
          }

          final data = codeSnapshot.data() ?? const <String, dynamic>{};
          final used = data['used'] == true;
          final expiresAt = _asDateTime(data['expiresAt']);
          final resolvedChildId = (data['childId'] as String?)?.trim() ?? '';
          final resolvedParentId = (data['parentId'] as String?)?.trim() ?? '';

          final throttled = _isLookupThrottled(
            data: data,
            lookupDeviceId: lookupDeviceId,
            now: now,
          );
          if (throttled) {
            return const _PairingTransactionOutcome.failure(
              PairingError.tooManyAttempts,
            );
          }

          if (used || expiresAt == null || !expiresAt.isAfter(now)) {
            transaction.update(
              codeRef,
              _nextLookupAttemptPayload(
                data: data,
                lookupDeviceId: lookupDeviceId,
                now: now,
              ),
            );
            return _PairingTransactionOutcome.failure(
              used ? PairingError.alreadyUsed : PairingError.expiredCode,
            );
          }

          if (resolvedChildId.isEmpty || resolvedParentId.isEmpty) {
            transaction.update(
              codeRef,
              _nextLookupAttemptPayload(
                data: data,
                lookupDeviceId: lookupDeviceId,
                now: now,
              ),
            );
            return const _PairingTransactionOutcome.failure(
              PairingError.invalidCode,
            );
          }

          transaction.update(codeRef, <String, dynamic>{
            'used': true,
            'usedAt': Timestamp.fromDate(now),
            'usedByDeviceId': normalizedDeviceId,
            'lookupAttempts': 0,
            'firstAttemptAt': null,
            'lookupDeviceId': null,
          });

          return _PairingTransactionOutcome.success(
            childId: resolvedChildId,
            parentId: resolvedParentId,
          );
        },
      );

      if (!outcome.success) {
        return PairingResult.failure(
            outcome.error ?? PairingError.networkError);
      }

      final childId = outcome.childId;
      final parentId = outcome.parentId;
      if (childId == null || parentId == null) {
        return PairingResult.failure(PairingError.networkError);
      }

      await _secureStorage.write(key: _pairedChildIdKey, value: childId);
      await _secureStorage.write(key: _pairedParentIdKey, value: parentId);
      await _appModeService.setMode(AppMode.child);

      try {
        await _saveDeviceRecord(
          childId: childId,
          parentId: parentId,
          deviceId: normalizedDeviceId,
        );
      } catch (_) {
        // Non-fatal in child pairing bootstrap.
      }

      final childRef = _firestore.collection('children').doc(childId);
      try {
        final updatedAt = Timestamp.fromDate(_nowProvider());
        await childRef.set(
          <String, dynamic>{
            'parentId': parentId,
            'deviceIds': FieldValue.arrayUnion(<String>[normalizedDeviceId]),
            'updatedAt': updatedAt,
          },
          SetOptions(merge: true),
        );
      } catch (_) {
        // Non-fatal in child pairing bootstrap. Device record still allows access.
      }

      return PairingResult.success(
        childId: childId,
        parentId: parentId,
      );
      // Note: The caller (child setup screen) should trigger an immediate
      // HeartbeatService.sendHeartbeat() after receiving this success result
      // so that the parent dashboard shows the device as online right away.
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

  bool _isLookupThrottled({
    required Map<String, dynamic> data,
    required String lookupDeviceId,
    required DateTime now,
  }) {
    if (lookupDeviceId.isEmpty) {
      return false;
    }
    final trackedDeviceId = (data['lookupDeviceId'] as String?)?.trim() ?? '';
    if (trackedDeviceId.isEmpty || trackedDeviceId != lookupDeviceId) {
      return false;
    }
    final firstAttemptAt = _asDateTime(data['firstAttemptAt']);
    if (firstAttemptAt == null) {
      return false;
    }
    if (now.difference(firstAttemptAt) > _lookupAttemptWindow) {
      return false;
    }
    final attempts = _asInt(data['lookupAttempts']);
    return attempts >= _maxLookupAttemptsPerWindow;
  }

  Map<String, dynamic> _nextLookupAttemptPayload({
    required Map<String, dynamic> data,
    required String lookupDeviceId,
    required DateTime now,
  }) {
    final trackedDeviceId = (data['lookupDeviceId'] as String?)?.trim() ?? '';
    final firstAttemptAt = _asDateTime(data['firstAttemptAt']);
    final attempts = _asInt(data['lookupAttempts']);
    final withinActiveWindow = trackedDeviceId == lookupDeviceId &&
        firstAttemptAt != null &&
        now.difference(firstAttemptAt) <= _lookupAttemptWindow;

    if (withinActiveWindow) {
      return <String, dynamic>{
        'lookupDeviceId': lookupDeviceId,
        'firstAttemptAt': Timestamp.fromDate(firstAttemptAt),
        'lookupAttempts': attempts + 1,
      };
    }

    return <String, dynamic>{
      'lookupDeviceId': lookupDeviceId,
      'firstAttemptAt': FieldValue.serverTimestamp(),
      'lookupAttempts': 1,
    };
  }

  int _asInt(Object? raw) {
    if (raw is int) {
      return raw < 0 ? 0 : raw;
    }
    if (raw is num) {
      final value = raw.toInt();
      return value < 0 ? 0 : value;
    }
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed >= 0) {
        return parsed;
      }
    }
    return 0;
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
      final childSnapshot =
          childDocRef == null ? null : await childDocRef.get();

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
    final normalizedCode = normalizePairingCodeInput(code);
    if (!isValidPairingCode(normalizedCode)) {
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
      'pairedAt': Timestamp.fromDate(_nowProvider()),
    };

    await _firestore
        .collection('children')
        .doc(childId)
        .collection('devices')
        .doc(deviceId)
        .set(record, SetOptions(merge: true));
  }

  Future<String> _generateUniquePairingCode() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final candidate = _generatePairingCode();
      final snapshot =
          await _firestore.collection('pairing_codes').doc(candidate).get();
      if (!snapshot.exists) {
        return candidate;
      }
    }
    return _generatePairingCode();
  }

  String _generatePairingCode() {
    final characters = List<String>.generate(
      pairingCodeLength,
      (_) => _pairingAlphabet[_random.nextInt(_pairingAlphabet.length)],
      growable: false,
    );
    return characters.join();
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
