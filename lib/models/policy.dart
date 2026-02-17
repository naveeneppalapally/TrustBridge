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
    final parsedSchedules = <Schedule>[];
    final rawSchedules = map['schedules'];
    if (rawSchedules is List) {
      for (final rawSchedule in rawSchedules) {
        final scheduleMap = _asMap(rawSchedule);
        if (scheduleMap.isEmpty) {
          continue;
        }
        try {
          parsedSchedules.add(Schedule.fromMap(scheduleMap));
        } catch (_) {
          // Skip malformed legacy schedule entries instead of failing policy load.
        }
      }
    }

    return Policy(
      blockedCategories: _stringList(map['blockedCategories']),
      blockedDomains: _stringList(map['blockedDomains']),
      schedules: parsedSchedules,
      safeSearchEnabled: _boolValue(map['safeSearchEnabled']),
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

  static bool _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return true;
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .where((item) => item != null)
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, dynamic>{};
  }
}
