import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/firestore_paths.dart';
import '../models/child_profile.dart';
import 'pairing_service.dart';

/// Carries the resolved child and parent context needed to send a request.
class RequestAccessContext {
  const RequestAccessContext({
    required this.parentId,
    required this.childId,
    required this.childNickname,
  });

  final String? parentId;
  final String? childId;
  final String? childNickname;
}

/// Handles loading child request context and writing access requests.
class RequestAccessService {
  RequestAccessService({
    FirebaseFirestore? firestore,
    PairingService? pairingService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _pairingService = pairingService ?? PairingService();

  final FirebaseFirestore _firestore;
  final PairingService _pairingService;

  /// Resolves the paired parent, child, and child nickname for the request UI.
  Future<RequestAccessContext> resolveContext({
    String? parentId,
    String? childId,
    String? childNickname,
  }) async {
    var resolvedParentId = parentId?.trim();
    var resolvedChildId = childId?.trim();
    var resolvedChildNickname = childNickname?.trim();

    if (resolvedParentId == null || resolvedParentId.isEmpty) {
      resolvedParentId = await _pairingService.getPairedParentId();
    }
    if (resolvedChildId == null || resolvedChildId.isEmpty) {
      resolvedChildId = await _pairingService.getPairedChildId();
    }

    if ((resolvedChildNickname == null || resolvedChildNickname.isEmpty) &&
        resolvedChildId != null &&
        resolvedChildId.isNotEmpty) {
      final childDoc = await _firestore
          .collection(FirestorePaths.childrenCollection)
          .doc(resolvedChildId)
          .get();
      if (childDoc.exists) {
        final profile = ChildProfile.fromFirestore(childDoc);
        resolvedChildNickname = profile.nickname;
        resolvedParentId ??=
            (childDoc.data()?['parentId'] as String?)?.trim();
      }
    }

    return RequestAccessContext(
      parentId: _normaliseNullable(resolvedParentId),
      childId: _normaliseNullable(resolvedChildId),
      childNickname: _normaliseNullable(resolvedChildNickname),
    );
  }

  /// Writes the child request and queue notification documents.
  Future<void> sendAccessRequest({
    required String parentId,
    required String childId,
    required String childNickname,
    required String requestedApp,
    required String durationLabel,
    required int durationMinutes,
    String? reason,
  }) async {
    final requestId = const Uuid().v4();
    final trimmedReason = reason?.trim();

    await _firestore
        .collection(FirestorePaths.parentsCollection)
        .doc(parentId)
        .collection(FirestorePaths.accessRequestsCollection)
        .doc(requestId)
        .set({
      'childId': childId,
      'parentId': parentId,
      'childNickname': childNickname,
      'appOrSite': requestedApp,
      'durationLabel': durationLabel,
      'durationMinutes': durationMinutes,
      'reason': trimmedReason == null || trimmedReason.isEmpty
          ? null
          : trimmedReason,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
      'parentReply': null,
      'respondedAt': null,
      'expiresAt': null,
    });

    await _firestore.collection(FirestorePaths.notificationQueueCollection).add({
      'parentId': parentId,
      'childId': childId,
      'title': '$childNickname wants access',
      'body': '$childNickname requested $requestedApp for $durationLabel.',
      'route': '/parent-requests',
      'eventType': 'access_request',
      'processed': false,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  String? _normaliseNullable(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
