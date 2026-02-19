import 'package:cloud_firestore/cloud_firestore.dart';

class ChildDeviceRecord {
  const ChildDeviceRecord({
    required this.deviceId,
    required this.alias,
    this.model,
    this.manufacturer,
    this.linkedNextDnsProfileId,
    this.isVerified = false,
    this.createdAt,
    this.lastSeenAt,
  });

  final String deviceId;
  final String alias;
  final String? model;
  final String? manufacturer;
  final String? linkedNextDnsProfileId;
  final bool isVerified;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;

  ChildDeviceRecord copyWith({
    String? alias,
    String? model,
    String? manufacturer,
    String? linkedNextDnsProfileId,
    bool? isVerified,
    DateTime? createdAt,
    DateTime? lastSeenAt,
  }) {
    return ChildDeviceRecord(
      deviceId: deviceId,
      alias: alias ?? this.alias,
      model: model ?? this.model,
      manufacturer: manufacturer ?? this.manufacturer,
      linkedNextDnsProfileId:
          linkedNextDnsProfileId ?? this.linkedNextDnsProfileId,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'alias': alias,
      'model': model,
      'manufacturer': manufacturer,
      'linkedNextDnsProfileId': linkedNextDnsProfileId,
      'isVerified': isVerified,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (lastSeenAt != null) 'lastSeenAt': Timestamp.fromDate(lastSeenAt!),
    };
  }

  factory ChildDeviceRecord.fromMap(
    String deviceId,
    Map<String, dynamic> map,
  ) {
    return ChildDeviceRecord(
      deviceId: deviceId,
      alias: _stringOrFallback(map['alias'], fallback: deviceId),
      model: _nullableString(map['model']),
      manufacturer: _nullableString(map['manufacturer']),
      linkedNextDnsProfileId: _nullableString(map['linkedNextDnsProfileId']),
      isVerified: map['isVerified'] == true,
      createdAt: _toDateTime(map['createdAt']),
      lastSeenAt: _toDateTime(map['lastSeenAt']),
    );
  }

  static String _stringOrFallback(
    Object? raw, {
    required String fallback,
  }) {
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return fallback;
  }

  static String? _nullableString(Object? raw) {
    if (raw is String) {
      final value = raw.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static DateTime? _toDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return null;
  }
}
