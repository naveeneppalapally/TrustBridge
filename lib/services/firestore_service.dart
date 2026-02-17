import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/support_ticket.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> ensureParentProfile({
    required String parentId,
    required String? phoneNumber,
  }) async {
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
      if (data.containsKey('onboardingComplete')) {
        mergedPreferences['onboardingComplete'] =
            data['onboardingComplete'] == true;
      }
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

    await _firestore.collection('children').doc(child.id).set({
      ...child.toFirestore(),
      'parentId': parentId,
    });

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
    return getChildren(parentId);
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

    final docRef = await _firestore
        .collection('parents')
        .doc(request.parentId)
        .collection('access_requests')
        .add(request.toFirestore());
    return docRef.id;
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
      final data = requestSnapshot.data();
      final minutesValue = data?['durationMinutes'];
      int? minutes;
      if (minutesValue is int) {
        minutes = minutesValue;
      } else if (minutesValue is num) {
        minutes = minutesValue.toInt();
      }

      if (minutes != null && minutes > 0) {
        expiresAt = DateTime.now().add(Duration(minutes: minutes));
      }
    }

    final trimmedReply = reply?.trim();
    await requestRef.update({
      'status': status.name,
      'parentReply':
          (trimmedReply == null || trimmedReply.isEmpty) ? null : trimmedReply,
      'respondedAt': Timestamp.fromDate(DateTime.now()),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
    });
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
}
