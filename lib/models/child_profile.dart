import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'child_device_record.dart';
import 'policy.dart';

enum AgeBand {
  young('6-9'),
  middle('10-13'),
  teen('14-17');

  final String value;
  const AgeBand(this.value);

  static AgeBand fromString(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return AgeBand.young;
    }

    for (final band in AgeBand.values) {
      if (band.value == normalized || band.name == normalized) {
        return band;
      }
    }

    return AgeBand.young;
  }
}

class ChildProfile {
  final String id;
  final String nickname;
  final AgeBand ageBand;
  final List<String> deviceIds;
  final String? nextDnsProfileId;
  final Map<String, ChildDeviceRecord> deviceMetadata;
  final Map<String, dynamic> nextDnsControls;
  final Policy policy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? pausedUntil;
  final Map<String, dynamic>? manualMode;

  ChildProfile({
    required this.id,
    required this.nickname,
    required this.ageBand,
    required this.deviceIds,
    this.nextDnsProfileId,
    this.deviceMetadata = const {},
    this.nextDnsControls = const {},
    required this.policy,
    required this.createdAt,
    required this.updatedAt,
    this.pausedUntil,
    this.manualMode,
  });

  factory ChildProfile.create({
    required String nickname,
    required AgeBand ageBand,
  }) {
    final now = DateTime.now();
    return ChildProfile(
      id: const Uuid().v4(),
      nickname: nickname,
      ageBand: ageBand,
      deviceIds: const <String>[],
      nextDnsProfileId: null,
      deviceMetadata: const <String, ChildDeviceRecord>{},
      nextDnsControls: const <String, dynamic>{},
      policy: Policy.presetForAgeBand(ageBand),
      createdAt: now,
      updatedAt: now,
      pausedUntil: null,
      manualMode: null,
    );
  }

  factory ChildProfile.fromFirestore(DocumentSnapshot doc) {
    final data = _asMap(doc.data());
    return ChildProfile(
      id: doc.id,
      nickname: _stringValue(data['nickname']),
      ageBand: AgeBand.fromString(data['ageBand']?.toString()),
      deviceIds: _stringList(data['deviceIds']),
      nextDnsProfileId: _nullableString(data['nextDnsProfileId']),
      deviceMetadata: _deviceMetadataMap(data['deviceMetadata']),
      nextDnsControls: _asMap(data['nextDnsControls']),
      policy: Policy.fromMap(_asMap(data['policy'])),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      pausedUntil: _toNullableDateTime(data['pausedUntil']),
      manualMode: _manualModeMap(data['manualMode']),
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'nickname': nickname,
      'ageBand': ageBand.value,
      'deviceIds': deviceIds,
      'policy': policy.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (nextDnsProfileId != null && nextDnsProfileId!.trim().isNotEmpty)
        'nextDnsProfileId': nextDnsProfileId!.trim(),
      if (deviceMetadata.isNotEmpty)
        'deviceMetadata': deviceMetadata.map(
          (deviceId, metadata) => MapEntry(deviceId, metadata.toMap()),
        ),
      if (nextDnsControls.isNotEmpty) 'nextDnsControls': nextDnsControls,
    };
    if (pausedUntil != null) {
      map['pausedUntil'] = Timestamp.fromDate(pausedUntil!);
    }
    final serializedManualMode =
        manualMode == null ? null : _manualModeToFirestore(manualMode!);
    if (serializedManualMode != null) {
      map['manualMode'] = serializedManualMode;
    }
    return map;
  }

  ChildProfile copyWith({
    String? nickname,
    AgeBand? ageBand,
    List<String>? deviceIds,
    String? nextDnsProfileId,
    bool clearNextDnsProfileId = false,
    Map<String, ChildDeviceRecord>? deviceMetadata,
    Map<String, dynamic>? nextDnsControls,
    Policy? policy,
    DateTime? pausedUntil,
    bool clearPausedUntil = false,
    Map<String, dynamic>? manualMode,
    bool clearManualMode = false,
  }) {
    return ChildProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      ageBand: ageBand ?? this.ageBand,
      deviceIds: deviceIds ?? this.deviceIds,
      nextDnsProfileId: clearNextDnsProfileId
          ? null
          : (nextDnsProfileId ?? this.nextDnsProfileId),
      deviceMetadata: deviceMetadata ?? this.deviceMetadata,
      nextDnsControls: nextDnsControls ?? this.nextDnsControls,
      policy: policy ?? this.policy,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      pausedUntil: clearPausedUntil ? null : (pausedUntil ?? this.pausedUntil),
      manualMode: clearManualMode ? null : (manualMode ?? this.manualMode),
    );
  }

  static DateTime _toDateTime(Object? rawValue) {
    if (rawValue is Timestamp) {
      return rawValue.toDate();
    }
    if (rawValue is DateTime) {
      return rawValue;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _toNullableDateTime(Object? rawValue) {
    if (rawValue == null) {
      return null;
    }
    if (rawValue is Timestamp) {
      return rawValue.toDate();
    }
    if (rawValue is DateTime) {
      return rawValue;
    }
    return null;
  }

  static Map<String, dynamic> _asMap(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }
    if (rawValue is Map) {
      return rawValue.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return <String, dynamic>{};
  }

  static String _stringValue(Object? rawValue) {
    if (rawValue is String) {
      return rawValue;
    }
    return rawValue?.toString() ?? '';
  }

  static String? _nullableString(Object? rawValue) {
    if (rawValue is String) {
      final value = rawValue.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static List<String> _stringList(Object? rawValue) {
    if (rawValue is List) {
      return rawValue
          .where((item) => item != null)
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static Map<String, ChildDeviceRecord> _deviceMetadataMap(Object? rawValue) {
    if (rawValue is! Map) {
      return const <String, ChildDeviceRecord>{};
    }

    final result = <String, ChildDeviceRecord>{};
    for (final entry in rawValue.entries) {
      final deviceId = entry.key.toString().trim();
      if (deviceId.isEmpty) {
        continue;
      }
      final rawMap = _asMap(entry.value);
      if (rawMap.isEmpty) {
        continue;
      }
      result[deviceId] = ChildDeviceRecord.fromMap(deviceId, rawMap);
    }
    return result;
  }

  static Map<String, dynamic>? _manualModeMap(Object? rawValue) {
    final raw = _asMap(rawValue);
    if (raw.isEmpty) {
      return null;
    }
    final mode = _nullableString(raw['mode'])?.toLowerCase();
    if (mode == null) {
      return null;
    }
    final setAt = _toNullableDateTime(raw['setAt']);
    final expiresAt = _toNullableDateTime(raw['expiresAt']);
    return <String, dynamic>{
      'mode': mode,
      if (setAt != null) 'setAt': setAt,
      if (expiresAt != null) 'expiresAt': expiresAt,
    };
  }

  static Map<String, dynamic>? _manualModeToFirestore(
    Map<String, dynamic> rawMode,
  ) {
    if (rawMode.isEmpty) {
      return null;
    }
    final mode = _nullableString(rawMode['mode'])?.toLowerCase();
    if (mode == null) {
      return null;
    }
    final result = <String, dynamic>{
      'mode': mode,
    };
    final setAt = _toNullableDateTime(rawMode['setAt']);
    if (setAt != null) {
      result['setAt'] = Timestamp.fromDate(setAt);
    }
    final expiresAt = _toNullableDateTime(rawMode['expiresAt']);
    if (expiresAt != null) {
      result['expiresAt'] = Timestamp.fromDate(expiresAt);
    }
    return result;
  }
}
