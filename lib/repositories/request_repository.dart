import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/repositories/parent_repository.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';

class RequestRepository {
  RequestRepository({
    required FirebaseFirestore firestore,
    required CrashlyticsService crashlyticsService,
    required NextDnsApiService nextDnsApiService,
    required ParentRepository parentRepository,
  })  : _firestore = firestore,
        _crashlyticsService = crashlyticsService,
        _nextDnsApiService = nextDnsApiService,
        _parentRepository = parentRepository;

  final FirebaseFirestore _firestore;
  final CrashlyticsService _crashlyticsService;
  final NextDnsApiService _nextDnsApiService;
  final ParentRepository _parentRepository;

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
        await _parentRepository.queueChildNotification(
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
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty || normalizedChildId.isEmpty) {
      return null;
    }

    final snapshot = await _firestore
        .collection('children')
        .doc(normalizedChildId)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    final data = snapshot.data();
    final ownerParentId = data?['parentId']?.toString().trim() ?? '';
    if (ownerParentId != normalizedParentId) {
      return null;
    }

    final profileId = data?['nextDnsProfileId']?.toString().trim();
    if (profileId == null || profileId.isEmpty) {
      return null;
    }
    return profileId;
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
