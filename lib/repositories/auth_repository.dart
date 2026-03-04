import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';

class AuthRepository {
  AuthRepository({
    required FirebaseFirestore firestore,
    required CrashlyticsService crashlyticsService,
  })  : _firestore = firestore,
        _crashlyticsService = crashlyticsService;

  final FirebaseFirestore _firestore;
  final CrashlyticsService _crashlyticsService;

  Future<void> ensureParentProfile({
    required String parentId,
    required String? phoneNumber,
  }) async {
    try {
      final parentRef = _firestore.collection('parents').doc(parentId);
      await parentRef.set(
        {
          'parentId': parentId,
          'phone': phoneNumber,
          'createdAt': FieldValue.serverTimestamp(),
          'subscription': {
            'tier': 'free',
            'validUntil': null,
            'autoRenew': false,
          },
          'preferences': {
            'language': 'en',
            'timezone': 'Asia/Kolkata',
            'pushNotificationsEnabled': true,
            'weeklySummaryEnabled': true,
            'securityAlertsEnabled': true,
            'activityHistoryEnabled': true,
            'crashReportsEnabled': true,
            'personalizedTipsEnabled': true,
            'biometricLoginEnabled': false,
            'incognitoModeEnabled': false,
            'vpnProtectionEnabled': false,
            'nextDnsEnabled': false,
            'nextDnsProfileId': null,
            'nextDnsApiConnected': false,
            'nextDnsConnectedAt': null,
          },
          'onboardingComplete': false,
          'fcmToken': null,
        },
        SetOptions(merge: true),
      );
    } catch (error, stackTrace) {
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'Failed to ensure parent profile',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getParentProfile(String parentId) async {
    final snapshot = await _firestore.collection('parents').doc(parentId).get();
    return snapshot.data();
  }

  Future<Map<String, dynamic>?> getParentPreferences(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final snapshot = await _firestore.collection('parents').doc(parentId).get();
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();
    final mergedPreferences = <String, dynamic>{};

    final rawPreferences = data?['preferences'];
    if (rawPreferences is Map<String, dynamic>) {
      mergedPreferences.addAll(rawPreferences);
    }
    if (rawPreferences is Map) {
      mergedPreferences.addAll(
        rawPreferences.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    if (data != null) {
      mergedPreferences['onboardingComplete'] =
          data['onboardingComplete'] == true;
      if (data.containsKey('onboardingCompletedAt')) {
        mergedPreferences['onboardingCompletedAt'] =
            data['onboardingCompletedAt'];
      }
    }
    return mergedPreferences.isEmpty ? null : mergedPreferences;
  }

  Future<void> completeOnboarding(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    await _firestore.collection('parents').doc(parentId).set(
      {
        'onboardingComplete': true,
        'onboardingCompletedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> recordGuardianConsent(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    await _firestore.collection('parents').doc(parentId).set(
      <String, dynamic>{
        'consentGiven': true,
        'consentTimestamp': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<bool> isOnboardingComplete(String parentId) async {
    final preferences = await getParentPreferences(parentId);
    return (preferences?['onboardingComplete'] as bool?) == true;
  }

  Future<void> saveFcmToken(String parentId, String token) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'FCM token is required.');
    }

    await _firestore.collection('parents').doc(parentId).set(
      {
        'fcmToken': token.trim(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> removeFcmToken(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    await _firestore.collection('parents').doc(parentId).set(
      <String, dynamic>{'fcmToken': FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  Future<int> revokeChildSessionsForParent(String parentId) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final children = await _firestore
        .collection('children')
        .where('parentId', isEqualTo: normalizedParentId)
        .get();
    if (children.docs.isEmpty) {
      return 0;
    }

    final now = Timestamp.fromDate(DateTime.now());
    var updated = 0;
    var batch = _firestore.batch();
    var pending = 0;

    Future<void> commitBatch() async {
      if (pending == 0) {
        return;
      }
      await batch.commit();
      updated += pending;
      batch = _firestore.batch();
      pending = 0;
    }

    for (final childDoc in children.docs) {
      batch.update(childDoc.reference, <String, dynamic>{
        'parentSessionRevokedAt': now,
        'updatedAt': now,
      });
      pending += 1;
      if (pending >= 400) {
        await commitBatch();
      }
    }
    await commitBatch();
    return updated;
  }
}
