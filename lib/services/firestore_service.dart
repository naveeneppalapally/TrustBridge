import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/config/category_ids.dart';
import 'package:trustbridge_app/config/service_definitions.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/installed_app_info.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/support_ticket.dart';
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

  /// Public accessor for the underlying Firestore instance.
  FirebaseFirestore get firestore => _firestore;
  final CrashlyticsService _crashlyticsService = CrashlyticsService();
  final PerformanceService _performanceService = PerformanceService();

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

  /// One-shot fetch of parent preferences plus onboarding status fields.
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

  /// Mark onboarding as complete for a parent.
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

  /// Stores DPDPA guardian consent acknowledgement metadata.
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

  /// Check if onboarding is complete for a parent.
  Future<bool> isOnboardingComplete(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    final preferences = await getParentPreferences(parentId);
    return (preferences?['onboardingComplete'] as bool?) == true;
  }

  /// Save parent's FCM token for push notifications.
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

  /// Remove parent's FCM token on logout or account switch.
  Future<void> removeFcmToken(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    await _firestore.collection('parents').doc(parentId).set(
      <String, dynamic>{'fcmToken': FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  /// Queue a parent push notification payload for backend processing.
  Future<void> queueParentNotification({
    required String parentId,
    required String title,
    required String body,
    required String route,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'Title is required.');
    }
    if (body.trim().isEmpty) {
      throw ArgumentError.value(body, 'body', 'Body is required.');
    }
    if (route.trim().isEmpty) {
      throw ArgumentError.value(route, 'route', 'Route is required.');
    }

    await _firestore.collection('notification_queue').add({
      'parentId': parentId.trim(),
      'title': title.trim(),
      'body': _truncateNotificationBody(body),
      'route': route.trim(),
      'sentAt': FieldValue.serverTimestamp(),
      'processed': false,
    });
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
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'Title is required.');
    }
    if (body.trim().isEmpty) {
      throw ArgumentError.value(body, 'body', 'Body is required.');
    }
    if (route.trim().isEmpty) {
      throw ArgumentError.value(route, 'route', 'Route is required.');
    }
    if (eventType.trim().isEmpty) {
      throw ArgumentError.value(
        eventType,
        'eventType',
        'Event type is required.',
      );
    }

    await _firestore.collection('notification_queue').add({
      'parentId': parentId.trim(),
      'childId': childId.trim(),
      'title': title.trim(),
      'body': _truncateNotificationBody(body),
      'route': route.trim(),
      'eventType': eventType.trim(),
      'sentAt': FieldValue.serverTimestamp(),
      'processed': false,
    });
  }

  Stream<Map<String, dynamic>?> watchParentProfile(String parentId) {
    return _firestore
        .collection('parents')
        .doc(parentId)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  Future<void> updateParentSecurityMetadata({
    required String parentId,
    DateTime? appPinChangedAt,
    int? activeSessions,
    bool? twoFactorEnabled,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final updates = <String, dynamic>{};
    if (appPinChangedAt != null) {
      updates['appPinChangedAt'] = Timestamp.fromDate(appPinChangedAt);
    }
    if (activeSessions != null) {
      updates['activeSessions'] = activeSessions;
    }
    if (twoFactorEnabled != null) {
      updates['twoFactorEnabled'] = twoFactorEnabled;
    }
    if (updates.isEmpty) {
      return;
    }

    await _firestore.collection('parents').doc(parentId).set(
      <String, dynamic>{
        'security': updates,
      },
      SetOptions(merge: true),
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
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final preferenceUpdates = <String, dynamic>{};
    if (language != null) {
      preferenceUpdates['language'] = language;
    }
    if (timezone != null) {
      preferenceUpdates['timezone'] = timezone;
    }
    if (pushNotificationsEnabled != null) {
      preferenceUpdates['pushNotificationsEnabled'] = pushNotificationsEnabled;
    }
    if (weeklySummaryEnabled != null) {
      preferenceUpdates['weeklySummaryEnabled'] = weeklySummaryEnabled;
    }
    if (securityAlertsEnabled != null) {
      preferenceUpdates['securityAlertsEnabled'] = securityAlertsEnabled;
    }
    if (activityHistoryEnabled != null) {
      preferenceUpdates['activityHistoryEnabled'] = activityHistoryEnabled;
    }
    if (crashReportsEnabled != null) {
      preferenceUpdates['crashReportsEnabled'] = crashReportsEnabled;
    }
    if (personalizedTipsEnabled != null) {
      preferenceUpdates['personalizedTipsEnabled'] = personalizedTipsEnabled;
    }
    if (biometricLoginEnabled != null) {
      preferenceUpdates['biometricLoginEnabled'] = biometricLoginEnabled;
    }
    if (incognitoModeEnabled != null) {
      preferenceUpdates['incognitoModeEnabled'] = incognitoModeEnabled;
    }
    if (vpnProtectionEnabled != null) {
      preferenceUpdates['vpnProtectionEnabled'] = vpnProtectionEnabled;
    }
    if (nextDnsEnabled != null) {
      preferenceUpdates['nextDnsEnabled'] = nextDnsEnabled;
    }
    if (nextDnsProfileId != null) {
      final trimmed = nextDnsProfileId.trim();
      preferenceUpdates['nextDnsProfileId'] = trimmed.isEmpty ? null : trimmed;
    }
    if (nextDnsApiConnected != null) {
      preferenceUpdates['nextDnsApiConnected'] = nextDnsApiConnected;
    }
    if (nextDnsConnectedAt != null) {
      preferenceUpdates['nextDnsConnectedAt'] =
          Timestamp.fromDate(nextDnsConnectedAt);
    }

    if (preferenceUpdates.isEmpty) {
      return;
    }

    await _firestore.collection('parents').doc(parentId).set(
      {
        'preferences': preferenceUpdates,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
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
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final updates = <String, dynamic>{};
    if (vpnDisabled != null) {
      updates['vpnDisabled'] = vpnDisabled;
    }
    if (uninstallAttempt != null) {
      updates['uninstallAttempt'] = uninstallAttempt;
    }
    if (privateDnsChanged != null) {
      updates['privateDnsChanged'] = privateDnsChanged;
    }
    if (deviceOffline30m != null) {
      updates['deviceOffline30m'] = deviceOffline30m;
    }
    if (deviceOffline24h != null) {
      updates['deviceOffline24h'] = deviceOffline24h;
    }
    if (emailSeriousAlerts != null) {
      updates['emailSeriousAlerts'] = emailSeriousAlerts;
    }

    if (updates.isEmpty) {
      return;
    }

    await _firestore.collection('parents').doc(parentId).set(
      <String, dynamic>{
        'alertPreferences': updates,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Returns alert preferences map for the parent account.
  Future<Map<String, dynamic>> getAlertPreferences(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final snapshot = await _firestore.collection('parents').doc(parentId).get();
    final data = snapshot.data();
    final raw = data?['alertPreferences'];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return <String, dynamic>{};
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
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    final normalizedDeviceId = deviceId.trim();
    if (normalizedParentId.isEmpty ||
        normalizedChildId.isEmpty ||
        normalizedDeviceId.isEmpty) {
      return;
    }

    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;

    final recentEvent = await _firestore
        .collection('bypass_events')
        .doc(normalizedDeviceId)
        .collection('events')
        .where('type', isEqualTo: 'device_offline_24h')
        .where('timestampEpochMs', isGreaterThanOrEqualTo: cutoff)
        .limit(1)
        .get();
    if (recentEvent.docs.isNotEmpty) {
      return;
    }

    await _firestore
        .collection('bypass_events')
        .doc(normalizedDeviceId)
        .collection('events')
        .add(<String, dynamic>{
      'type': 'device_offline_24h',
      'timestamp': FieldValue.serverTimestamp(),
      'timestampEpochMs': DateTime.now().millisecondsSinceEpoch,
      'deviceId': normalizedDeviceId,
      'childId': normalizedChildId,
      'childNickname':
          childNickname.trim().isEmpty ? 'Child' : childNickname.trim(),
      'parentId': normalizedParentId,
      'read': false,
    });

    await queueParentNotification(
      parentId: normalizedParentId,
      title: 'Device offline for 24+ hours',
      body:
          '${childNickname.trim().isEmpty ? 'Your child' : childNickname.trim()} has not checked in for 24+ hours.',
      route: '/parent/bypass-alerts',
    );
  }

  Future<String> createSupportTicket({
    required String parentId,
    required String subject,
    required String message,
    String? childId,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final normalizedSubject = subject.trim();
    if (normalizedSubject.isEmpty) {
      throw ArgumentError.value(subject, 'subject', 'Subject is required.');
    }

    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) {
      throw ArgumentError.value(message, 'message', 'Message is required.');
    }

    final ticketRef = _firestore.collection('supportTickets').doc();
    await ticketRef.set({
      'parentId': parentId,
      'subject': normalizedSubject,
      'message': normalizedMessage,
      'childId': childId,
      'status': 'open',
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    return ticketRef.id;
  }

  Stream<List<SupportTicket>> getSupportTicketsStream(
    String parentId, {
    int limit = 50,
  }) {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(
          limit, 'limit', 'Limit must be greater than 0.');
    }

    return _firestore
        .collection('supportTickets')
        .where('parentId', isEqualTo: parentId)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final tickets = <SupportTicket>[];
      for (final doc in snapshot.docs) {
        try {
          tickets.add(SupportTicket.fromFirestore(doc));
        } catch (error, stackTrace) {
          developer.log(
            'Skipping malformed support ticket document: ${doc.id}',
            name: 'FirestoreService',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tickets;
    });
  }

  /// Returns duplicate-ticket analytics summary for roadmap planning.
  Future<Map<String, dynamic>> getDuplicateAnalytics(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    try {
      final snapshot = await _firestore
          .collection('supportTickets')
          .where('parentId', isEqualTo: parentId)
          .limit(500)
          .get();

      final allTickets = <SupportTicket>[];
      for (final doc in snapshot.docs) {
        try {
          allTickets.add(SupportTicket.fromFirestore(doc));
        } catch (_) {
          // Skip malformed tickets.
        }
      }

      final clusterMap = <String, List<SupportTicket>>{};
      for (final ticket in allTickets) {
        final key = ticket.duplicateKey;
        if (key.isEmpty) {
          continue;
        }
        clusterMap.putIfAbsent(key, () => <SupportTicket>[]).add(ticket);
      }

      final duplicateClusters =
          clusterMap.entries.where((entry) => entry.value.length >= 2).toList();
      duplicateClusters
          .sort((a, b) => b.value.length.compareTo(a.value.length));

      final duplicateTickets = duplicateClusters
          .expand((entry) => entry.value)
          .toList(growable: false);
      final totalDuplicateReports = duplicateTickets.length;

      final resolvedDuplicateReports =
          duplicateTickets.where((ticket) => ticket.isResolved).length;
      final resolutionRate = totalDuplicateReports == 0
          ? 0.0
          : resolvedDuplicateReports / totalDuplicateReports;

      final velocities =
          duplicateTickets.where((ticket) => ticket.isResolved).map((ticket) {
        final days =
            ticket.updatedAt.difference(ticket.createdAt).inHours.toDouble() /
                24.0;
        return days < 0 ? 0.0 : days;
      }).toList();

      final avgVelocity = velocities.isEmpty
          ? 0.0
          : velocities.reduce((a, b) => a + b) / velocities.length;
      final minVelocity =
          velocities.isEmpty ? 0.0 : velocities.reduce((a, b) => a < b ? a : b);
      final maxVelocity =
          velocities.isEmpty ? 0.0 : velocities.reduce((a, b) => a > b ? a : b);

      final categoryMap = <String, int>{};
      for (final ticket in duplicateTickets) {
        final category = _extractDuplicateCategory(ticket.subject);
        categoryMap[category] = (categoryMap[category] ?? 0) + 1;
      }

      final now = DateTime.now();
      final volumeByWeek = <String, int>{
        'Week -3': 0,
        'Week -2': 0,
        'Week -1': 0,
        'Week -0': 0,
      };
      for (final ticket in duplicateTickets) {
        final weekOffset = now.difference(ticket.createdAt).inDays ~/ 7;
        if (weekOffset >= 0 && weekOffset < 4) {
          final weekKey = 'Week -$weekOffset';
          volumeByWeek[weekKey] = (volumeByWeek[weekKey] ?? 0) + 1;
        }
      }

      final topIssues = duplicateClusters
          .take(5)
          .map((entry) => <String, dynamic>{
                'subject': _formatDuplicateKeyForDisplay(entry.key),
                'count': entry.value.length,
              })
          .toList(growable: false);

      return <String, dynamic>{
        'topIssues': topIssues,
        'avgVelocityDays': avgVelocity,
        'minVelocityDays': minVelocity,
        'maxVelocityDays': maxVelocity,
        'volumeByWeek': volumeByWeek,
        'categoryBreakdown': categoryMap,
        'totalDuplicateClusters': duplicateClusters.length,
        'totalDuplicateReports': totalDuplicateReports,
        'resolutionRate': resolutionRate,
      };
    } catch (error, stackTrace) {
      developer.log(
        'Duplicate analytics error',
        name: 'FirestoreService',
        error: error,
        stackTrace: stackTrace,
      );
      return <String, dynamic>{};
    }
  }

  /// Exports top duplicate clusters as CSV text.
  Future<String> exportDuplicateClustersCSV(String parentId) async {
    final analytics = await getDuplicateAnalytics(parentId);
    final topIssues = (analytics['topIssues'] as List?) ?? const <dynamic>[];

    final csv = StringBuffer();
    csv.writeln('Subject,Report Count,Category');

    for (final rawIssue in topIssues) {
      if (rawIssue is! Map) {
        continue;
      }
      final subject = (rawIssue['subject'] as String? ?? '').trim();
      final count = rawIssue['count'];
      final category = _extractDuplicateCategory(subject);
      final escapedSubject = subject.replaceAll('"', '""');
      csv.writeln('"$escapedSubject",$count,$category');
    }

    return csv.toString();
  }

  String _extractDuplicateCategory(String subject) {
    final lower = subject.toLowerCase();
    if (lower.contains('vpn')) {
      return 'VPN';
    }
    if (lower.contains('notification')) {
      return 'Notifications';
    }
    if (lower.contains('policy') || lower.contains('schedule')) {
      return 'Policy';
    }
    if (lower.contains('crash') || lower.contains('bug')) {
      return 'Crashes';
    }
    if (lower.contains('request')) {
      return 'Requests';
    }
    if (lower.contains('dns')) {
      return 'DNS';
    }
    return 'Other';
  }

  String _formatDuplicateKeyForDisplay(String key) {
    if (key.trim().isEmpty) {
      return 'Unknown issue';
    }
    return key
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  /// Returns unresolved duplicate count for a normalized duplicate key.
  Future<int> getDuplicateClusterSize({
    required String parentId,
    required String duplicateKey,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final normalizedKey = duplicateKey.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(
        duplicateKey,
        'duplicateKey',
        'Duplicate key is required.',
      );
    }

    final snapshot = await _firestore
        .collection('supportTickets')
        .where('parentId', isEqualTo: parentId)
        .limit(300)
        .get();

    var count = 0;
    for (final doc in snapshot.docs) {
      try {
        final ticket = SupportTicket.fromFirestore(doc);
        if (!ticket.isResolved && ticket.duplicateKey == normalizedKey) {
          count += 1;
        }
      } catch (_) {
        // Skip malformed tickets.
      }
    }
    return count;
  }

  /// Resolves all unresolved tickets in a duplicate cluster.
  Future<int> bulkResolveDuplicates({
    required String parentId,
    required String duplicateKey,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final normalizedKey = duplicateKey.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(
        duplicateKey,
        'duplicateKey',
        'Duplicate key is required.',
      );
    }

    final snapshot = await _firestore
        .collection('supportTickets')
        .where('parentId', isEqualTo: parentId)
        .limit(300)
        .get();

    final batch = _firestore.batch();
    var updatedCount = 0;
    for (final doc in snapshot.docs) {
      try {
        final ticket = SupportTicket.fromFirestore(doc);
        if (ticket.isResolved || ticket.duplicateKey != normalizedKey) {
          continue;
        }

        batch.update(doc.reference, {
          'status': SupportTicketStatus.resolved.name,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
        updatedCount += 1;
      } catch (_) {
        // Skip malformed tickets.
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
    }

    return updatedCount;
  }

  /// Reopens recently resolved tickets in a duplicate cluster.
  Future<int> bulkReopenDuplicates({
    required String parentId,
    required String duplicateKey,
    int limit = 50,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final normalizedKey = duplicateKey.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(
        duplicateKey,
        'duplicateKey',
        'Duplicate key is required.',
      );
    }
    if (limit <= 0) {
      throw ArgumentError.value(
          limit, 'limit', 'Limit must be greater than 0.');
    }

    final snapshot = await _firestore
        .collection('supportTickets')
        .where('parentId', isEqualTo: parentId)
        .limit(300)
        .get();

    final candidates =
        <MapEntry<DocumentReference<Map<String, dynamic>>, SupportTicket>>[];
    for (final doc in snapshot.docs) {
      try {
        final ticket = SupportTicket.fromFirestore(doc);
        if (!ticket.isResolved || ticket.duplicateKey != normalizedKey) {
          continue;
        }
        candidates.add(MapEntry(doc.reference, ticket));
      } catch (_) {
        // Skip malformed tickets.
      }
    }

    candidates.sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));

    final batch = _firestore.batch();
    var reopenedCount = 0;
    for (final entry in candidates.take(limit)) {
      batch.update(entry.key, {
        'status': SupportTicketStatus.open.name,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      reopenedCount += 1;
    }

    if (reopenedCount > 0) {
      await batch.commit();
    }

    return reopenedCount;
  }

  Future<String> submitBetaFeedback({
    required String parentId,
    required String category,
    required String severity,
    required String title,
    required String details,
    String? childId,
  }) async {
    const allowedCategories = <String>{
      'Bug Report',
      'Blocking Accuracy',
      'Performance',
      'UX / Design',
      'Feature Request',
      'Other',
    };
    const allowedSeverities = <String>{
      'Low',
      'Medium',
      'High',
      'Critical',
    };

    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final normalizedCategory = category.trim();
    if (!allowedCategories.contains(normalizedCategory)) {
      throw ArgumentError.value(
        category,
        'category',
        'Unsupported beta feedback category.',
      );
    }

    final normalizedSeverity = severity.trim();
    if (!allowedSeverities.contains(normalizedSeverity)) {
      throw ArgumentError.value(
        severity,
        'severity',
        'Unsupported beta feedback severity.',
      );
    }

    final normalizedTitle = title.trim();
    if (normalizedTitle.length < 4 || normalizedTitle.length > 80) {
      throw ArgumentError.value(
        title,
        'title',
        'Title must be between 4 and 80 characters.',
      );
    }

    final normalizedDetails = details.trim();
    if (normalizedDetails.length < 20 || normalizedDetails.length > 1500) {
      throw ArgumentError.value(
        details,
        'details',
        'Details must be between 20 and 1500 characters.',
      );
    }

    final normalizedChildId = childId?.trim();

    final rawSubject =
        '[Beta][$normalizedSeverity] $normalizedCategory: $normalizedTitle';
    final subject =
        rawSubject.length > 120 ? rawSubject.substring(0, 120) : rawSubject;

    final messageBuffer = StringBuffer()
      ..writeln('Category: $normalizedCategory')
      ..writeln('Severity: $normalizedSeverity');
    if (normalizedChildId != null && normalizedChildId.isNotEmpty) {
      messageBuffer.writeln('Child ID: $normalizedChildId');
    }
    messageBuffer
      ..writeln()
      ..write(normalizedDetails)
      ..writeln()
      ..writeln()
      ..write('Submitted from Alpha feedback form.');

    final message = messageBuffer.toString();

    return createSupportTicket(
      parentId: parentId,
      subject: subject,
      message: message.length > 2000 ? message.substring(0, 2000) : message,
      childId: normalizedChildId == null || normalizedChildId.isEmpty
          ? null
          : normalizedChildId,
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
      await _firestore.collection('children').doc(child.id).set({
        ...child.toFirestore(),
        'parentId': parentId,
      });
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
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    return _firestore
        .collection('children')
        .where('parentId', isEqualTo: parentId)
        .snapshots()
        .map((snapshot) {
      final children = <ChildProfile>[];
      for (final doc in snapshot.docs) {
        try {
          children.add(ChildProfile.fromFirestore(doc));
        } catch (error, stackTrace) {
          developer.log(
            'Skipping malformed child document: ${doc.id}',
            name: 'FirestoreService',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      children.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return children;
    });
  }

  Future<List<ChildProfile>> getChildren(String parentId) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final snapshot = await _firestore
        .collection('children')
        .where('parentId', isEqualTo: parentId)
        .get();

    final children = <ChildProfile>[];
    for (final doc in snapshot.docs) {
      try {
        children.add(ChildProfile.fromFirestore(doc));
      } catch (error, stackTrace) {
        developer.log(
          'Skipping malformed child document: ${doc.id}',
          name: 'FirestoreService',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    children.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return children;
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

    final snapshot = await _firestore.collection('children').doc(childId).get();
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();
    if (data == null || data['parentId'] != parentId) {
      return null;
    }

    return ChildProfile.fromFirestore(snapshot);
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

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    if (!childDoc.exists) {
      return const <InstalledAppInfo>[];
    }

    final inventoryDoc = await childDoc.reference
        .collection('app_inventory')
        .doc('current')
        .get();
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

    return _firestore
        .collection('children')
        .doc(childId.trim())
        .collection('app_inventory')
        .doc('current')
        .snapshots()
        .asyncMap((snapshot) async {
      if (!snapshot.exists) {
        return const <InstalledAppInfo>[];
      }
      final childSnapshot =
          await _firestore.collection('children').doc(childId.trim()).get();
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

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    if (!childDoc.exists) {
      return const <String, List<String>>{};
    }

    final usageDoc = await childDoc.reference
        .collection('app_domain_usage')
        .doc('current')
        .get();
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
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }
    final normalizedProfileId = profileId.trim().toLowerCase();
    if (normalizedProfileId.isEmpty) {
      throw ArgumentError.value(
        profileId,
        'profileId',
        'NextDNS profile ID is required.',
      );
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );

    await childDoc.reference.update(<String, dynamic>{
      'nextDnsProfileId': normalizedProfileId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
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
    await childDoc.reference.update(<String, dynamic>{
      'nextDnsControls': controls,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
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
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Device ID cannot be empty.',
      );
    }
    final normalizedAlias = alias.trim();
    if (normalizedAlias.isEmpty) {
      throw ArgumentError.value(alias, 'alias', 'Device alias is required.');
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    final currentData = childDoc.data() ?? const <String, dynamic>{};
    final rawMetadata = currentData['deviceMetadata'];
    final metadataMap = rawMetadata is Map
        ? rawMetadata.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};

    final existingDeviceRaw = metadataMap[normalizedDeviceId];
    final existingDeviceMap = existingDeviceRaw is Map
        ? existingDeviceRaw.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    final now = Timestamp.fromDate(DateTime.now());

    metadataMap[normalizedDeviceId] = <String, dynamic>{
      'alias': normalizedAlias,
      'model': model?.trim().isEmpty == true ? null : model?.trim(),
      'manufacturer':
          manufacturer?.trim().isEmpty == true ? null : manufacturer?.trim(),
      'linkedNextDnsProfileId': linkedNextDnsProfileId?.trim().isEmpty == true
          ? null
          : linkedNextDnsProfileId?.trim(),
      'isVerified': existingDeviceMap['isVerified'] == true,
      'createdAt': existingDeviceMap['createdAt'] ?? now,
      'lastSeenAt': existingDeviceMap['lastSeenAt'],
    };

    final rawDeviceIds = currentData['deviceIds'];
    final deviceIds = rawDeviceIds is List
        ? rawDeviceIds
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
        : <String>{};
    deviceIds.add(normalizedDeviceId);

    await childDoc.reference.update(<String, dynamic>{
      'deviceIds': deviceIds.toList(growable: false),
      'deviceMetadata': metadataMap,
      'updatedAt': now,
    });
  }

  Future<void> verifyChildDevice({
    required String parentId,
    required String childId,
    required String deviceId,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Device ID cannot be empty.',
      );
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    final currentData = childDoc.data() ?? const <String, dynamic>{};
    final rawMetadata = currentData['deviceMetadata'];
    final metadataMap = rawMetadata is Map
        ? rawMetadata.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    final existingRaw = metadataMap[normalizedDeviceId];
    if (existingRaw is! Map) {
      throw StateError('Device metadata not found for $normalizedDeviceId');
    }

    final existingMap = existingRaw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final now = Timestamp.fromDate(DateTime.now());
    metadataMap[normalizedDeviceId] = <String, dynamic>{
      ...existingMap,
      'isVerified': true,
      'lastSeenAt': now,
    };

    await childDoc.reference.update(<String, dynamic>{
      'deviceMetadata': metadataMap,
      'updatedAt': now,
    });
  }

  Future<void> removeChildDevice({
    required String parentId,
    required String childId,
    required String deviceId,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Device ID cannot be empty.',
      );
    }

    final childDoc = await _loadOwnedChildDoc(
      parentId: parentId,
      childId: childId,
    );
    final currentData = childDoc.data() ?? const <String, dynamic>{};
    final rawMetadata = currentData['deviceMetadata'];
    final metadataMap = rawMetadata is Map
        ? rawMetadata.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    metadataMap.remove(normalizedDeviceId);

    final rawDeviceIds = currentData['deviceIds'];
    final deviceIds = rawDeviceIds is List
        ? rawDeviceIds
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty && item != normalizedDeviceId)
            .toList(growable: false)
        : const <String>[];

    await childDoc.reference.update(<String, dynamic>{
      'deviceIds': deviceIds,
      'deviceMetadata': metadataMap,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadOwnedChildDoc({
    required String parentId,
    required String childId,
  }) async {
    final childDoc = await _firestore.collection('children').doc(childId).get();
    if (!childDoc.exists) {
      throw StateError('Child profile not found.');
    }
    final data = childDoc.data();
    if (data == null || data['parentId'] != parentId) {
      throw StateError('You do not have access to this child profile.');
    }
    return childDoc;
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
      'policy': normalizedPolicy.toMap(),
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
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty || normalizedChildId.isEmpty) {
      return null;
    }

    await _loadOwnedChildDoc(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    );
    final doc = await _firestore
        .collection('children')
        .doc(normalizedChildId)
        .collection('effective_policy')
        .doc('current')
        .get();
    if (!doc.exists) {
      return null;
    }
    final data = doc.data();
    if (data == null) {
      return null;
    }
    return _dynamicInt(data['version']);
  }

  Future<void> deleteChild({
    required String parentId,
    required String childId,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final childRef = _firestore.collection('children').doc(childId);

    final childSnapshot = await childRef.get();
    if (!childSnapshot.exists) {
      return;
    }

    final childData = childSnapshot.data() ?? const <String, dynamic>{};
    final ownerId = (childData['parentId'] as String?)?.trim();
    if (ownerId != null && ownerId.isNotEmpty && ownerId != parentId.trim()) {
      throw StateError('Child profile does not belong to the provided parent.');
    }

    final deviceIds = <String>{};
    final rawDeviceIds = childData['deviceIds'];
    if (rawDeviceIds is List) {
      for (final raw in rawDeviceIds) {
        final deviceId = raw?.toString().trim() ?? '';
        if (deviceId.isNotEmpty) {
          deviceIds.add(deviceId);
        }
      }
    }

    try {
      final childDevices = await childRef.collection('devices').get();
      for (final doc in childDevices.docs) {
        final deviceId = doc.id.trim();
        if (deviceId.isNotEmpty) {
          deviceIds.add(deviceId);
        }
      }
    } catch (_) {
      // Best-effort discovery. Device IDs from child document may still exist.
    }

    if (deviceIds.isNotEmpty) {
      final batch = _firestore.batch();
      final now = FieldValue.serverTimestamp();
      for (final deviceId in deviceIds) {
        final commandRef = _firestore
            .collection('devices')
            .doc(deviceId)
            .collection('pendingCommands')
            .doc();
        batch.set(commandRef, <String, dynamic>{
          'commandId': commandRef.id,
          'parentId': parentId.trim(),
          'command': 'clearPairingAndStopProtection',
          'childId': childId.trim(),
          'reason': 'childProfileDeleted',
          'status': 'pending',
          'attempts': 0,
          'sentAt': now,
        });
      }
      batch.delete(childRef);
      await batch.commit();
      return;
    }

    await childRef.delete();
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
      final policy = _dynamicMap(data['policy']);
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
      final policy = _dynamicMap(data['policy']);
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
    final policy = _dynamicMap(childData['policy']);
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
    );
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
    final policy = _dynamicMap(childData['policy']);
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
    final policy = _dynamicMap(childData['policy']);
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
      );
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
    );
  }

  /// Submit a new access request from child profile.
  Future<String> submitAccessRequest(AccessRequest request) async {
    if (request.parentId.trim().isEmpty) {
      throw ArgumentError.value(
        request.parentId,
        'request.parentId',
        'Parent ID is required.',
      );
    }
    if (request.childId.trim().isEmpty) {
      throw ArgumentError.value(
        request.childId,
        'request.childId',
        'Child ID is required.',
      );
    }
    if (request.appOrSite.trim().isEmpty) {
      throw ArgumentError.value(
        request.appOrSite,
        'request.appOrSite',
        'App/site is required.',
      );
    }

    try {
      final docRef = await _firestore
          .collection('parents')
          .doc(request.parentId)
          .collection('access_requests')
          .add(request.toFirestore());
      await _crashlyticsService.setCustomKeys({
        'last_request_parent_id': request.parentId,
        'last_request_child_id': request.childId,
        'last_request_status': request.status.name,
      });
      return docRef.id;
    } catch (error, stackTrace) {
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'Failed to submit access request',
      );
      rethrow;
    }
  }

  /// Stream pending access requests for parent dashboard actions.
  Stream<List<AccessRequest>> getPendingRequestsStream(String parentId) {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    return _firestore
        .collection('parents')
        .doc(parentId)
        .collection('access_requests')
        .where('status', isEqualTo: RequestStatus.pending.name)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AccessRequest.fromFirestore(doc))
              .toList(),
        );
  }

  /// Stream unread bypass alert count for a parent.
  Stream<int> getUnreadBypassAlertCountStream(String parentId) {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final normalizedParentId = parentId.trim();
    return _firestore
        .collection('children')
        .where('parentId', isEqualTo: normalizedParentId)
        .snapshots()
        .asyncMap((snapshot) async {
      try {
        final deviceIds = <String>{};
        for (final childDoc in snapshot.docs) {
          final data = childDoc.data();
          final rawDeviceIds = data['deviceIds'];
          if (rawDeviceIds is List) {
            for (final rawDeviceId in rawDeviceIds) {
              final deviceId = rawDeviceId?.toString().trim() ?? '';
              if (deviceId.isNotEmpty) {
                deviceIds.add(deviceId);
              }
            }
          }

          final rawDeviceMetadata = data['deviceMetadata'];
          if (rawDeviceMetadata is Map) {
            for (final entry in rawDeviceMetadata.entries) {
              final deviceId = entry.key.toString().trim();
              if (deviceId.isNotEmpty) {
                deviceIds.add(deviceId);
              }
            }
          }
        }

        if (deviceIds.isEmpty) {
          return 0;
        }

        var unreadCount = 0;
        for (final deviceId in deviceIds) {
          final unreadSnapshot = await _firestore
              .collection('bypass_events')
              .doc(deviceId)
              .collection('events')
              .where('parentId', isEqualTo: normalizedParentId)
              .where('read', isEqualTo: false)
              .limit(120)
              .get();
          unreadCount += unreadSnapshot.docs.length;
        }
        return unreadCount;
      } catch (_) {
        return 0;
      }
    });
  }

  /// Stream recent access requests for a specific child profile.
  Stream<List<AccessRequest>> getChildRequestsStream({
    required String parentId,
    required String childId,
  }) {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    return _firestore
        .collection('parents')
        .doc(parentId)
        .collection('access_requests')
        .where('childId', isEqualTo: childId)
        .orderBy('requestedAt', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AccessRequest.fromFirestore(doc))
              .toList(),
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
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'Request ID is required.',
      );
    }
    if (status != RequestStatus.approved && status != RequestStatus.denied) {
      throw ArgumentError.value(
        status,
        'status',
        'Status must be approved or denied.',
      );
    }
    if (status != RequestStatus.approved && approvedDurationOverride != null) {
      throw ArgumentError.value(
        approvedDurationOverride,
        'approvedDurationOverride',
        'Duration override is only allowed for approved requests.',
      );
    }

    try {
      final requestRef = _firestore
          .collection('parents')
          .doc(parentId)
          .collection('access_requests')
          .doc(requestId);

      final requestSnapshot = await requestRef.get();
      if (!requestSnapshot.exists) {
        throw StateError('Access request not found.');
      }
      final requestData = requestSnapshot.data();
      final existingRequest = AccessRequest.fromFirestore(requestSnapshot);
      final rawChildId = requestData == null
          ? ''
          : (requestData['childId']?.toString().trim() ?? '');
      final childNotificationTargetId =
          existingRequest.childId.trim().isNotEmpty
              ? existingRequest.childId.trim()
              : rawChildId;

      DateTime? expiresAt;
      if (status == RequestStatus.approved) {
        int? minutes = approvedDurationOverride?.minutes;
        if (approvedDurationOverride == null) {
          final data = requestSnapshot.data();
          final minutesValue = data?['durationMinutes'];
          if (minutesValue is int) {
            minutes = minutesValue;
          } else if (minutesValue is num) {
            minutes = minutesValue.toInt();
          }
        }

        if (minutes != null && minutes > 0) {
          expiresAt = DateTime.now().add(Duration(minutes: minutes));
        }
      }

      final trimmedReply = reply?.trim();
      await requestRef.update({
        'status': status.name,
        'parentReply': (trimmedReply == null || trimmedReply.isEmpty)
            ? null
            : trimmedReply,
        'respondedAt': Timestamp.fromDate(DateTime.now()),
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      });

      if (childNotificationTargetId.isNotEmpty) {
        final childNotificationBody = _buildChildResponseNotificationBody(
          request: existingRequest,
          status: status,
          parentReply: trimmedReply,
          expiresAt: expiresAt,
        );
        await queueChildNotification(
          parentId: parentId,
          childId: childNotificationTargetId,
          title: status == RequestStatus.approved
              ? 'Request approved'
              : 'Request denied',
          body: childNotificationBody,
          route: '/child/status',
        );
      }

      await _syncNextDnsAccessLifecycle(
        parentId: parentId,
        request: existingRequest,
        status: status,
      );
      await _crashlyticsService.setCustomKeys({
        'last_request_id': requestId,
        'last_request_status': status.name,
      });
    } catch (error, stackTrace) {
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'Failed to respond to access request',
      );
      rethrow;
    }
  }

  /// Parent ends an active approved request immediately.
  ///
  /// This marks the request as expired so temporary DNS exceptions are removed
  /// on the next policy sync.
  Future<void> expireApprovedAccessRequestNow({
    required String parentId,
    required String requestId,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'Request ID is required.',
      );
    }

    try {
      final requestRef = _firestore
          .collection('parents')
          .doc(parentId)
          .collection('access_requests')
          .doc(requestId);

      final requestSnapshot = await requestRef.get();
      if (!requestSnapshot.exists) {
        throw StateError('Access request not found.');
      }

      final request = AccessRequest.fromFirestore(requestSnapshot);
      if (request.status != RequestStatus.approved) {
        throw StateError('Only approved requests can be ended early.');
      }

      final now = Timestamp.fromDate(DateTime.now());
      await requestRef.update({
        'status': RequestStatus.expired.name,
        'expiresAt': now,
        'expiredAt': now,
        'updatedAt': now,
      });
      await _syncNextDnsAccessLifecycle(
        parentId: parentId,
        request: request,
        status: RequestStatus.expired,
      );
      await _crashlyticsService.setCustomKeys({
        'last_request_id': requestId,
        'last_request_status': RequestStatus.expired.name,
      });
    } catch (error, stackTrace) {
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'Failed to end approved access request early',
      );
      rethrow;
    }
  }

  String _buildChildResponseNotificationBody({
    required AccessRequest request,
    required RequestStatus status,
    String? parentReply,
    DateTime? expiresAt,
  }) {
    final appOrSite = request.appOrSite.trim();
    final target = appOrSite.isEmpty ? 'your request' : appOrSite;
    final reply = parentReply?.trim();

    if (status == RequestStatus.approved) {
      final base = expiresAt == null
          ? '$target was approved.'
          : '$target was approved for ${request.duration.label}.';
      if (reply == null || reply.isEmpty) {
        return _truncateNotificationBody(base);
      }
      return _truncateNotificationBody('$base Parent message: $reply');
    }

    final base = '$target was not approved.';
    if (reply == null || reply.isEmpty) {
      return _truncateNotificationBody(base);
    }
    return _truncateNotificationBody('$base Parent message: $reply');
  }

  String _truncateNotificationBody(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 280) {
      return trimmed;
    }
    return '${trimmed.substring(0, 277)}...';
  }

  /// Stream all requests (pending + history) for parent.
  Stream<List<AccessRequest>> getAllRequestsStream(String parentId) {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    return _firestore
        .collection('parents')
        .doc(parentId)
        .collection('access_requests')
        .orderBy('requestedAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AccessRequest.fromFirestore(doc))
              .toList(),
        );
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
    final requests = await _getApprovedRequestsForExceptionEvaluation(
      parentId: parentId,
      childId: childId,
      limit: limit,
    );

    final now = DateTime.now();
    final exceptionDomains = <String>{};

    for (final request in requests) {
      final expiresAt = request.expiresAt;
      if (expiresAt != null && !expiresAt.isAfter(now)) {
        continue;
      }

      final domain = _normalizeExceptionDomain(request.appOrSite);
      if (domain != null) {
        exceptionDomains.add(domain);
      }
    }

    final ordered = exceptionDomains.toList()..sort();
    return ordered;
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
    final requests = await _getApprovedRequestsForExceptionEvaluation(
      parentId: parentId,
      childId: childId,
      limit: limit,
    );

    final now = DateTime.now();
    DateTime? nearest;
    for (final request in requests) {
      final expiresAt = request.expiresAt;
      if (expiresAt == null || !expiresAt.isAfter(now)) {
        continue;
      }
      if (nearest == null || expiresAt.isBefore(nearest)) {
        nearest = expiresAt;
      }
    }
    return nearest;
  }

  Future<List<AccessRequest>> _getApprovedRequestsForExceptionEvaluation({
    required String parentId,
    String? childId,
    required int limit,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Limit must be greater than 0.',
      );
    }

    final snapshot = await _firestore
        .collection('parents')
        .doc(parentId)
        .collection('access_requests')
        .where('status', isEqualTo: RequestStatus.approved.name)
        .orderBy('requestedAt', descending: true)
        .limit(limit)
        .get();

    final normalizedChildId = childId?.trim();
    final requests = <AccessRequest>[];

    for (final doc in snapshot.docs) {
      AccessRequest request;
      try {
        request = AccessRequest.fromFirestore(doc);
      } catch (_) {
        continue;
      }

      if (normalizedChildId != null &&
          normalizedChildId.isNotEmpty &&
          request.childId != normalizedChildId) {
        continue;
      }
      requests.add(request);
    }

    return requests;
  }

  Future<void> _syncNextDnsAccessLifecycle({
    required String parentId,
    required AccessRequest request,
    required RequestStatus status,
  }) async {
    final domain = _normalizeExceptionDomain(request.appOrSite);
    if (domain == null) {
      return;
    }

    final profileId = await _getChildNextDnsProfileId(
      parentId: parentId,
      childId: request.childId,
    );
    if (profileId == null || profileId.isEmpty) {
      return;
    }

    try {
      if (status == RequestStatus.approved) {
        await _nextDnsApiService.addToAllowlist(
          profileId: profileId,
          domain: domain,
        );
      } else if (status == RequestStatus.denied ||
          status == RequestStatus.expired) {
        await _nextDnsApiService.removeFromAllowlist(
          profileId: profileId,
          domain: domain,
        );
      }
    } catch (error, stackTrace) {
      await _crashlyticsService.logError(
        error,
        stackTrace,
        reason: 'Failed syncing NextDNS access pass lifecycle',
      );
    }
  }

  Future<String?> _getChildNextDnsProfileId({
    required String parentId,
    required String childId,
  }) async {
    final child = await getChild(parentId: parentId, childId: childId);
    final profileId = child?.nextDnsProfileId?.trim();
    if (profileId == null || profileId.isEmpty) {
      return null;
    }
    return profileId;
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
      final modeBlockedPackages = protectionEnabled
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
      final modeBlockedDomains = protectionEnabled
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
        'manualMode': normalizedManualMode,
        'pausedUntil': effectivePausedUntil == null
            ? null
            : Timestamp.fromDate(effectivePausedUntil),
        'sourceUpdatedAt': Timestamp.fromDate(sourceUpdatedAt),
        'eventEpochMs': version,
        'version': version,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _writeEffectivePolicyCurrent(
        parentId: normalizedParentId,
        childId: normalizedChildId,
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
  }) async {
    await _firestore
        .collection('children')
        .doc(childId)
        .collection('effective_policy')
        .doc('current')
        .set(
      <String, dynamic>{
        'parentId': parentId,
        'childId': childId,
        'version': version,
        'protectionEnabled': protectionEnabled,
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
        'manualMode': manualMode,
        'pausedUntil':
            pausedUntil == null ? null : Timestamp.fromDate(pausedUntil),
        'sourceUpdatedAt': Timestamp.fromDate(sourceUpdatedAt),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
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
          observed
              .map((domain) => domain.trim().toLowerCase())
              .where((domain) => domain.isNotEmpty),
        );
      }
    }
    return result;
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
      return null;
    }
    final mode = (manualMode['mode'] as String?)?.trim().toLowerCase();
    if (mode == null || mode.isEmpty) {
      return null;
    }
    final expiresAt = _dynamicDateTime(manualMode['expiresAt']);
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      return null;
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

  String? _normalizeExceptionDomain(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.isEmpty || value.contains(' ')) {
      return null;
    }

    if (value.startsWith('http://')) {
      value = value.substring('http://'.length);
    } else if (value.startsWith('https://')) {
      value = value.substring('https://'.length);
    }

    final slashIndex = value.indexOf('/');
    if (slashIndex >= 0) {
      value = value.substring(0, slashIndex);
    }

    final queryIndex = value.indexOf('?');
    if (queryIndex >= 0) {
      value = value.substring(0, queryIndex);
    }

    final hashIndex = value.indexOf('#');
    if (hashIndex >= 0) {
      value = value.substring(0, hashIndex);
    }

    if (value.startsWith('www.')) {
      value = value.substring(4);
    }
    while (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }

    final domainPattern = RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$');
    if (!domainPattern.hasMatch(value)) {
      return null;
    }

    return value;
  }
}
