import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/core/utils/app_logger.dart';

import '../models/subscription.dart';
import 'auth_service.dart';

/// Reads and manages subscription/trial state for the current parent account.
class SubscriptionService {
  SubscriptionService({
    FirebaseFirestore? firestore,
    AuthService? authService,
    DateTime Function()? nowProvider,
    String? Function()? currentUserIdResolver,
    Stream<String?>? userIdChanges,
  })  : _firestoreOverride = firestore,
        _authServiceOverride = authService,
        _nowProvider = nowProvider ?? DateTime.now,
        _currentUserIdResolver = currentUserIdResolver,
        _userIdChanges = userIdChanges;

  final FirebaseFirestore? _firestoreOverride;
  final AuthService? _authServiceOverride;
  final DateTime Function() _nowProvider;
  final String? Function()? _currentUserIdResolver;
  final Stream<String?>? _userIdChanges;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  AuthService get _authService => _authServiceOverride ?? AuthService();

  /// Returns current subscription from `parents/{parentId}.subscription`.
  Future<Subscription> getCurrentSubscription() async {
    final parentId =
        (_currentUserIdResolver?.call() ?? _authService.currentUser?.uid);
    if (parentId == null || parentId.trim().isEmpty) {
      return Subscription.free();
    }

    final snapshot = await _firestore.collection('parents').doc(parentId).get();
    if (!snapshot.exists) {
      return Subscription.free();
    }

    final data = snapshot.data();
    final raw = data?['subscription'];
    final map = _toMap(raw);
    final parsed = Subscription.fromMap(map);
    return parsed.effectiveTier == SubscriptionTier.free
        ? Subscription.free()
        : parsed;
  }

  /// Refresh hook for Play Store purchase sync (stub for post-submission day).
  Future<void> refreshFromPlayStore() async {
    AppLogger.debug('[Subscription] refreshFromPlayStore called (stub).');
  }

  /// Starts one-time 7 day trial. Returns false when trial already used.
  Future<bool> startTrial() async {
    final parentId =
        (_currentUserIdResolver?.call() ?? _authService.currentUser?.uid);
    if (parentId == null || parentId.trim().isEmpty) {
      return false;
    }

    final parentRef = _firestore.collection('parents').doc(parentId);
    final trialEndsAt = _nowProvider().add(const Duration(days: 7));

    return _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(parentRef);
      final data = snapshot.data() ?? const <String, dynamic>{};
      final subscription = _toMap(data['subscription']);
      final trialUsed = subscription['trialUsed'] == true;
      if (trialUsed) {
        return false;
      }

      final existingToken = (subscription['purchaseToken'] as String?)?.trim();
      transaction.set(
        parentRef,
        <String, dynamic>{
          'subscription': <String, dynamic>{
            'tier': 'pro',
            'isInTrial': true,
            'trialUsed': true,
            'trialEndsAt': Timestamp.fromDate(trialEndsAt),
            'validUntil': Timestamp.fromDate(trialEndsAt),
            if (existingToken != null && existingToken.isNotEmpty)
              'purchaseToken': existingToken,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );
      return true;
    });
  }

  /// Watches subscription changes for the current parent.
  Stream<Subscription> watchSubscription() async* {
    final userIds = _userIdChanges ??
        _authService.authStateChanges.map((user) => user?.uid);
    await for (final userId in userIds) {
      if (userId == null || userId.trim().isEmpty) {
        yield Subscription.free();
        continue;
      }
      yield* _firestore.collection('parents').doc(userId).snapshots().map(
        (snapshot) {
          final data = snapshot.data();
          final raw = data?['subscription'];
          final parsed = Subscription.fromMap(_toMap(raw));
          return parsed.effectiveTier == SubscriptionTier.free
              ? Subscription.free()
              : parsed;
        },
      );
    }
  }

  Map<String, dynamic> _toMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }
}
