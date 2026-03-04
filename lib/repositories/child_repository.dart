import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/models/child_profile.dart';

class ChildRepository {
  ChildRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> childRef(String childId) {
    return _firestore.collection('children').doc(childId.trim());
  }

  Query<Map<String, dynamic>> childrenByParentQuery(String parentId) {
    return _firestore
        .collection('children')
        .where('parentId', isEqualTo: parentId.trim());
  }

  Future<void> createChildProfile({
    required String parentId,
    required ChildProfile child,
  }) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (child.id.trim().isEmpty) {
      throw ArgumentError.value(child.id, 'child.id', 'Child ID is required.');
    }

    await childRef(child.id).set(<String, dynamic>{
      ...child.toFirestore(includePolicy: false),
      'parentId': normalizedParentId,
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getChildDoc(
    String childId,
  ) async {
    return childRef(childId).get();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchChildDoc(
    String childId, {
    bool includeMetadataChanges = true,
  }) {
    return childRef(childId).snapshots(
      includeMetadataChanges: includeMetadataChanges,
    );
  }

  Future<QuerySnapshot<Map<String, dynamic>>> getChildrenDocsByParent(
    String parentId, {
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query = childrenByParentQuery(parentId);
    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }
    return query.get();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchChildrenByParent(
    String parentId,
  ) {
    return childrenByParentQuery(parentId).snapshots();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> loadOwnedChildDoc({
    required String parentId,
    required String childId,
  }) async {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (normalizedChildId.isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final childDoc = await childRef(normalizedChildId).get();
    if (!childDoc.exists) {
      throw StateError('Child profile not found.');
    }
    final data = childDoc.data();
    if (data == null || data['parentId'] != normalizedParentId) {
      throw StateError('You do not have access to this child profile.');
    }
    return childDoc;
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

    await loadOwnedChildDoc(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    );
    final doc = await childRef(normalizedChildId)
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
    final rawVersion = data['version'];
    if (rawVersion is int) {
      return rawVersion;
    }
    if (rawVersion is num) {
      return rawVersion.toInt();
    }
    if (rawVersion is String) {
      return int.tryParse(rawVersion);
    }
    return null;
  }

  Future<bool> deleteChildAndQueueUnpairCommands({
    required String parentId,
    required String childId,
  }) async {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty) {
      throw ArgumentError.value(parentId, 'parentId', 'Parent ID is required.');
    }
    if (normalizedChildId.isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child ID is required.');
    }

    final childDocumentRef = childRef(normalizedChildId);
    final childSnapshot = await childDocumentRef.get();
    if (!childSnapshot.exists) {
      return false;
    }

    final childData = childSnapshot.data() ?? const <String, dynamic>{};
    final ownerId = (childData['parentId'] as String?)?.trim();
    if (ownerId != null && ownerId.isNotEmpty && ownerId != normalizedParentId) {
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
      final childDevices = await childDocumentRef.collection('devices').get();
      for (final doc in childDevices.docs) {
        final deviceId = doc.id.trim();
        if (deviceId.isNotEmpty) {
          deviceIds.add(deviceId);
        }
      }
    } catch (_) {
      // Best-effort child-device discovery.
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
          'parentId': normalizedParentId,
          'command': 'clearPairingAndStopProtection',
          'childId': normalizedChildId,
          'reason': 'childProfileDeleted',
          'status': 'pending',
          'attempts': 0,
          'sentAt': now,
        });
      }
      batch.delete(childDocumentRef);
      await batch.commit();
      return true;
    }

    await childDocumentRef.delete();
    return true;
  }
}
