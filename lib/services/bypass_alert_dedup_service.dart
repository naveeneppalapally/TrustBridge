import 'package:cloud_firestore/cloud_firestore.dart';

/// Alert decision payload for bypass notification flow.
class AlertDecision {
  const AlertDecision({
    required this.shouldSend,
    required this.isEscalated,
    this.escalationMessage,
  });

  final bool shouldSend;
  final bool isEscalated;
  final String? escalationMessage;
}

/// Deduplicates bypass alerts and escalates repeated attempts.
class BypassAlertDedupService {
  BypassAlertDedupService({
    FirebaseFirestore? firestore,
    DateTime Function()? nowProvider,
  })  : _firestoreOverride = firestore,
        _nowProvider = nowProvider ?? DateTime.now;

  static const Duration _dedupWindow = Duration(minutes: 10);
  static const Duration _escalationWindow = Duration(hours: 1);

  final FirebaseFirestore? _firestoreOverride;
  final DateTime Function() _nowProvider;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Returns true if an alert should be sent for this device/type.
  Future<bool> shouldAlert(String deviceId, String eventType) async {
    if (deviceId.trim().isEmpty || eventType.trim().isEmpty) {
      return false;
    }
    final doc = await _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('lastAlerts')
        .doc(eventType)
        .get();
    if (!doc.exists) {
      return true;
    }
    final data = doc.data() ?? const <String, dynamic>{};
    final lastAt = _readEpochDateTime(data['lastAlertAtEpochMs']) ??
        _readDateTime(data['lastAlertAt']);
    if (lastAt == null) {
      return true;
    }
    return _nowProvider().difference(lastAt) >= _dedupWindow;
  }

  /// Records an alert send timestamp for dedup.
  Future<void> recordAlert(String deviceId, String eventType) async {
    if (deviceId.trim().isEmpty || eventType.trim().isEmpty) {
      return;
    }
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('lastAlerts')
        .doc(eventType)
        .set(
      <String, dynamic>{
        'lastAlertAt': FieldValue.serverTimestamp(),
        'lastAlertAtEpochMs': _nowProvider().millisecondsSinceEpoch,
        'eventType': eventType,
      },
      SetOptions(merge: true),
    );
  }

  /// Returns dedup + escalation decision for this alert candidate.
  Future<AlertDecision> getAlertDecision(String deviceId, String eventType) async {
    final shouldSendNow = await shouldAlert(deviceId, eventType);
    if (!shouldSendNow) {
      return const AlertDecision(
        shouldSend: false,
        isEscalated: false,
      );
    }

    final cutoff = _nowProvider().subtract(_escalationWindow).millisecondsSinceEpoch;
    final recent = await _firestore
        .collection('bypass_events')
        .doc(deviceId)
        .collection('events')
        .where('type', isEqualTo: eventType)
        .where('timestampEpochMs', isGreaterThanOrEqualTo: cutoff)
        .get();
    final isEscalated = recent.docs.length >= 3;
    return AlertDecision(
      shouldSend: true,
      isEscalated: isEscalated,
      escalationMessage:
          isEscalated ? 'Repeated bypass attempts detected' : null,
    );
  }

  DateTime? _readDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return null;
  }

  DateTime? _readEpochDateTime(Object? raw) {
    if (raw is int && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is num && raw.toInt() > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    return null;
  }
}
