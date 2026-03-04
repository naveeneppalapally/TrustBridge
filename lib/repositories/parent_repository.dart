import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/models/dashboard_state.dart';
import 'package:trustbridge_app/models/support_ticket.dart';

class ParentRepository {
  ParentRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

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

  Stream<DashboardStateSnapshot?> watchDashboardState(String parentId) {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return Stream<DashboardStateSnapshot?>.value(null);
    }

    return _firestore
        .collection('parents')
        .doc(normalizedParentId)
        .collection('dashboard_state')
        .doc('current')
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      final data = snapshot.data();
      if (data == null || data.isEmpty) {
        return null;
      }
      return DashboardStateSnapshot.fromMap(data);
    });
  }

  Future<void> updateParentContactInfo({
    required String parentId,
    String? email,
    String? displayName,
  }) async {
    if (parentId.trim().isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }

    final updates = <String, dynamic>{};
    if (email != null) {
      final normalized = email.trim();
      if (normalized.isNotEmpty) {
        updates['email'] = normalized;
      }
    }
    if (displayName != null) {
      final normalized = displayName.trim();
      if (normalized.isNotEmpty) {
        updates['displayName'] = normalized;
      }
    }
    if (updates.isEmpty) {
      return;
    }

    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore.collection('parents').doc(parentId).set(
          updates,
          SetOptions(merge: true),
        );
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
            name: 'ParentRepository',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tickets;
    });
  }

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
      duplicateClusters.sort((a, b) => b.value.length.compareTo(a.value.length));

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
        name: 'ParentRepository',
        error: error,
        stackTrace: stackTrace,
      );
      return <String, dynamic>{};
    }
  }

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

  String _truncateNotificationBody(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 280) {
      return trimmed;
    }
    return '${trimmed.substring(0, 277)}...';
  }
}
