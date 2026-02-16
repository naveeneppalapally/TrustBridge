import 'child_profile.dart';
import 'schedule.dart';

class Policy {
  final List<String> blockedCategories;
  final List<String> blockedDomains;
  final List<Schedule> schedules;
  final bool safeSearchEnabled;

  Policy({
    required this.blockedCategories,
    required this.blockedDomains,
    required this.schedules,
    this.safeSearchEnabled = true,
  });

  static Policy presetForAgeBand(AgeBand band) {
    switch (band) {
      case AgeBand.young:
        return Policy(
          blockedCategories: const [
            'social-networks',
            'dating',
            'gambling',
            'weapons',
            'drugs',
          ],
          blockedDomains: const [],
          schedules: [
            Schedule.bedtime(startTime: '20:00', endTime: '07:00'),
            Schedule.schoolTime(startTime: '09:00', endTime: '15:00'),
          ],
          safeSearchEnabled: true,
        );
      case AgeBand.middle:
        return Policy(
          blockedCategories: const [
            'dating',
            'gambling',
            'weapons',
            'drugs',
          ],
          blockedDomains: const [],
          schedules: [
            Schedule.bedtime(startTime: '21:30', endTime: '07:00'),
            Schedule.schoolTime(startTime: '09:00', endTime: '15:00'),
          ],
          safeSearchEnabled: true,
        );
      case AgeBand.teen:
        return Policy(
          blockedCategories: const [
            'gambling',
            'weapons',
            'drugs',
          ],
          blockedDomains: const [],
          schedules: [
            Schedule.bedtime(startTime: '23:00', endTime: '07:00'),
          ],
          safeSearchEnabled: false,
        );
    }
  }

  factory Policy.fromMap(Map<String, dynamic> map) {
    return Policy(
      blockedCategories: List<String>.from(map['blockedCategories'] ?? []),
      blockedDomains: List<String>.from(map['blockedDomains'] ?? []),
      schedules: (map['schedules'] as List<dynamic>?)
              ?.map((s) => Schedule.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      safeSearchEnabled: map['safeSearchEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'blockedCategories': blockedCategories,
      'blockedDomains': blockedDomains,
      'schedules': schedules.map((s) => s.toMap()).toList(),
      'safeSearchEnabled': safeSearchEnabled,
    };
  }

  Policy copyWith({
    List<String>? blockedCategories,
    List<String>? blockedDomains,
    List<Schedule>? schedules,
    bool? safeSearchEnabled,
  }) {
    return Policy(
      blockedCategories: blockedCategories ?? this.blockedCategories,
      blockedDomains: blockedDomains ?? this.blockedDomains,
      schedules: schedules ?? this.schedules,
      safeSearchEnabled: safeSearchEnabled ?? this.safeSearchEnabled,
    );
  }
}
