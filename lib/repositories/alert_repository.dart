import 'package:cloud_firestore/cloud_firestore.dart';

class AlertRepository {
  AlertRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

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
}
