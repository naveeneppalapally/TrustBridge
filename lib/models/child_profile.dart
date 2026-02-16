import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'policy.dart';

enum AgeBand {
  young('6-9'),
  middle('10-13'),
  teen('14-17');

  final String value;
  const AgeBand(this.value);

  static AgeBand fromString(String value) {
    return AgeBand.values.firstWhere((e) => e.value == value);
  }
}

class ChildProfile {
  final String id;
  final String nickname;
  final AgeBand ageBand;
  final List<String> deviceIds;
  final Policy policy;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChildProfile({
    required this.id,
    required this.nickname,
    required this.ageBand,
    required this.deviceIds,
    required this.policy,
    required this.createdAt,
    required this.updatedAt,
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
      deviceIds: [],
      policy: Policy.presetForAgeBand(ageBand),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory ChildProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChildProfile(
      id: doc.id,
      nickname: data['nickname'] as String,
      ageBand: AgeBand.fromString(data['ageBand'] as String),
      deviceIds: List<String>.from(data['deviceIds'] ?? []),
      policy: Policy.fromMap(data['policy'] as Map<String, dynamic>),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nickname': nickname,
      'ageBand': ageBand.value,
      'deviceIds': deviceIds,
      'policy': policy.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  ChildProfile copyWith({
    String? nickname,
    AgeBand? ageBand,
    Policy? policy,
  }) {
    return ChildProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      ageBand: ageBand ?? this.ageBand,
      deviceIds: deviceIds,
      policy: policy ?? this.policy,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
