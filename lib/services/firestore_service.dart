import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> ensureParentProfile({
    required String parentId,
    required String? phoneNumber,
  }) async {
    final parentRef = _firestore.collection('parents').doc(parentId);
    final existing = await parentRef.get();
    if (existing.exists) {
      return;
    }

    await parentRef.set({
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
      },
      'fcmToken': null,
    });
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
}
