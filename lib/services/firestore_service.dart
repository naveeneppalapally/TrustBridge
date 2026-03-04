import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/config/category_ids.dart';
import 'package:trustbridge_app/config/service_definitions.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/dashboard_state.dart';
import 'package:trustbridge_app/models/installed_app_info.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/support_ticket.dart';
import 'package:trustbridge_app/repositories/alert_repository.dart';
import 'package:trustbridge_app/repositories/auth_repository.dart';
import 'package:trustbridge_app/repositories/child_repository.dart';
import 'package:trustbridge_app/repositories/parent_repository.dart';
import 'package:trustbridge_app/repositories/request_repository.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';
import 'package:trustbridge_app/services/performance_service.dart';

class DeviceStatusSnapshot {
  const DeviceStatusSnapshot({
    required this.deviceId,
    this.lastSeen,
    this.vpnActive = false,
    this.queriesProcessed = 0,
    this.queriesBlocked = 0,
    this.queriesAllowed = 0,
    this.updatedAt,
  });

  final String deviceId;
  final DateTime? lastSeen;
  final bool vpnActive;
  final int queriesProcessed;
  final int queriesBlocked;
  final int queriesAllowed;
  final DateTime? updatedAt;

  factory DeviceStatusSnapshot.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final lastSeen = _readDateTime(data['lastSeen']) ??
        _readEpochDateTime(data['lastSeenEpochMs']) ??
        _readDateTime(data['pairedAt']) ??
        _readDateTime(data['fcmTokenUpdatedAt']);
    return DeviceStatusSnapshot(
      deviceId: snapshot.id,
      lastSeen: lastSeen,
      vpnActive: data['vpnActive'] == true,
      queriesProcessed: _readInt(data['queriesProcessed']),
      queriesBlocked: _readInt(data['queriesBlocked']),
      queriesAllowed: _readInt(data['queriesAllowed']),
      updatedAt: _readDateTime(data['updatedAt']) ??
          _readDateTime(data['pairedAt']) ??
          _readDateTime(data['fcmTokenUpdatedAt']),
    );
  }

  static int _readInt(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return 0;
  }

  static DateTime? _readDateTime(Object? rawValue) {
    if (rawValue is Timestamp) {
      return rawValue.toDate();
    }
    if (rawValue is DateTime) {
      return rawValue;
    }
    return null;
  }

  static DateTime? _readEpochDateTime(Object? rawValue) {
    if (rawValue is int && rawValue > 0) {
      return DateTime.fromMillisecondsSinceEpoch(rawValue);
    }
    if (rawValue is num && rawValue.toInt() > 0) {
      return DateTime.fromMillisecondsSinceEpoch(rawValue.toInt());
    }
    return null;
  }
}

class FirestoreService {
  static const Duration _vpnStateFreshnessWindow = Duration(seconds: 30);

  FirestoreService({
    FirebaseFirestore? firestore,
    NextDnsApiService? nextDnsApiService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _nextDnsApiService = nextDnsApiService ?? NextDnsApiService();

  final FirebaseFirestore _firestore;
  final NextDnsApiService _nextDnsApiService;
  int _lastPolicyEventEpochMs = 0;
  final Map<String, List<ChildProfile>> _childrenCacheByParentId =
      <String, List<ChildProfile>>{};
  final Map<String, ChildProfile> _childCacheByScopedId =
      <String, ChildProfile>{};
  final Map<String, Stream<List<ChildProfile>>> _childrenStreamByParentId =
      <String, Stream<List<ChildProfile>>>{};
  final Map<String, Stream<ChildProfile?>> _childStreamByScopedId =
      <String, Stream<ChildProfile?>>{};

  /// Public accessor for the underlying Firestore instance.
  FirebaseFirestore get firestore => _firestore;
  final CrashlyticsService _crashlyticsService = CrashlyticsService();
  final PerformanceService _performanceService = PerformanceService();
  late final AuthRepository _authRepository = AuthRepository(
    firestore: _firestore,
    crashlyticsService: _crashlyticsService,
  );
  late final ParentRepository _parentRepository =
      ParentRepository(firestore: _firestore);
  late final AlertRepository _alertRepository =
      AlertRepository(firestore: _firestore);
  late final ChildRepository _childRepository =
      ChildRepository(firestore: _firestore);
  late final RequestRepository _requestRepository = RequestRepository(
    firestore: _firestore,
    crashlyticsService: _crashlyticsService,
    nextDnsApiService: _nextDnsApiService,
    parentRepository: _parentRepository,
  );

  String _scopedChildCacheKey({
    required String parentId,
    required String childId,
  }) {
    return '${parentId.trim()}::${childId.trim()}';
  }

  List<ChildProfile> getCachedChildren(String parentId) {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return const <ChildProfile>[];
    }
    final cached = _childrenCacheByParentId[normalizedParentId];
    if (cached == null || cached.isEmpty) {
      return const <ChildProfile>[];
    }
    return List<ChildProfile>.from(cached);
  }

  ChildProfile? getCachedChild({
    required String parentId,
    required String childId,
  }) {
    final key = _scopedChildCacheKey(parentId: parentId, childId: childId);
    return _childCacheByScopedId[key];
  }

  Future<List<ChildProfile>> _childrenFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final children = <ChildProfile>[];
    final hydratedChildren = await Future.wait<ChildProfile?>(
      snapshot.docs.map((doc) async {
        try {
          final child = ChildProfile.fromFirestore(doc);
          return await _mergeEffectivePolicyIntoChild(child);
        } catch (error, stackTrace) {
          developer.log(
            'Skipping malformed child document: ${doc.id}',
            name: 'FirestoreService',
            error: error,
            stackTrace: stackTrace,
          );
          return null;
        }
      }),
    );
    for (final child in hydratedChildren) {
      if (child != null) {
        children.add(child);
      }
    }
    children.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return children;
  }

  Future<ChildProfile> _mergeEffectivePolicyIntoChild(
      ChildProfile child) async {
    final effective = await _loadEffectivePolicyCurrent(child.id);
    if (effective.isEmpty) {
      return child;
    }

    final modeOverrides = _dynamicMap(
      effective['baseModeOverrides'] ?? effective['modeOverridesResolved'],
    );
    final policyMap = <String, dynamic>{
      'blockedCategories': _dynamicStringList(
        effective['baseBlockedCategories'] ?? effective['blockedCategories'],
      ).toList(),
      'blockedServices': _dynamicStringList(
        effective['baseBlockedServices'] ?? effective['blockedServices'],
      ).toList(),
      'blockedDomains': _dynamicStringList(
        effective['baseBlockedDomains'] ?? effective['blockedDomains'],
      ).toList(),
      'blockedPackages': _dynamicStringList(
        effective['baseBlockedPackages'] ?? effective['blockedPackages'],
      ).toList(),
      'modeOverrides': modeOverrides,
      'policySchemaVersion': _dynamicInt(effective['policySchemaVersion']) ??
          child.policy.policySchemaVersion,
      'schedules': _dynamicListOfMaps(
        effective['schedules'],
        fallback: child.policy.schedules.map((schedule) => schedule.toMap()),
      ),
      'safeSearchEnabled': _dynamicBool(
        effective['safeSearchEnabled'],
        fallback: child.policy.safeSearchEnabled,
      ),
    };
    final mergedPolicy = Policy.fromMap(policyMap);

    final hasPausedUntil = effective.containsKey('pausedUntil');
    final mergedPausedUntil = hasPausedUntil
        ? _dynamicDateTime(effective['pausedUntil'])
        : child.pausedUntil;
    final hasManualMode = effective.containsKey('manualMode');
    final mergedManualMode = hasManualMode
        ? (() {
            final manualMode = _dynamicMap(effective['manualMode']);
            return manualMode.isEmpty ? null : manualMode;
          })()
        : child.manualMode;
    final mergedProtectionEnabled = _dynamicBool(
      effective['protectionEnabled'],
      fallback: child.protectionEnabled,
    );

    return ChildProfile(
      id: child.id,
      nickname: child.nickname,
      ageBand: child.ageBand,
      deviceIds: child.deviceIds,
      nextDnsProfileId: child.nextDnsProfileId,
      deviceMetadata: child.deviceMetadata,
      nextDnsControls: child.nextDnsControls,
      policy: mergedPolicy,
      protectionEnabled: mergedProtectionEnabled,
      createdAt: child.createdAt,
      updatedAt: child.updatedAt,
      pausedUntil: mergedPausedUntil,
      manualMode: mergedManualMode,
    );
  }

  Future<Map<String, dynamic>> _loadEffectivePolicyCurrent(
      String childId) async {
    try {
      final snapshot = await _firestore
          .collection('children')
          .doc(childId.trim())
          .collection('effective_policy')
          .doc('current')
          .get();
      return _dynamicMap(snapshot.data());
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _upsertChildrenCache(String parentId, List<ChildProfile> children) {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return;
    }
    final immutable = List<ChildProfile>.unmodifiable(children);
    _childrenCacheByParentId[normalizedParentId] = immutable;
    for (final child in immutable) {
      final key = _scopedChildCacheKey(
        parentId: normalizedParentId,
        childId: child.id,
      );
      _childCacheByScopedId[key] = child;
    }
  }

  void _upsertChildCache({
    required String parentId,
    required ChildProfile child,
  }) {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return;
    }
    final key = _scopedChildCacheKey(
      parentId: normalizedParentId,
      childId: child.id,
    );
    _childCacheByScopedId[key] = child;
    final existing = _childrenCacheByParentId[normalizedParentId];
    if (existing == null) {
      return;
    }
    final next = List<ChildProfile>.from(existing);
    final index = next.indexWhere((value) => value.id == child.id);
    if (index >= 0) {
      next[index] = child;
    } else {
      next.add(child);
      next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    _childrenCacheByParentId[normalizedParentId] =
        List<ChildProfile>.unmodifiable(next);
  }

  void _evictChildCache({
    required String parentId,
    required String childId,
  }) {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty || normalizedChildId.isEmpty) {
      return;
    }

    final scopedKey = _scopedChildCacheKey(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    );
    _childCacheByScopedId.remove(scopedKey);

    final existing = _childrenCacheByParentId[normalizedParentId];
    if (existing == null || existing.isEmpty) {
      return;
    }

    final next = existing
        .where((child) => child.id != normalizedChildId)
        .toList(growable: false);
    _childrenCacheByParentId[normalizedParentId] =
        List<ChildProfile>.unmodifiable(next);
  }

  Future<void> ensureParentProfile({
    required String parentId,
    required String? phoneNumber,
  }) async {
    return _authRepository.ensureParentProfile(
      parentId: parentId,
      phoneNumber: phoneNumber,
    );
  }

  Future<Map<String, dynamic>?> getParentProfile(String parentId) async {
    return _authRepository.getParentProfile(parentId);
  }

  /// One-shot fetch of parent preferences plus onboarding status fields.
  Future<Map<String, dynamic>?> getParentPreferences(String parentId) async {
    return _authRepository.getParentPreferences(parentId);
  }

  /// Mark onboarding as complete for a parent.
  Future<void> completeOnboarding(String parentId) async {
    return _authRepository.completeOnboarding(parentId);
  }

  /// Stores DPDPA guardian consent acknowledgement metadata.
  Future<void> recordGuardianConsent(String parentId) async {
    return _authRepository.recordGuardianConsent(parentId);
  }

  /// Check if onboarding is complete for a parent.
  Future<bool> isOnboardingComplete(String parentId) async {
    return _authRepository.isOnboardingComplete(parentId);
  }

  /// Save parent's FCM token for push notifications.
  Future<void> saveFcmToken(String parentId, String token) async {
    return _authRepository.saveFcmToken(parentId, token);
  }

  /// Remove parent's FCM token on logout or account switch.
  Future<void> removeFcmToken(String parentId) async {
    return _authRepository.removeFcmToken(parentId);
  }

  /// Marks all linked child sessions as revoked for the signing-out parent.
  ///
  /// Child devices listen to their profile and will self-unpair when this
  /// marker is updated.
  Future<int> revokeChildSessionsForParent(String parentId) async {
    return _authRepository.revokeChildSessionsForParent(parentId);
  }

  /// Queue a parent push notification payload for backend processing.
  Future<void> queueParentNotification({
    required String parentId,
    required String title,
    required String body,
    required String route,
  }) async {
    return _parentRepository.queueParentNotification(
      parentId: parentId,
      title: title,
      body: body,
      route: route,
    );
  }

  /// Queue a child push notification payload for backend processing.
  Future<void> queueChildNotification({
    required String parentId,
    required String childId,
    required String title,
    required String body,
    String route = '/child/status',
    String eventType = 'access_request_response',
  }) async {
    return _parentRepository.queueChildNotification(
      parentId: parentId,
      childId: childId,
      title: title,
      body: body,
      route: route,
      eventType: eventType,
    );
  }

  Stream<Map<String, dynamic>?> watchParentProfile(String parentId) {
    return _parentRepository.watchParentProfile(parentId);
  }

  Stream<DashboardStateSnapshot?> watchDashboardState(String parentId) {
    return _parentRepository.watchDashboardState(parentId);
  }

  Future<void> updateParentSecurityMetadata({
    required String parentId,
    DateTime? appPinChangedAt,
    int? activeSessions,
    bool? twoFactorEnabled,
  }) async {
    return _parentRepository.updateParentSecurityMetadata(
      parentId: parentId,
      appPinChangedAt: appPinChangedAt,
      activeSessions: activeSessions,
      twoFactorEnabled: twoFactorEnabled,
    );
  }

  Future<void> updateParentPreferences({
    required String parentId,
    String? language,
    String? timezone,
    bool? pushNotificationsEnabled,
    bool? weeklySummaryEnabled,
    bool? securityAlertsEnabled,
    bool? activityHistoryEnabled,
    bool? crashReportsEnabled,
    bool? personalizedTipsEnabled,
    bool? biometricLoginEnabled,
    bool? incognitoModeEnabled,
    bool? vpnProtectionEnabled,
    bool? nextDnsEnabled,
    String? nextDnsProfileId,
    bool? nextDnsApiConnected,
    DateTime? nextDnsConnectedAt,
  }) async {
    return _parentRepository.updateParentPreferences(
      parentId: parentId,
      language: language,
      timezone: timezone,
      pushNotificationsEnabled: pushNotificationsEnabled,
      weeklySummaryEnabled: weeklySummaryEnabled,
      securityAlertsEnabled: securityAlertsEnabled,
      activityHistoryEnabled: activityHistoryEnabled,
      crashReportsEnabled: crashReportsEnabled,
      personalizedTipsEnabled: personalizedTipsEnabled,
      biometricLoginEnabled: biometricLoginEnabled,
      incognitoModeEnabled: incognitoModeEnabled,
      vpnProtectionEnabled: vpnProtectionEnabled,
      nextDnsEnabled: nextDnsEnabled,
      nextDnsProfileId: nextDnsProfileId,
      nextDnsApiConnected: nextDnsApiConnected,
      nextDnsConnectedAt: nextDnsConnectedAt,
    );
  }

  /// Updates parent alert preferences used by protection/bypass notifications.
  Future<void> updateAlertPreferences({
    required String parentId,
    bool? vpnDisabled,
    bool? uninstallAttempt,
    bool? privateDnsChanged,
    bool? deviceOffline30m,
    bool? deviceOffline24h,
    bool? emailSeriousAlerts,
  }) async {
    return _parentRepository.updateAlertPreferences(
      parentId: parentId,
      vpnDisabled: vpnDisabled,
      uninstallAttempt: uninstallAttempt,
      privateDnsChanged: privateDnsChanged,
      deviceOffline30m: deviceOffline30m,
      deviceOffline24h: deviceOffline24h,
      emailSeriousAlerts: emailSeriousAlerts,
    );
  }

  /// Returns alert preferences map for the parent account.
  Future<Map<String, dynamic>> getAlertPreferences(String parentId) async {
    return _parentRepository.getAlertPreferences(parentId);
  }

  /// Logs a 24h offline bypass event for a child device and queues parent alert.
  ///
  /// This method is idempotent within a 24-hour window per device.
  Future<void> logDeviceOffline24hAlert({
    required String parentId,
    required String childId,
    required String childNickname,
    required String deviceId,
  }) async {
    return _parentRepository.logDeviceOffline24hAlert(
      parentId: parentId,
      childId: childId,
      childNickname: childNickname,
      deviceId: deviceId,
    );
  }

  Future<String> createSupportTicket({
    required String parentId,
    required String subject,
    required String message,
    String? childId,
  }) async {
    return _parentRepository.createSupportTicket(
      parentId: parentId,
      subject: subject,
      message: message,
      childId: childId,
    );
  }

  Stream<List<SupportTicket>> getSupportTicketsStream(
    String parentId, {
    int limit = 50,
  }) {
    return _parentRepository.getSupportTicketsStream(parentId, limit: limit);
  }

  /// Returns duplicate-ticket analytics summary for roadmap planning.
  Future<Map<String, dynamic>> getDuplicateAnalytics(String parentId) async {
    return _parentRepository.getDuplicateAnalytics(parentId);
  }

  /// Exports top duplicate clusters as CSV text.
  Future<String> exportDuplicateClustersCSV(String parentId) async {
    return _parentRepository.exportDuplicateClustersCSV(parentId);
  }

  /// Returns unresolved duplicate count for a normalized duplicate key.
  Future<int> getDuplicateClusterSize({
    required String parentId,
    required String duplicateKey,
  }) async {
    return _parentRepository.getDuplicateClusterSize(
      parentId: parentId,
      duplicateKey: duplicateKey,
    );
  }

  /// Resolves all unresolved tickets in a duplicate cluster.
  Future<int> bulkResolveDuplicates({
    required String parentId,
    required String duplicateKey,
  }) async {
    return _parentRepository.bulkResolveDuplicates(
      parentId: parentId,
      duplicateKey: duplicateKey,
    );
  }

  /// Reopens recently resolved tickets in a duplicate cluster.
  Future<int> bulkReopenDuplicates({
    required String parentId,
    required String duplicateKey,
    int limit = 50,
  }) async {
    return _parentRepository.bulkReopenDuplicates(
      parentId: parentId,
      duplicateKey: duplicateKey,
      limit: limit,
    );
  }

  Future<String> submitBetaFeedback({
    required String parentId,
    required String category,
    required String severity,
    required String title,
    required String details,
    String? childId,
  }) async {
    return _parentRepository.submitBetaFeedback(
      parentId: parentId,
      category: category,
      severity: severity,
      title: title,
      details: details,
      childId: childId,
    );
  }

  Future<ChildProfile> addChild({
    required String parentId,
    required String nickname,
    required AgeBand ageBand,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final normalizedNickname = nickname.trim();
    if (normalizedNickname.isEmpty) {
      throw ArgumentError.value(
        nickname,
        'nickname',
        'Nickname cannot be empty.',
      );
    }

    final child = ChildProfile.create(
      nickname: normalizedNickname,
      ageBand: ageBand,
    );

    try {
      await _childRepository.createChildProfile(
        parentId: parentId,
        child: child,
      );
      await _recordPolicyEventSnapshot(
        parentId: parentId,
        childId: child.id,
        blockedCategories: child.policy.blockedCategories,
        blockedServices: child.policy.blockedServices,
        blockedDomains: child.policy.blockedDomains,
        blockedPackages: child.policy.blockedPackages,
        modeOverrides: child.policy.modeOverrides.map(
          (modeName, overrideSet) => MapEntry(modeName, overrideSet.toMap()),
        ),
        manualMode: null,
        pausedUntil: null,
        protectionEnabled: child.protectionEnabled,
        sourceUpdatedAt: child.updatedAt,
        policySchemaVersion: child.policy.policySchemaVersion,
        schedules: child.policy.schedules.map((schedule) => schedule.toMap()),
        safeSearchEnabled: child.policy.safeSearchEnabled,
      );
      _upsertChildCache(parentId: parentId, child: child);
      await _crashlyticsService.setCustomKeys({
        'last_child_id': child.id,
        'last_child_age_band': ageBand.value,
      });
    } catch (error, stackTrace) {
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'Failed to add child profile',
      );
      rethrow;
    }

    return child;
  }

  Stream<List<ChildProfile>> getChildrenStream(String parentId) {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    return _childrenStreamByParentId.putIfAbsent(normalizedParentId, () {
      return _childRepository
          .watchChildrenByParent(normalizedParentId)
          .asyncMap((snapshot) async {
        final children = await _childrenFromSnapshot(snapshot);
        _upsertChildrenCache(normalizedParentId, children);
        return children;
      }).asBroadcastStream();
    });
  }

  Future<void> updateParentContactInfo({
    required String parentId,
    String? email,
    String? displayName,
  }) async {
    await _parentRepository.updateParentContactInfo(
      parentId: parentId,
      email: email,
      displayName: displayName,
    );
  }

  Future<List<ChildProfile>> getChildren(String parentId) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final snapshot = await _childRepository.getChildrenDocsByParent(
      normalizedParentId,
    );
    final children = await _childrenFromSnapshot(snapshot);
    _upsertChildrenCache(normalizedParentId, children);
    return children;
  }

  /// Returns true when the parent has at least one child profile.
  Future<bool> hasAnyChildProfiles(String parentId) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final cachedChildren = _childrenCacheByParentId[normalizedParentId];
    if (cachedChildren != null && cachedChildren.isNotEmpty) {
      return true;
    }

    final snapshot = await _childRepository.getChildrenDocsByParent(
      normalizedParentId,
      limit: 1,
    );
    return snapshot.docs.isNotEmpty;
  }

  /// One-shot fetch of all children without subscribing to stream updates.
  Future<List<ChildProfile>> getChildrenOnce(String parentId) {
    return _performanceService.traceOperation<List<ChildProfile>>(
      'firestore_get_children',
      () => getChildren(parentId),
      warningThresholdMs: PerformanceThresholds.firestoreGetChildrenWarningMs,
      thresholdMetricName: 'firestore_get_children_ms',
      onSuccess: (PerformanceTrace trace, List<ChildProfile> children) async {
        await _performanceService.setMetric(
          trace,
          'children_count',
          children.length,
        );
        await _performanceService.setMetric(trace, 'query_success', 1);
      },
      onError: (
        PerformanceTrace trace,
        Object error,
        StackTrace stackTrace,
      ) async {
        await _performanceService.setMetric(trace, 'query_success', 0);
      },
    );
  }

  Future<ChildProfile?> getChild({
    required String parentId,
    required String childId,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final snapshot = await _childRepository.getChildDoc(childId);
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();
    if (data == null || data['parentId'] != parentId) {
      return null;
    }
    final child = await _mergeEffectivePolicyIntoChild(
      ChildProfile.fromFirestore(snapshot),
    );
    _upsertChildCache(parentId: parentId, child: child);
    return child;
  }

  Stream<ChildProfile?> getChildStream({
    required String parentId,
    required String childId,
  }) {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (normalizedChildId.isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final key = _scopedChildCacheKey(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    );
    return _childStreamByScopedId.putIfAbsent(key, () {
      return _childRepository
          .watchChildDoc(
            normalizedChildId,
            includeMetadataChanges: true,
          )
          .asyncMap((snapshot) async {
        if (!snapshot.exists) {
          _childCacheByScopedId.remove(key);
          return null;
        }
        final data = snapshot.data() ?? const <String, dynamic>{};
        final ownerParentId = (data['parentId'] as String?)?.trim();
        if (ownerParentId == null || ownerParentId != normalizedParentId) {
          return null;
        }
        final child = await _mergeEffectivePolicyIntoChild(
          ChildProfile.fromFirestore(snapshot),
        );
        _upsertChildCache(parentId: normalizedParentId, child: child);
        return child;
      }).asBroadcastStream();
    });
  }

  Future<List<InstalledAppInfo>> getChildInstalledAppsOnce({
    required String parentId,
    required String childId,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final childDoc = await _childRepository.loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    if (!childDoc.exists) {
      return const <InstalledAppInfo>[];
    }

    final inventoryDoc = await _childRepository.getChildInventoryDoc(
      parentId: parentId,
      childId: childId,
    );
    return _installedAppsFromSnapshot(inventoryDoc.data());
  }

  Stream<List<InstalledAppInfo>> watchChildInstalledApps({
    required String parentId,
    required String childId,
  }) {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    return _childRepository
        .watchChildInventoryDoc(childId.trim())
        .asyncMap((snapshot) async {
      if (!snapshot.exists) {
        return const <InstalledAppInfo>[];
      }
      final childSnapshot = await _childRepository.getChildDoc(childId.trim());
      final childData = childSnapshot.data() ?? const <String, dynamic>{};
      final ownerParentId = (childData['parentId'] as String?)?.trim();
      if (ownerParentId == null || ownerParentId != parentId.trim()) {
        return const <InstalledAppInfo>[];
      }
      return _installedAppsFromSnapshot(snapshot.data());
    });
  }

  Future<Map<String, List<String>>> getChildObservedAppDomainsOnce({
    required String parentId,
    required String childId,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final childDoc = await _childRepository.loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    if (!childDoc.exists) {
      return const <String, List<String>>{};
    }

    final usageDoc = await _childRepository.getChildAppDomainUsageDoc(
      parentId: parentId,
      childId: childId,
    );
    return _observedAppDomainsFromSnapshot(usageDoc.data());
  }

  List<InstalledAppInfo> _installedAppsFromSnapshot(
      Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return const <InstalledAppInfo>[];
    }
    final rawApps = data['apps'];
    if (rawApps is! List) {
      return const <InstalledAppInfo>[];
    }
    final apps = <InstalledAppInfo>[];
    for (final raw in rawApps) {
      final appMap = _dynamicMap(raw);
      if (appMap.isEmpty) {
        continue;
      }
      final packageName = (appMap['packageName'] as String?)?.trim();
      if (packageName == null || packageName.isEmpty) {
        continue;
      }
      final firstSeenAt = _dynamicDateTime(appMap['firstSeenAt']) ??
          _dynamicDateTime(appMap['firstSeenAtEpochMs']);
      final lastSeenAt = _dynamicDateTime(appMap['lastSeenAt']) ??
          _dynamicDateTime(appMap['lastSeenAtEpochMs']);
      final app = InstalledAppInfo(
        packageName: packageName.toLowerCase(),
        appName: (appMap['appName'] as String?)?.trim() ?? packageName,
        appIconBase64: (appMap['appIconBase64'] as String?)?.trim(),
        isSystemApp: appMap['isSystemApp'] == true,
        isLaunchable: appMap['isLaunchable'] != false,
        firstSeenAt: firstSeenAt,
        lastSeenAt: lastSeenAt,
      );
      if (!app.isValid) {
        continue;
      }
      apps.add(app);
    }
    apps.sort(
      (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
    );
    return apps;
  }

  Map<String, List<String>> _observedAppDomainsFromSnapshot(
    Map<String, dynamic>? data,
  ) {
    if (data == null || data.isEmpty) {
      return const <String, List<String>>{};
    }
    final result = <String, List<String>>{};
    final packageDomainsRaw = data['packageDomains'];
    if (packageDomainsRaw is Map) {
      packageDomainsRaw.forEach((key, value) {
        final packageName = key.toString().trim().toLowerCase();
        if (packageName.isEmpty) {
          return;
        }
        final domains = _dynamicStringList(value)
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (domains.isNotEmpty) {
          result[packageName] = domains;
        }
      });
    }
    final packagesRaw = data['packages'];
    if (packagesRaw is List) {
      for (final raw in packagesRaw) {
        final packageMap = _dynamicMap(raw);
        if (packageMap.isEmpty) {
          continue;
        }
        final packageName =
            (packageMap['packageName'] as String?)?.trim().toLowerCase();
        if (packageName == null || packageName.isEmpty) {
          continue;
        }
        final domains = _dynamicStringList(packageMap['domains'])
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (domains.isEmpty) {
          continue;
        }
        final existing = result[packageName] ?? const <String>[];
        result[packageName] = <String>{...existing, ...domains}.toList()
          ..sort();
      }
    }
    return result;
  }

  /// Streams latest heartbeat timestamps for a set of device IDs.
  ///
  /// Firestore `whereIn` supports at most 10 IDs; extra IDs are ignored and
  /// should be handled separately by callers.
  Stream<Map<String, DeviceStatusSnapshot>> watchDeviceStatuses(
    List<String> deviceIds, {
    String? parentId,
    Map<String, String>? childIdByDeviceId,
  }) {
    final uniqueDeviceIds = deviceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (uniqueDeviceIds.isEmpty) {
      return Stream<Map<String, DeviceStatusSnapshot>>.value(
        const <String, DeviceStatusSnapshot>{},
      );
    }

    final queryIds = uniqueDeviceIds.length > 10
        ? uniqueDeviceIds.take(10).toList(growable: false)
        : uniqueDeviceIds;

    final normalizedParentId = parentId?.trim();
    Query<Map<String, dynamic>> rootQuery = _firestore.collection('devices');
    final hasParentScope =
        normalizedParentId != null && normalizedParentId.isNotEmpty;
    if (hasParentScope) {
      // Do not combine parent scope with __name__ in-filter. If any stale or
      // unauthorized ID is present in queryIds, Firestore rejects the whole
      // listen. Parent-scoped query remains rule-safe and we filter client-side.
      rootQuery = rootQuery.where('parentId', isEqualTo: normalizedParentId);
    } else {
      rootQuery = rootQuery.where(FieldPath.documentId, whereIn: queryIds);
    }
    final childDeviceQuery = _firestore
        .collectionGroup('devices')
        .where(FieldPath.documentId, whereIn: queryIds);

    return Stream<Map<String, DeviceStatusSnapshot>>.multi((controller) {
      var rootStatusByDeviceId = <String, DeviceStatusSnapshot>{};
      var childStatusByDeviceId = <String, DeviceStatusSnapshot>{};

      final normalizedChildDeviceMap = <String, String>{};
      if (childIdByDeviceId != null) {
        for (final entry in childIdByDeviceId.entries) {
          final deviceId = entry.key.trim();
          final childId = entry.value.trim();
          if (deviceId.isEmpty ||
              childId.isEmpty ||
              !uniqueDeviceIds.contains(deviceId)) {
            continue;
          }
          normalizedChildDeviceMap[deviceId] = childId;
        }
      }

      void emitMerged() {
        final merged = <String, DeviceStatusSnapshot>{};
        final allDeviceIds = <String>{
          ...childStatusByDeviceId.keys,
          ...rootStatusByDeviceId.keys,
        };
        for (final deviceId in allDeviceIds) {
          final childSnapshot = childStatusByDeviceId[deviceId];
          final rootSnapshot = rootStatusByDeviceId[deviceId];
          final mergedSnapshot = _mergeStatusSnapshots(
            deviceId: deviceId,
            childSnapshot: childSnapshot,
            rootSnapshot: rootSnapshot,
          );
          if (mergedSnapshot != null) {
            merged[deviceId] = mergedSnapshot;
          }
        }
        controller.add(merged);
      }

      final rootSub = rootQuery.snapshots().listen(
        (snapshot) {
          final next = <String, DeviceStatusSnapshot>{};
          for (final doc in snapshot.docs) {
            if (!uniqueDeviceIds.contains(doc.id)) {
              continue;
            }
            next[doc.id] = DeviceStatusSnapshot.fromFirestore(doc);
          }
          rootStatusByDeviceId = next;
          emitMerged();
        },
        onError: (_, __) {
          // Root query can be denied by stricter rulesets; child-device
          // fallbacks still provide presence data.
          rootStatusByDeviceId = <String, DeviceStatusSnapshot>{};
          emitMerged();
        },
      );

      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? childSub;
      final childDocSubs =
          <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];

      if (normalizedChildDeviceMap.isNotEmpty) {
        for (final entry in normalizedChildDeviceMap.entries) {
          final childId = entry.value;
          final deviceId = entry.key;
          final sub = _firestore
              .collection('children')
              .doc(childId)
              .collection('devices')
              .doc(deviceId)
              .snapshots()
              .listen(
            (snapshot) {
              final next = <String, DeviceStatusSnapshot>{
                ...childStatusByDeviceId,
              };
              if (snapshot.exists) {
                next[deviceId] = DeviceStatusSnapshot.fromFirestore(snapshot);
              } else {
                next.remove(deviceId);
              }
              childStatusByDeviceId = next;
              emitMerged();
            },
            onError: (_, __) {
              final next = <String, DeviceStatusSnapshot>{
                ...childStatusByDeviceId,
              };
              next.remove(deviceId);
              childStatusByDeviceId = next;
              emitMerged();
            },
          );
          childDocSubs.add(sub);
        }
      } else {
        childSub = childDeviceQuery.snapshots().listen(
          (snapshot) {
            final next = <String, DeviceStatusSnapshot>{};
            for (final doc in snapshot.docs) {
              final candidate = DeviceStatusSnapshot.fromFirestore(doc);
              final existing = next[doc.id];
              if (_isNewerStatusSnapshot(candidate, existing)) {
                next[doc.id] = candidate;
              }
            }
            childStatusByDeviceId = next;
            emitMerged();
          },
          onError: (_, __) {
            // Child-device fallback is best effort; root stream can still drive
            // status in environments where collectionGroup access is restricted.
          },
        );
      }

      controller.onCancel = () async {
        await rootSub.cancel();
        if (childSub != null) {
          await childSub.cancel();
        }
        for (final sub in childDocSubs) {
          await sub.cancel();
        }
      };
    });
  }

  /// One-shot snapshot of merged device statuses used for lightweight
  /// hydration paths (for example, parent fallback UI after relogin).
  Future<Map<String, DeviceStatusSnapshot>> getDeviceStatusesOnce(
    List<String> deviceIds, {
    String? parentId,
    Map<String, String>? childIdByDeviceId,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      return await watchDeviceStatuses(
        deviceIds,
        parentId: parentId,
        childIdByDeviceId: childIdByDeviceId,
      ).first.timeout(
            timeout,
            onTimeout: () => const <String, DeviceStatusSnapshot>{},
          );
    } catch (_) {
      return const <String, DeviceStatusSnapshot>{};
    }
  }

  bool _isNewerStatusSnapshot(
    DeviceStatusSnapshot candidate,
    DeviceStatusSnapshot? existing,
  ) {
    if (existing == null) {
      return true;
    }

    final candidateSeen = candidate.lastSeen ?? candidate.updatedAt;
    final existingSeen = existing.lastSeen ?? existing.updatedAt;

    if (candidateSeen == null) {
      return false;
    }
    if (existingSeen == null) {
      return true;
    }
    return candidateSeen.isAfter(existingSeen);
  }

  DeviceStatusSnapshot? _mergeStatusSnapshots({
    required String deviceId,
    required DeviceStatusSnapshot? childSnapshot,
    required DeviceStatusSnapshot? rootSnapshot,
  }) {
    if (childSnapshot == null) {
      return rootSnapshot;
    }
    if (rootSnapshot == null) {
      return childSnapshot;
    }

    final childSeen = _snapshotSeenAt(childSnapshot);
    final rootSeen = _snapshotSeenAt(rootSnapshot);
    final freshestSeen = _maxDateTime(childSeen, rootSeen);
    final freshestUpdated = _maxDateTime(
      childSnapshot.updatedAt,
      rootSnapshot.updatedAt,
    );
    final preferred = _isNewerStatusSnapshot(rootSnapshot, childSnapshot)
        ? rootSnapshot
        : childSnapshot;

    final childRecent = _isSnapshotRecent(
      snapshotSeenAt: childSeen,
      freshestSeenAt: freshestSeen,
    );
    final rootRecent = _isSnapshotRecent(
      snapshotSeenAt: rootSeen,
      freshestSeenAt: freshestSeen,
    );

    // Combine root + child status paths so transient write races do not flip
    // "Protected" to "Not protected" while one stream is still catching up.
    final mergedVpnActive = (childRecent && childSnapshot.vpnActive) ||
        (rootRecent && rootSnapshot.vpnActive) ||
        ((!childRecent && !rootRecent) &&
            ((_isNewerStatusSnapshot(rootSnapshot, childSnapshot) &&
                    rootSnapshot.vpnActive) ||
                (!_isNewerStatusSnapshot(rootSnapshot, childSnapshot) &&
                    childSnapshot.vpnActive)));

    return DeviceStatusSnapshot(
      deviceId: deviceId,
      lastSeen: freshestSeen,
      vpnActive: mergedVpnActive,
      queriesProcessed: preferred.queriesProcessed,
      queriesBlocked: preferred.queriesBlocked,
      queriesAllowed: preferred.queriesAllowed,
      updatedAt: freshestUpdated,
    );
  }

  DateTime? _snapshotSeenAt(DeviceStatusSnapshot snapshot) {
    return snapshot.lastSeen ?? snapshot.updatedAt;
  }

  bool _isSnapshotRecent({
    required DateTime? snapshotSeenAt,
    required DateTime? freshestSeenAt,
  }) {
    if (snapshotSeenAt == null || freshestSeenAt == null) {
      return false;
    }
    return freshestSeenAt.difference(snapshotSeenAt) <=
        _vpnStateFreshnessWindow;
  }

  DateTime? _maxDateTime(DateTime? left, DateTime? right) {
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    return left.isAfter(right) ? left : right;
  }

  /// Streams latest heartbeat timestamps for a set of device IDs.
  ///
  /// Firestore `whereIn` supports at most 10 IDs; extra IDs are ignored and
  /// should be handled separately by callers.
  Stream<Map<String, DateTime?>> watchDeviceHeartbeats(
    List<String> deviceIds, {
    String? parentId,
  }) {
    return watchDeviceStatuses(deviceIds, parentId: parentId).map((
      statusByDeviceId,
    ) {
      final heartbeatByDeviceId = <String, DateTime?>{};
      for (final entry in statusByDeviceId.entries) {
        heartbeatByDeviceId[entry.key] = entry.value.lastSeen;
      }
      return heartbeatByDeviceId;
    });
  }

  Future<void> setChildNextDnsProfileId({
    required String parentId,
    required String childId,
    required String profileId,
  }) async {
    await _childRepository.setChildNextDnsProfileId(
      parentId: parentId,
      childId: childId,
      profileId: profileId,
    );
  }

  Future<int> migrateChildrenWithoutNextDnsProfiles(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final children = await getChildren(parentId);
    if (children.isEmpty) {
      return 0;
    }

    final existingProfiles = await _nextDnsApiService.fetchProfiles();
    final profilesByName = <String, NextDnsProfileSummary>{};
    for (final profile in existingProfiles) {
      final key = profile.name.trim().toLowerCase();
      if (key.isNotEmpty) {
        profilesByName[key] = profile;
      }
    }

    var migratedCount = 0;
    for (final child in children) {
      final existingProfileId = child.nextDnsProfileId?.trim();
      if (existingProfileId != null && existingProfileId.isNotEmpty) {
        continue;
      }

      final nicknameKey = child.nickname.trim().toLowerCase();
      NextDnsProfileSummary profile;
      if (profilesByName.containsKey(nicknameKey)) {
        profile = profilesByName[nicknameKey]!;
      } else {
        profile = await _nextDnsApiService.createProfile(name: child.nickname);
        profilesByName[nicknameKey] = profile;
      }

      await setChildNextDnsProfileId(
        parentId: parentId,
        childId: child.id,
        profileId: profile.id,
      );
      migratedCount += 1;
    }

    return migratedCount;
  }

  Future<void> saveChildNextDnsControls({
    required String parentId,
    required String childId,
    required Map<String, dynamic> controls,
  }) async {
    await _childRepository.saveChildNextDnsControls(
      parentId: parentId,
      childId: childId,
      controls: controls,
    );
  }

  Future<void> upsertChildDeviceMetadata({
    required String parentId,
    required String childId,
    required String deviceId,
    required String alias,
    String? model,
    String? manufacturer,
    String? linkedNextDnsProfileId,
  }) async {
    await _childRepository.upsertChildDeviceMetadata(
      parentId: parentId,
      childId: childId,
      deviceId: deviceId,
      alias: alias,
      model: model,
      manufacturer: manufacturer,
      linkedNextDnsProfileId: linkedNextDnsProfileId,
    );
  }

  Future<void> verifyChildDevice({
    required String parentId,
    required String childId,
    required String deviceId,
  }) async {
    await _childRepository.verifyChildDevice(
      parentId: parentId,
      childId: childId,
      deviceId: deviceId,
    );
  }

  Future<void> removeChildDevice({
    required String parentId,
    required String childId,
    required String deviceId,
  }) async {
    await _childRepository.removeChildDevice(
      parentId: parentId,
      childId: childId,
      deviceId: deviceId,
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadOwnedChildDoc({
    required String parentId,
    required String childId,
  }) async {
    return _childRepository.loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
  }

  Future<void> updateChild({
    required String parentId,
    required ChildProfile child,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (child.id.trim().isEmpty) {
      throw ArgumentError.value(child.id, 'child.id', 'Child ID is required.');
    }

    final normalizedNickname = child.nickname.trim();
    if (normalizedNickname.isEmpty) {
      throw ArgumentError.value(
        child.nickname,
        'child.nickname',
        'Nickname cannot be empty.',
      );
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: child.id,
    );
    final childData = childDoc.data() ?? const <String, dynamic>{};
    final existingManualMode = _dynamicMap(childData['manualMode']);
    final normalizedPolicy = child.policy.copyWith(
      blockedCategories: normalizeCategoryIds(child.policy.blockedCategories),
      blockedServices: _normalizeServiceIds(child.policy.blockedServices),
      blockedPackages: _normalizePackageIds(child.policy.blockedPackages),
      modeOverrides: _normalizeModeOverridesModel(child.policy.modeOverrides),
      policySchemaVersion: child.policy.policySchemaVersion <= 0
          ? 2
          : child.policy.policySchemaVersion,
    );
    final updatedAt = DateTime.now();
    final childRef = childDoc.reference;
    await childRef.update({
      'nickname': normalizedNickname,
      'ageBand': child.ageBand.value,
      'deviceIds': child.deviceIds,
      'nextDnsProfileId': child.nextDnsProfileId,
      'deviceMetadata': child.deviceMetadata.map(
        (deviceId, metadata) => MapEntry(deviceId, metadata.toMap()),
      ),
      'nextDnsControls': child.nextDnsControls,
      'policy': FieldValue.delete(),
      'protectionEnabled': child.protectionEnabled,
      'pausedUntil': child.pausedUntil != null
          ? Timestamp.fromDate(child.pausedUntil!)
          : null,
      'updatedAt': Timestamp.fromDate(updatedAt),
    });
    await _recordPolicyEventSnapshot(
      parentId: parentId,
      childId: child.id,
      blockedCategories: normalizedPolicy.blockedCategories,
      blockedServices: normalizedPolicy.blockedServices,
      blockedDomains: normalizedPolicy.blockedDomains,
      blockedPackages: normalizedPolicy.blockedPackages,
      modeOverrides: normalizedPolicy.modeOverrides.map(
        (modeName, overrideSet) => MapEntry(modeName, overrideSet.toMap()),
      ),
      manualMode: existingManualMode.isEmpty ? null : existingManualMode,
      pausedUntil: child.pausedUntil,
      protectionEnabled: child.protectionEnabled,
      sourceUpdatedAt: updatedAt,
      policySchemaVersion: normalizedPolicy.policySchemaVersion,
      schedules: normalizedPolicy.schedules.map((schedule) => schedule.toMap()),
      safeSearchEnabled: normalizedPolicy.safeSearchEnabled,
    );
    _upsertChildCache(
      parentId: parentId,
      child: child.copyWith(
        policy: normalizedPolicy,
      ),
    );
  }

  Future<void> appendParentDebugEvent({
    required String parentId,
    required String childId,
    required String eventType,
    required String screen,
    Map<String, dynamic>? payload,
    DateTime? clientTime,
  }) async {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    final normalizedEventType = eventType.trim();
    final normalizedScreen = screen.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (normalizedChildId.isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }
    if (normalizedEventType.isEmpty) {
      throw ArgumentError.value(
        eventType,
        'eventType',
        'Event type is required.',
      );
    }
    if (normalizedScreen.isEmpty) {
      throw ArgumentError.value(screen, 'screen', 'Screen is required.');
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    );
    final normalizedPayload = <String, dynamic>{};
    (payload ?? const <String, dynamic>{}).forEach((key, value) {
      final normalizedKey = key.trim();
      if (normalizedKey.isEmpty) {
        return;
      }
      normalizedPayload[normalizedKey] = value;
    });

    await childDoc.reference.collection('parent_debug_events').add(
      <String, dynamic>{
        'parentId': normalizedParentId,
        'childId': normalizedChildId,
        'source': 'parent_app',
        'screen': normalizedScreen,
        'eventType': normalizedEventType,
        'payload': normalizedPayload,
        'clientTime': Timestamp.fromDate(clientTime ?? DateTime.now()),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<int?> getEffectivePolicyCurrentVersion({
    required String parentId,
    required String childId,
  }) async {
    return _childRepository.getEffectivePolicyCurrentVersion(
      parentId: parentId,
      childId: childId,
    );
  }

  Future<void> deleteChild({
    required String parentId,
    required String childId,
  }) async {
    final deleted = await _childRepository.deleteChildAndQueueUnpairCommands(
      parentId: parentId,
      childId: childId,
    );
    if (deleted) {
      _evictChildCache(parentId: parentId, childId: childId);
    }
  }

  Future<Map<String, dynamic>> _loadPolicySnapshotForChild({
    required String childId,
    required Map<String, dynamic> fallbackChildData,
  }) async {
    final effectivePolicy = await _loadEffectivePolicyCurrent(childId);
    if (effectivePolicy.isNotEmpty) {
      return <String, dynamic>{
        'blockedCategories': _dynamicStringList(
          effectivePolicy['baseBlockedCategories'] ??
              effectivePolicy['blockedCategories'],
        ).toList(),
        'blockedServices': _dynamicStringList(
          effectivePolicy['baseBlockedServices'] ??
              effectivePolicy['blockedServices'],
        ).toList(),
        'blockedDomains': _dynamicStringList(
          effectivePolicy['baseBlockedDomains'] ??
              effectivePolicy['blockedDomains'],
        ).toList(),
        'blockedPackages': _dynamicStringList(
          effectivePolicy['baseBlockedPackages'] ??
              effectivePolicy['blockedPackages'],
        ).toList(),
        'modeOverrides': _dynamicMap(
          effectivePolicy['baseModeOverrides'] ??
              effectivePolicy['modeOverridesResolved'],
        ),
        'policySchemaVersion':
            _dynamicInt(effectivePolicy['policySchemaVersion']) ?? 1,
        'schedules': _dynamicListOfMaps(effectivePolicy['schedules']),
        'safeSearchEnabled': _dynamicBool(
          effectivePolicy['safeSearchEnabled'],
          fallback: true,
        ),
      };
    }
    return _dynamicMap(fallbackChildData['policy']);
  }

  Future<void> pauseAllChildren(
    String parentId, {
    Duration duration = const Duration(hours: 8),
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (duration.inMinutes <= 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Pause duration must be greater than zero.',
      );
    }

    final snapshot = await _firestore
        .collection('children')
        .where('parentId', isEqualTo: parentId)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final pausedUntil = DateTime.now().add(duration);
    final updatedAt = DateTime.now();
    final batch = _firestore.batch();
    final childrenForEvents = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snapshot.docs) {
      childrenForEvents.add(doc);
      batch.update(doc.reference, <String, dynamic>{
        'pausedUntil': Timestamp.fromDate(pausedUntil),
        'updatedAt': Timestamp.fromDate(updatedAt),
      });
    }
    await batch.commit();

    for (final doc in childrenForEvents) {
      final data = doc.data() ?? const <String, dynamic>{};
      final policy = await _loadPolicySnapshotForChild(
        childId: doc.id,
        fallbackChildData: data,
      );
      final manualMode = _dynamicMap(data['manualMode']);
      final protectionEnabled = data['protectionEnabled'] != false;
      await _recordPolicyEventSnapshot(
        parentId: parentId,
        childId: doc.id,
        blockedCategories: _dynamicStringList(policy['blockedCategories']),
        blockedServices: _dynamicStringList(policy['blockedServices']),
        blockedDomains: _dynamicStringList(policy['blockedDomains']),
        blockedPackages: _dynamicStringList(policy['blockedPackages']),
        modeOverrides: _dynamicMap(policy['modeOverrides']),
        manualMode: manualMode.isEmpty ? null : manualMode,
        pausedUntil: pausedUntil,
        protectionEnabled: protectionEnabled,
        sourceUpdatedAt: updatedAt,
        policySchemaVersion: _dynamicInt(policy['policySchemaVersion']) ?? 1,
        schedules: _dynamicListOfMaps(policy['schedules']),
        safeSearchEnabled:
            _dynamicBool(policy['safeSearchEnabled'], fallback: true),
      );
    }
  }

  Future<void> resumeAllChildren(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final snapshot = await _firestore
        .collection('children')
        .where('parentId', isEqualTo: parentId)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final updatedAt = DateTime.now();
    final batch = _firestore.batch();
    final childrenForEvents = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snapshot.docs) {
      childrenForEvents.add(doc);
      batch.update(doc.reference, <String, dynamic>{
        'pausedUntil': null,
        'updatedAt': Timestamp.fromDate(updatedAt),
      });
    }
    await batch.commit();

    for (final doc in childrenForEvents) {
      final data = doc.data() ?? const <String, dynamic>{};
      final policy = await _loadPolicySnapshotForChild(
        childId: doc.id,
        fallbackChildData: data,
      );
      final manualMode = _dynamicMap(data['manualMode']);
      final protectionEnabled = data['protectionEnabled'] != false;
      await _recordPolicyEventSnapshot(
        parentId: parentId,
        childId: doc.id,
        blockedCategories: _dynamicStringList(policy['blockedCategories']),
        blockedServices: _dynamicStringList(policy['blockedServices']),
        blockedDomains: _dynamicStringList(policy['blockedDomains']),
        blockedPackages: _dynamicStringList(policy['blockedPackages']),
        modeOverrides: _dynamicMap(policy['modeOverrides']),
        manualMode: manualMode.isEmpty ? null : manualMode,
        pausedUntil: null,
        protectionEnabled: protectionEnabled,
        sourceUpdatedAt: updatedAt,
        policySchemaVersion: _dynamicInt(policy['policySchemaVersion']) ?? 1,
        schedules: _dynamicListOfMaps(policy['schedules']),
        safeSearchEnabled:
            _dynamicBool(policy['safeSearchEnabled'], fallback: true),
      );
    }
  }

  /// Applies or clears pause for a single child profile.
  Future<void> setChildPause({
    required String parentId,
    required String childId,
    DateTime? pausedUntil,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    final childData = childDoc.data() ?? const <String, dynamic>{};
    final policy = await _loadPolicySnapshotForChild(
      childId: childId,
      fallbackChildData: childData,
    );
    final manualMode = _dynamicMap(childData['manualMode']);
    final blockedCategories = _dynamicStringList(policy['blockedCategories']);
    final blockedServices = _dynamicStringList(policy['blockedServices']);
    final blockedDomains = _dynamicStringList(policy['blockedDomains']);
    final blockedPackages = _dynamicStringList(policy['blockedPackages']);
    final modeOverrides = _dynamicMap(policy['modeOverrides']);
    final policySchemaVersion = _dynamicInt(policy['policySchemaVersion']) ?? 1;
    final protectionEnabled = childData['protectionEnabled'] != false;
    final updatedAt = DateTime.now();
    await childDoc.reference.update(<String, dynamic>{
      'pausedUntil':
          pausedUntil == null ? null : Timestamp.fromDate(pausedUntil),
      'updatedAt': Timestamp.fromDate(updatedAt),
    });
    try {
      await _recordPolicyEventSnapshot(
        parentId: parentId,
        childId: childId,
        blockedCategories: blockedCategories,
        blockedServices: blockedServices,
        blockedDomains: blockedDomains,
        blockedPackages: blockedPackages,
        modeOverrides: modeOverrides,
        manualMode: manualMode.isEmpty ? null : manualMode,
        pausedUntil: pausedUntil,
        protectionEnabled: protectionEnabled,
        sourceUpdatedAt: updatedAt,
        policySchemaVersion: policySchemaVersion,
        schedules: _dynamicListOfMaps(policy['schedules']),
        safeSearchEnabled:
            _dynamicBool(policy['safeSearchEnabled'], fallback: true),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Policy event logging failed while setting child pause; continuing with core update.',
        name: 'FirestoreService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setChildProtectionEnabled({
    required String parentId,
    required String childId,
    required bool enabled,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    final childData = childDoc.data() ?? const <String, dynamic>{};
    final policy = await _loadPolicySnapshotForChild(
      childId: childId,
      fallbackChildData: childData,
    );
    final manualMode = _dynamicMap(childData['manualMode']);
    final blockedCategories = _dynamicStringList(policy['blockedCategories']);
    final blockedServices = _dynamicStringList(policy['blockedServices']);
    final blockedDomains = _dynamicStringList(policy['blockedDomains']);
    final blockedPackages = _dynamicStringList(policy['blockedPackages']);
    final modeOverrides = _dynamicMap(policy['modeOverrides']);
    final policySchemaVersion = _dynamicInt(policy['policySchemaVersion']) ?? 1;
    final pausedUntil = _dynamicDateTime(childData['pausedUntil']);
    final updatedAt = DateTime.now();

    await childDoc.reference.update(<String, dynamic>{
      'protectionEnabled': enabled,
      'updatedAt': Timestamp.fromDate(updatedAt),
    });

    await _recordPolicyEventSnapshot(
      parentId: parentId,
      childId: childId,
      blockedCategories: blockedCategories,
      blockedServices: blockedServices,
      blockedDomains: blockedDomains,
      blockedPackages: blockedPackages,
      modeOverrides: modeOverrides,
      manualMode: manualMode.isEmpty ? null : manualMode,
      pausedUntil: pausedUntil,
      protectionEnabled: enabled,
      sourceUpdatedAt: updatedAt,
      policySchemaVersion: policySchemaVersion,
      schedules: _dynamicListOfMaps(policy['schedules']),
      safeSearchEnabled:
          _dynamicBool(policy['safeSearchEnabled'], fallback: true),
    );
  }

  /// Persists or clears manual quick-mode override for a child.
  ///
  /// Supported modes are currently `homework`, `bedtime`, and `free`.
  Future<void> setChildManualMode({
    required String parentId,
    required String childId,
    String? mode,
    DateTime? expiresAt,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    final childData = childDoc.data() ?? const <String, dynamic>{};
    final policy = await _loadPolicySnapshotForChild(
      childId: childId,
      fallbackChildData: childData,
    );
    final blockedCategories = _dynamicStringList(policy['blockedCategories']);
    final blockedServices = _dynamicStringList(policy['blockedServices']);
    final blockedDomains = _dynamicStringList(policy['blockedDomains']);
    final blockedPackages = _dynamicStringList(policy['blockedPackages']);
    final modeOverrides = _dynamicMap(policy['modeOverrides']);
    final policySchemaVersion = _dynamicInt(policy['policySchemaVersion']) ?? 1;
    final pausedUntil = _dynamicDateTime(childData['pausedUntil']);
    final protectionEnabled = childData['protectionEnabled'] != false;
    final normalizedMode = mode?.trim().toLowerCase();
    final updatedAt = DateTime.now();

    if (normalizedMode == null || normalizedMode.isEmpty) {
      await childDoc.reference.update(<String, dynamic>{
        'manualMode': null,
        'updatedAt': Timestamp.fromDate(updatedAt),
      });
      try {
        await _recordPolicyEventSnapshot(
          parentId: parentId,
          childId: childId,
          blockedCategories: blockedCategories,
          blockedServices: blockedServices,
          blockedDomains: blockedDomains,
          blockedPackages: blockedPackages,
          modeOverrides: modeOverrides,
          manualMode: null,
          pausedUntil: pausedUntil,
          protectionEnabled: protectionEnabled,
          sourceUpdatedAt: updatedAt,
          policySchemaVersion: policySchemaVersion,
          schedules: _dynamicListOfMaps(policy['schedules']),
          safeSearchEnabled:
              _dynamicBool(policy['safeSearchEnabled'], fallback: true),
        );
      } catch (error, stackTrace) {
        developer.log(
          'Policy event logging failed while clearing child manual mode; continuing with core update.',
          name: 'FirestoreService',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return;
    }

    final manualModePayload = <String, dynamic>{
      'mode': normalizedMode,
      'setAt': Timestamp.fromDate(updatedAt),
      'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt),
    };
    await childDoc.reference.update(<String, dynamic>{
      'manualMode': manualModePayload,
      'updatedAt': Timestamp.fromDate(updatedAt),
    });
    try {
      await _recordPolicyEventSnapshot(
        parentId: parentId,
        childId: childId,
        blockedCategories: blockedCategories,
        blockedServices: blockedServices,
        blockedDomains: blockedDomains,
        blockedPackages: blockedPackages,
        modeOverrides: modeOverrides,
        manualMode: manualModePayload,
        pausedUntil: pausedUntil,
        protectionEnabled: protectionEnabled,
        sourceUpdatedAt: updatedAt,
        policySchemaVersion: policySchemaVersion,
        schedules: _dynamicListOfMaps(policy['schedules']),
        safeSearchEnabled:
            _dynamicBool(policy['safeSearchEnabled'], fallback: true),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Policy event logging failed while setting child manual mode; continuing with core update.',
        name: 'FirestoreService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Submit a new access request from child profile.
  Future<String> submitAccessRequest(AccessRequest request) async {
    return _requestRepository.submitAccessRequest(request);
  }

  /// Stream pending access requests for parent dashboard actions.
  Stream<List<AccessRequest>> getPendingRequestsStream(String parentId) {
    return _requestRepository.getPendingRequestsStream(parentId);
  }

  /// Stream unread bypass alert count for a parent.
  Stream<int> getUnreadBypassAlertCountStream(String parentId) {
    return _alertRepository.getUnreadBypassAlertCountStream(parentId);
  }

  /// Stream recent access requests for a specific child profile.
  Stream<List<AccessRequest>> getChildRequestsStream({
    required String parentId,
    required String childId,
  }) {
    return _requestRepository.getChildRequestsStream(
      parentId: parentId,
      childId: childId,
    );
  }

  /// Parent responds to an access request (approved or denied).
  Future<void> respondToAccessRequest({
    required String parentId,
    required String requestId,
    required RequestStatus status,
    String? reply,
    RequestDuration? approvedDurationOverride,
  }) async {
    return _requestRepository.respondToAccessRequest(
      parentId: parentId,
      requestId: requestId,
      status: status,
      reply: reply,
      approvedDurationOverride: approvedDurationOverride,
    );
  }

  /// Parent ends an active approved request immediately.
  ///
  /// This marks the request as expired so temporary DNS exceptions are removed
  /// on the next policy sync.
  Future<void> expireApprovedAccessRequestNow({
    required String parentId,
    required String requestId,
  }) async {
    return _requestRepository.expireApprovedAccessRequestNow(
      parentId: parentId,
      requestId: requestId,
    );
  }

  /// Stream all requests (pending + history) for parent.
  Stream<List<AccessRequest>> getAllRequestsStream(String parentId) {
    return _requestRepository.getAllRequestsStream(parentId);
  }

  /// Returns active approved request domains that should be temporarily allowed.
  ///
  /// Domains are normalized (lowercase host only) and filtered for:
  /// - status == approved
  /// - not expired (or no expiry)
  /// - valid domain-like `appOrSite` values
  Future<List<String>> getActiveApprovedExceptionDomains({
    required String parentId,
    String? childId,
    int limit = 200,
  }) async {
    return _requestRepository.getActiveApprovedExceptionDomains(
      parentId: parentId,
      childId: childId,
      limit: limit,
    );
  }

  /// Returns the nearest future expiry timestamp among approved requests.
  ///
  /// Used by policy sync to schedule a one-shot refresh when a temporary
  /// exception window ends.
  Future<DateTime?> getNextApprovedExceptionExpiry({
    required String parentId,
    String? childId,
    int limit = 200,
  }) async {
    return _requestRepository.getNextApprovedExceptionExpiry(
      parentId: parentId,
      childId: childId,
      limit: limit,
    );
  }

  Future<void> _recordPolicyEventSnapshot({
    required String parentId,
    required String childId,
    required Iterable<String> blockedCategories,
    required Iterable<String> blockedServices,
    required Iterable<String> blockedDomains,
    required Iterable<String> blockedPackages,
    required Map<String, dynamic>? modeOverrides,
    required Map<String, dynamic>? manualMode,
    required DateTime? pausedUntil,
    required bool protectionEnabled,
    required DateTime sourceUpdatedAt,
    required int policySchemaVersion,
    required Iterable<Map<String, dynamic>> schedules,
    required bool safeSearchEnabled,
  }) async {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty || normalizedChildId.isEmpty) {
      return;
    }
    try {
      final normalizedCategories = _normalizeStringIterable(blockedCategories);
      final canonicalCategories = normalizeCategoryIds(normalizedCategories);
      final normalizedServices = _normalizeServiceIds(blockedServices);
      final normalizedDomains = _normalizeStringIterable(blockedDomains);
      final normalizedPackages = _normalizePackageIds(blockedPackages);
      final normalizedModeOverrides = _normalizeModeOverridesMap(modeOverrides);
      final normalizedSchedules = _dynamicListOfMaps(schedules);
      final normalizedManualMode =
          protectionEnabled ? _normalizeManualModeMap(manualMode) : null;
      final effectivePausedUntil = protectionEnabled ? pausedUntil : null;
      final observedPackageDomains = protectionEnabled
          ? await getChildObservedAppDomainsOnce(
              parentId: normalizedParentId,
              childId: normalizedChildId,
            )
          : const <String, List<String>>{};
      final activeModeKey = protectionEnabled
          ? _activeModeOverrideKey(
              pausedUntil: effectivePausedUntil,
              manualMode: normalizedManualMode,
              now: sourceUpdatedAt,
            )
          : null;
      final activeModeOverride = activeModeKey == null
          ? const <String, dynamic>{}
          : _dynamicMap(normalizedModeOverrides[activeModeKey]);
      final suppressModeForceBlocks = activeModeKey == 'free';
      final modeForceBlockServices = _normalizeServiceIds(
        _dynamicStringList(activeModeOverride['forceBlockServices']),
      );
      final modeForceAllowServices = _normalizeServiceIds(
        _dynamicStringList(activeModeOverride['forceAllowServices']),
      );
      final modeForceBlockPackages = _normalizePackageIds(
        _dynamicStringList(activeModeOverride['forceBlockPackages']),
      );
      final modeForceAllowPackages = _normalizePackageIds(
        _dynamicStringList(activeModeOverride['forceAllowPackages']),
      );
      final modeForceBlockDomains = _normalizeStringIterable(
        _dynamicStringList(activeModeOverride['forceBlockDomains']),
      );
      final modeForceAllowDomains = _normalizeStringIterable(
        _dynamicStringList(activeModeOverride['forceAllowDomains']),
      );
      final modeBlockedPackages = protectionEnabled && !suppressModeForceBlocks
          ? (<String>{
              ...ServiceDefinitions.resolvePackages(
                blockedCategories: const <String>[],
                blockedServices: modeForceBlockServices,
              ),
              ...modeForceBlockPackages,
            }.toList()
            ..sort())
          : <String>[];
      final modeAllowedPackages = protectionEnabled
          ? (<String>{
              ...ServiceDefinitions.resolvePackages(
                blockedCategories: const <String>[],
                blockedServices: modeForceAllowServices,
              ),
              ...modeForceAllowPackages,
            }.toList()
            ..sort())
          : <String>[];
      final modeBlockedDomains = protectionEnabled && !suppressModeForceBlocks
          ? (<String>{
              ...ServiceDefinitions.resolveDomains(
                blockedCategories: const <String>[],
                blockedServices: modeForceBlockServices,
                customBlockedDomains: modeForceBlockDomains,
              ),
              ..._resolveDomainsForPackagesUsingObserved(
                blockedPackages: modeBlockedPackages,
                observedPackageDomains: observedPackageDomains,
              ),
            }.toList()
            ..sort())
          : <String>[];
      final modeAllowedDomains = protectionEnabled
          ? (<String>{
              ...ServiceDefinitions.resolveDomains(
                blockedCategories: const <String>[],
                blockedServices: modeForceAllowServices,
                customBlockedDomains: modeForceAllowDomains,
              ),
              ..._resolveDomainsForPackagesUsingObserved(
                blockedPackages: modeAllowedPackages,
                observedPackageDomains: observedPackageDomains,
              ),
            }.toList()
            ..sort())
          : <String>[];
      final resolvedPackages = protectionEnabled
          ? (<String>{
              ...ServiceDefinitions.resolvePackages(
                blockedCategories: canonicalCategories,
                blockedServices: normalizedServices,
              ),
              ...normalizedPackages,
              ...modeBlockedPackages,
            }.toList()
            ..removeWhere(modeAllowedPackages.contains)
            ..sort())
          : <String>[];
      final resolvedDomains = protectionEnabled
          ? (<String>{
              ...ServiceDefinitions.resolveDomains(
                blockedCategories: canonicalCategories,
                blockedServices: normalizedServices,
                customBlockedDomains: normalizedDomains,
              ),
              ...modeBlockedDomains,
              ..._resolveDomainsForPackagesUsingObserved(
                blockedPackages: resolvedPackages,
                observedPackageDomains: observedPackageDomains,
              ),
            }.toList()
            ..removeWhere(modeAllowedDomains.contains)
            ..sort())
          : <String>[];
      final temporaryAllowedDomainsResolved =
          protectionEnabled ? modeAllowedDomains : <String>[];
      final effectiveCategories =
          protectionEnabled ? canonicalCategories : <String>[];
      final effectiveServices =
          protectionEnabled ? normalizedServices : <String>[];
      final effectiveDomains =
          protectionEnabled ? normalizedDomains : <String>[];
      final effectivePackages =
          protectionEnabled ? normalizedPackages : <String>[];
      final version = _nextPolicyEventEpochMs();
      final deleteAt = DateTime.now().add(const Duration(days: 30));

      await _firestore
          .collection('children')
          .doc(normalizedChildId)
          .collection('policy_events')
          .add(<String, dynamic>{
        'parentId': normalizedParentId,
        'childId': normalizedChildId,
        'protectionEnabled': protectionEnabled,
        'blockedCategories': effectiveCategories,
        'blockedServices': effectiveServices,
        'blockedDomains': effectiveDomains,
        'blockedPackages': effectivePackages,
        'blockedDomainsResolved': resolvedDomains,
        'blockedPackagesResolved': resolvedPackages,
        'temporaryAllowedDomainsResolved': temporaryAllowedDomainsResolved,
        'modeOverrides': normalizedModeOverrides,
        'modeOverridesResolved': normalizedModeOverrides,
        'activeModeKey': activeModeKey,
        'modeBlockedDomainsResolved': modeBlockedDomains,
        'modeAllowedDomainsResolved': modeAllowedDomains,
        'modeBlockedPackagesResolved': modeBlockedPackages,
        'modeAllowedPackagesResolved': modeAllowedPackages,
        'policySchemaVersion':
            policySchemaVersion <= 0 ? 2 : policySchemaVersion,
        'schedules': normalizedSchedules,
        'safeSearchEnabled': safeSearchEnabled,
        'manualMode': normalizedManualMode,
        'pausedUntil': effectivePausedUntil == null
            ? null
            : Timestamp.fromDate(effectivePausedUntil),
        'sourceUpdatedAt': Timestamp.fromDate(sourceUpdatedAt),
        'eventEpochMs': version,
        'version': version,
        'createdAt': FieldValue.serverTimestamp(),
        'deleteAt': Timestamp.fromDate(deleteAt),
      });
      await _writeEffectivePolicyCurrent(
        parentId: normalizedParentId,
        childId: normalizedChildId,
        baseBlockedCategories: canonicalCategories,
        baseBlockedServices: normalizedServices,
        baseBlockedDomains: normalizedDomains,
        baseBlockedPackages: normalizedPackages,
        baseModeOverrides: normalizedModeOverrides,
        blockedCategories: effectiveCategories,
        blockedServices: effectiveServices,
        customBlockedDomains: effectiveDomains,
        blockedPackages: effectivePackages,
        blockedDomainsResolved: resolvedDomains,
        blockedPackagesResolved: resolvedPackages,
        temporaryAllowedDomainsResolved: temporaryAllowedDomainsResolved,
        modeOverridesResolved: normalizedModeOverrides,
        activeModeKey: activeModeKey,
        modeBlockedDomainsResolved: modeBlockedDomains,
        modeAllowedDomainsResolved: modeAllowedDomains,
        modeBlockedPackagesResolved: modeBlockedPackages,
        modeAllowedPackagesResolved: modeAllowedPackages,
        manualMode: normalizedManualMode,
        pausedUntil: effectivePausedUntil,
        protectionEnabled: protectionEnabled,
        sourceUpdatedAt: sourceUpdatedAt,
        version: version,
        policySchemaVersion: policySchemaVersion <= 0 ? 2 : policySchemaVersion,
        schedules: normalizedSchedules,
        safeSearchEnabled: safeSearchEnabled,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to append child policy event for $normalizedChildId',
        name: 'FirestoreService',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _writeEffectivePolicyCurrent({
    required String parentId,
    required String childId,
    required List<String> baseBlockedCategories,
    required List<String> baseBlockedServices,
    required List<String> baseBlockedDomains,
    required List<String> baseBlockedPackages,
    required Map<String, dynamic> baseModeOverrides,
    required List<String> blockedCategories,
    required List<String> blockedServices,
    required List<String> customBlockedDomains,
    required List<String> blockedPackages,
    required List<String> blockedDomainsResolved,
    required List<String> blockedPackagesResolved,
    required List<String> temporaryAllowedDomainsResolved,
    required Map<String, dynamic> modeOverridesResolved,
    required String? activeModeKey,
    required List<String> modeBlockedDomainsResolved,
    required List<String> modeAllowedDomainsResolved,
    required List<String> modeBlockedPackagesResolved,
    required List<String> modeAllowedPackagesResolved,
    required Map<String, dynamic>? manualMode,
    required DateTime? pausedUntil,
    required bool protectionEnabled,
    required DateTime sourceUpdatedAt,
    required int version,
    required int policySchemaVersion,
    required Iterable<Map<String, dynamic>> schedules,
    required bool safeSearchEnabled,
  }) async {
    final childDoc = _firestore.collection('children').doc(childId);
    final effectivePolicyDoc =
        childDoc.collection('effective_policy').doc('current');
    final syncTriggerDoc = childDoc.collection('trigger').doc('sync');

    final batch = _firestore.batch();
    batch.set(
      effectivePolicyDoc,
      <String, dynamic>{
        'parentId': parentId,
        'childId': childId,
        'version': version,
        'protectionEnabled': protectionEnabled,
        'baseBlockedCategories': baseBlockedCategories,
        'baseBlockedServices': baseBlockedServices,
        'baseBlockedDomains': baseBlockedDomains,
        'baseBlockedPackages': baseBlockedPackages,
        'baseModeOverrides': baseModeOverrides,
        'blockedCategories': blockedCategories,
        'blockedServices': blockedServices,
        'blockedDomains': customBlockedDomains,
        'blockedPackages': blockedPackages,
        'blockedDomainsResolved': blockedDomainsResolved,
        'blockedPackagesResolved': blockedPackagesResolved,
        'temporaryAllowedDomainsResolved': temporaryAllowedDomainsResolved,
        'modeOverridesResolved': modeOverridesResolved,
        'activeModeKey': activeModeKey,
        'modeBlockedDomainsResolved': modeBlockedDomainsResolved,
        'modeAllowedDomainsResolved': modeAllowedDomainsResolved,
        'modeBlockedPackagesResolved': modeBlockedPackagesResolved,
        'modeAllowedPackagesResolved': modeAllowedPackagesResolved,
        'policySchemaVersion':
            policySchemaVersion <= 0 ? 2 : policySchemaVersion,
        'schedules': _dynamicListOfMaps(schedules),
        'safeSearchEnabled': safeSearchEnabled,
        'manualMode': manualMode,
        'pausedUntil':
            pausedUntil == null ? null : Timestamp.fromDate(pausedUntil),
        'sourceUpdatedAt': Timestamp.fromDate(sourceUpdatedAt),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      syncTriggerDoc,
      <String, dynamic>{
        // Use the policy version directly so create/update writes are rule-safe
        // even when transform evaluation differs across SDK/runtime versions.
        'version': version,
        'policyVersion': version,
        'parentId': parentId,
        'childId': childId,
        'sourceUpdatedAt': Timestamp.fromDate(sourceUpdatedAt),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  List<String> _normalizeStringIterable(Iterable<String> values) {
    return values
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> _normalizeServiceIds(Iterable<String> values) {
    final normalized = <String>{};
    for (final value in values) {
      final serviceId = value.trim().toLowerCase();
      if (serviceId.isEmpty) {
        continue;
      }
      if (!ServiceDefinitions.byId.containsKey(serviceId)) {
        continue;
      }
      normalized.add(serviceId);
    }
    final ordered = normalized.toList()..sort();
    return ordered;
  }

  List<String> _normalizePackageIds(Iterable<String> values) {
    final normalized = <String>{};
    for (final value in values) {
      final packageName = value.trim().toLowerCase();
      if (packageName.isEmpty) {
        continue;
      }
      normalized.add(packageName);
    }
    final ordered = normalized.toList()..sort();
    return ordered;
  }

  Set<String> _resolveDomainsForPackagesUsingObserved({
    required Iterable<String> blockedPackages,
    required Map<String, List<String>> observedPackageDomains,
  }) {
    final result = <String>{};
    for (final rawPackage in blockedPackages) {
      final packageName = rawPackage.trim().toLowerCase();
      if (packageName.isEmpty) {
        continue;
      }
      final observed = observedPackageDomains[packageName];
      if (observed != null && observed.isNotEmpty) {
        result.addAll(
          observed.map((domain) => domain.trim().toLowerCase()).where(
                (domain) =>
                    domain.isNotEmpty &&
                    _isPackageScopedObservedDomain(
                      packageName: packageName,
                      domain: domain,
                    ),
              ),
        );
      }
    }
    return result;
  }

  bool _isPackageScopedObservedDomain({
    required String packageName,
    required String domain,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    if (normalizedDomain.isEmpty) {
      return false;
    }

    // Keep explicit package-scoped matches and drop generic shared infra
    // domains (for example graph.facebook.com) to avoid collateral blocking.
    const ignoredTokens = <String>{
      'com',
      'org',
      'net',
      'app',
      'android',
      'google',
      'service',
      'services',
      'mobile',
      'client',
      'free',
      'lite',
      'global',
      'india',
      'official',
      'inc',
      'co',
    };

    final tokens = packageName
        .split('.')
        .map((token) => token.trim().toLowerCase())
        .where((token) => token.length >= 4 && !ignoredTokens.contains(token))
        .toSet();
    if (tokens.isEmpty) {
      return false;
    }

    for (final token in tokens) {
      if (normalizedDomain == token ||
          normalizedDomain.endsWith('.$token') ||
          normalizedDomain.contains('$token.') ||
          normalizedDomain.contains('-$token') ||
          normalizedDomain.contains('$token-')) {
        return true;
      }
    }
    return false;
  }

  Map<String, ModeOverrideSet> _normalizeModeOverridesModel(
    Map<String, ModeOverrideSet> values,
  ) {
    final normalized = <String, ModeOverrideSet>{};
    for (final entry in values.entries) {
      final modeName = entry.key.trim().toLowerCase();
      if (modeName.isEmpty) {
        continue;
      }
      final normalizedSet = ModeOverrideSet(
        forceBlockServices: _normalizeStringIterable(
          entry.value.forceBlockServices,
        ),
        forceAllowServices: _normalizeStringIterable(
          entry.value.forceAllowServices,
        ),
        forceBlockPackages: _normalizePackageIds(
          entry.value.forceBlockPackages,
        ),
        forceAllowPackages: _normalizePackageIds(
          entry.value.forceAllowPackages,
        ),
        forceBlockDomains: _normalizeStringIterable(
          entry.value.forceBlockDomains,
        ),
        forceAllowDomains: _normalizeStringIterable(
          entry.value.forceAllowDomains,
        ),
      );
      if (normalizedSet.isEmpty) {
        continue;
      }
      normalized[modeName] = normalizedSet;
    }
    return normalized;
  }

  Map<String, dynamic> _normalizeModeOverridesMap(
    Map<String, dynamic>? rawOverrides,
  ) {
    if (rawOverrides == null || rawOverrides.isEmpty) {
      return <String, dynamic>{};
    }
    final normalized = <String, dynamic>{};
    for (final entry in rawOverrides.entries) {
      final modeName = entry.key.trim().toLowerCase();
      if (modeName.isEmpty) {
        continue;
      }
      final modeMap = _dynamicMap(entry.value);
      if (modeMap.isEmpty) {
        continue;
      }
      final normalizedModeMap = <String, dynamic>{
        'forceBlockServices': _normalizeStringIterable(
            _dynamicStringList(modeMap['forceBlockServices'])),
        'forceAllowServices': _normalizeStringIterable(
            _dynamicStringList(modeMap['forceAllowServices'])),
        'forceBlockPackages': _normalizePackageIds(
            _dynamicStringList(modeMap['forceBlockPackages'])),
        'forceAllowPackages': _normalizePackageIds(
            _dynamicStringList(modeMap['forceAllowPackages'])),
        'forceBlockDomains': _normalizeStringIterable(
            _dynamicStringList(modeMap['forceBlockDomains'])),
        'forceAllowDomains': _normalizeStringIterable(
            _dynamicStringList(modeMap['forceAllowDomains'])),
      };
      final hasAnyValue = normalizedModeMap.values.any(
        (value) => value is List && value.isNotEmpty,
      );
      if (!hasAnyValue) {
        continue;
      }
      normalized[modeName] = normalizedModeMap;
    }
    return normalized;
  }

  Map<String, dynamic>? _normalizeManualModeMap(Map<String, dynamic>? rawMode) {
    if (rawMode == null || rawMode.isEmpty) {
      return null;
    }
    final normalizedMode = (rawMode['mode'] as String?)?.trim().toLowerCase();
    if (normalizedMode == null || normalizedMode.isEmpty) {
      return null;
    }
    final setAt = _dynamicDateTime(rawMode['setAt']);
    final expiresAt = _dynamicDateTime(rawMode['expiresAt']);
    return <String, dynamic>{
      'mode': normalizedMode,
      if (setAt != null) 'setAt': Timestamp.fromDate(setAt),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
    };
  }

  String? _activeModeOverrideKey({
    required DateTime? pausedUntil,
    required Map<String, dynamic>? manualMode,
    required DateTime now,
  }) {
    if (pausedUntil != null && pausedUntil.isAfter(now)) {
      return 'bedtime';
    }
    if (manualMode == null || manualMode.isEmpty) {
      return 'free';
    }
    final mode = (manualMode['mode'] as String?)?.trim().toLowerCase();
    if (mode == null || mode.isEmpty) {
      return 'free';
    }
    final expiresAt = _dynamicDateTime(manualMode['expiresAt']);
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      return 'free';
    }
    switch (mode) {
      case 'homework':
        return 'homework';
      case 'bedtime':
        return 'bedtime';
      case 'free':
        return 'free';
      default:
        return 'focus';
    }
  }

  int _nextPolicyEventEpochMs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= _lastPolicyEventEpochMs) {
      _lastPolicyEventEpochMs += 1;
    } else {
      _lastPolicyEventEpochMs = now;
    }
    return _lastPolicyEventEpochMs;
  }

  Map<String, dynamic> _dynamicMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _dynamicListOfMaps(
    Object? raw, {
    Iterable<Map<String, dynamic>> fallback = const <Map<String, dynamic>>[],
  }) {
    final source = raw is Iterable ? raw : fallback;
    final result = <Map<String, dynamic>>[];
    for (final item in source) {
      final map = _dynamicMap(item);
      if (map.isEmpty) {
        continue;
      }
      result.add(map);
    }
    return List<Map<String, dynamic>>.unmodifiable(result);
  }

  bool _dynamicBool(
    Object? raw, {
    required bool fallback,
  }) {
    if (raw is bool) {
      return raw;
    }
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return fallback;
  }

  Set<String> _dynamicStringList(Object? raw) {
    if (raw is! List) {
      return <String>{};
    }
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  DateTime? _dynamicDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is int && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is num && raw.toInt() > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String) {
      final parsedInt = int.tryParse(raw.trim());
      if (parsedInt != null && parsedInt > 0) {
        return DateTime.fromMillisecondsSinceEpoch(parsedInt);
      }
      final parsedDate = DateTime.tryParse(raw.trim());
      if (parsedDate != null) {
        return parsedDate;
      }
    }
    return null;
  }

  int? _dynamicInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

}
