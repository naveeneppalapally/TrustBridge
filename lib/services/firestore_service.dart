import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:trustbridge_app/models/child_profile.dart';

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
        },
        'fcmToken': null,
      },
      SetOptions(merge: true),
    );
  }

  Future<Map<String, dynamic>?> getParentProfile(String parentId) async {
    final snapshot = await _firestore.collection('parents').doc(parentId).get();
    return snapshot.data();
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
      final children =
          snapshot.docs.map((doc) => ChildProfile.fromFirestore(doc)).toList();
      children.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return children;
    });
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
    final snapshot = await childRef.get();
    final data = snapshot.data();
    if (data != null && data['parentId'] != parentId) {
      throw StateError('Child does not belong to parent $parentId.');
    }

    await childRef.update({
      'nickname': normalizedNickname,
      'ageBand': child.ageBand.value,
      'deviceIds': child.deviceIds,
      'policy': child.policy.toMap(),
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
}
