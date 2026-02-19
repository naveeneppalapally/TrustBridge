import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/support_ticket.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';
import 'package:trustbridge_app/services/performance_service.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
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
      'body': body.trim(),
      'route': route.trim(),
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

    final childRef = _firestore.collection('children').doc(child.id);
    await childRef.update({
      'nickname': normalizedNickname,
      'ageBand': child.ageBand.value,
      'deviceIds': child.deviceIds,
      'policy': child.policy.toMap(),
      'pausedUntil': child.pausedUntil != null
          ? Timestamp.fromDate(child.pausedUntil!)
          : null,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
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

    await _firestore.collection('children').doc(childId).delete();
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
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, <String, dynamic>{
        'pausedUntil': Timestamp.fromDate(pausedUntil),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    }
    await batch.commit();
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

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, <String, dynamic>{
        'pausedUntil': null,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    }
    await batch.commit();
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
