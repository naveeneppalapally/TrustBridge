import 'package:cloud_firestore/cloud_firestore.dart';

enum RequestStatus {
  pending,
  approved,
  denied,
  expired;

  String get displayName {
    switch (this) {
      case RequestStatus.pending:
        return 'Waiting for response';
      case RequestStatus.approved:
        return 'Approved';
      case RequestStatus.denied:
        return 'Not approved';
      case RequestStatus.expired:
        return 'Expired';
    }
  }

  String get emoji {
    switch (this) {
      case RequestStatus.pending:
        return '⏳';
      case RequestStatus.approved:
        return '✅';
      case RequestStatus.denied:
        return '❌';
      case RequestStatus.expired:
        return '⏱️';
    }
  }
}

enum RequestDuration {
  fifteenMin,
  thirtyMin,
  oneHour,
  twoHours,
  untilScheduleEnds;

  String get label {
    switch (this) {
      case RequestDuration.fifteenMin:
        return '15 min';
      case RequestDuration.thirtyMin:
        return '30 min';
      case RequestDuration.oneHour:
        return '1 hour';
      case RequestDuration.twoHours:
        return '2 hours';
      case RequestDuration.untilScheduleEnds:
        return 'Until schedule ends';
    }
  }

  int? get minutes {
    switch (this) {
      case RequestDuration.fifteenMin:
        return 15;
      case RequestDuration.thirtyMin:
        return 30;
      case RequestDuration.oneHour:
        return 60;
      case RequestDuration.twoHours:
        return 120;
      case RequestDuration.untilScheduleEnds:
        return null;
    }
  }
}

class AccessRequest {
  const AccessRequest({
    required this.id,
    required this.childId,
    required this.parentId,
    required this.childNickname,
    required this.appOrSite,
    required this.duration,
    this.reason,
    required this.status,
    this.parentReply,
    required this.requestedAt,
    this.respondedAt,
    this.expiresAt,
  });

  final String id;
  final String childId;
  final String parentId;
  final String childNickname;
  final String appOrSite;
  final RequestDuration duration;
  final String? reason;
  final RequestStatus status;
  final String? parentReply;
  final DateTime requestedAt;
  final DateTime? respondedAt;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }
    return !expiry.isAfter(now);
  }

  RequestStatus effectiveStatus({DateTime? now}) {
    final reference = now ?? DateTime.now();
    if (status == RequestStatus.approved && isExpiredAt(reference)) {
      return RequestStatus.expired;
    }
    return status;
  }

  factory AccessRequest.create({
    required String childId,
    required String parentId,
    required String childNickname,
    required String appOrSite,
    required RequestDuration duration,
    String? reason,
  }) {
    return AccessRequest(
      id: '',
      childId: childId,
      parentId: parentId,
      childNickname: childNickname,
      appOrSite: appOrSite,
      duration: duration,
      reason: reason,
      status: RequestStatus.pending,
      requestedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'childId': childId,
      'parentId': parentId,
      'childNickname': childNickname,
      'appOrSite': appOrSite,
      'durationMinutes': duration.minutes,
      'durationLabel': duration.label,
      'reason': reason,
      'status': status.name,
      'parentReply': parentReply,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'respondedAt':
          respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    };
  }

  factory AccessRequest.fromFirestore(DocumentSnapshot doc) {
    final data = _asMap(doc.data());
    return AccessRequest(
      id: doc.id,
      childId: (data['childId'] as String?) ?? '',
      parentId: (data['parentId'] as String?) ?? '',
      childNickname: (data['childNickname'] as String?) ?? '',
      appOrSite: (data['appOrSite'] as String?) ?? '',
      duration: _parseDuration(
        durationLabel: data['durationLabel'] as String?,
        durationMinutes: data['durationMinutes'],
      ),
      reason: (data['reason'] as String?)?.trim().isEmpty == true
          ? null
          : (data['reason'] as String?),
      status: RequestStatus.values.firstWhere(
        (status) => status.name == data['status'],
        orElse: () => RequestStatus.pending,
      ),
      parentReply: (data['parentReply'] as String?)?.trim().isEmpty == true
          ? null
          : (data['parentReply'] as String?),
      requestedAt: _toDateTime(data['requestedAt']),
      respondedAt: _toNullableDateTime(data['respondedAt']),
      expiresAt: _toNullableDateTime(data['expiresAt']),
    );
  }

  static RequestDuration _parseDuration({
    required String? durationLabel,
    required Object? durationMinutes,
  }) {
    if (durationLabel != null && durationLabel.trim().isNotEmpty) {
      for (final duration in RequestDuration.values) {
        if (duration.label == durationLabel) {
          return duration;
        }
      }
    }

    final minutesValue = _toNullableInt(durationMinutes);
    for (final duration in RequestDuration.values) {
      if (duration.minutes == minutesValue) {
        return duration;
      }
    }
    return RequestDuration.thirtyMin;
  }

  static DateTime _toDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _toNullableDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static int? _toNullableInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }
}
