import 'package:uuid/uuid.dart';

enum Day {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday;

  static Day fromDateTime(DateTime date) {
    return Day.values[date.weekday - 1];
  }
}

enum ScheduleType {
  bedtime,
  school,
  homework,
  custom;
}

enum ScheduleAction {
  blockAll,
  blockDistracting,
  allowAll;
}

class Schedule {
  final String id;
  final String name;
  final ScheduleType type;
  final List<Day> days;
  final String startTime;
  final String endTime;
  final bool enabled;
  final ScheduleAction action;

  Schedule({
    required this.id,
    required this.name,
    required this.type,
    required this.days,
    required this.startTime,
    required this.endTime,
    this.enabled = true,
    required this.action,
  });

  factory Schedule.bedtime({
    required String startTime,
    required String endTime,
  }) {
    return Schedule(
      id: const Uuid().v4(),
      name: 'Bedtime',
      type: ScheduleType.bedtime,
      days: Day.values,
      startTime: startTime,
      endTime: endTime,
      action: ScheduleAction.blockAll,
    );
  }

  factory Schedule.schoolTime({
    required String startTime,
    required String endTime,
  }) {
    return Schedule(
      id: const Uuid().v4(),
      name: 'School Time',
      type: ScheduleType.school,
      days: const [
        Day.monday,
        Day.tuesday,
        Day.wednesday,
        Day.thursday,
        Day.friday,
      ],
      startTime: startTime,
      endTime: endTime,
      action: ScheduleAction.blockDistracting,
    );
  }

  factory Schedule.fromMap(Map<String, dynamic> map) {
    final type = _parseScheduleType(map['type']);
    final action = _parseScheduleAction(map['action'], type);

    return Schedule(
      id: _stringValue(map['id'], fallback: const Uuid().v4()),
      name: _stringValue(map['name'], fallback: _defaultNameForType(type)),
      type: type,
      days: _parseDays(map['days']),
      startTime: _stringValue(map['startTime'], fallback: '00:00'),
      endTime: _stringValue(map['endTime'], fallback: '00:00'),
      enabled: _boolValue(map['enabled'], fallback: true),
      action: action,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'days': days.map((d) => d.name).toList(),
      'startTime': startTime,
      'endTime': endTime,
      'enabled': enabled,
      'action': action.name,
    };
  }

  static ScheduleType _parseScheduleType(Object? rawValue) {
    final candidate = rawValue?.toString();
    if (candidate != null) {
      for (final type in ScheduleType.values) {
        if (type.name == candidate) {
          return type;
        }
      }
    }
    return ScheduleType.custom;
  }

  static ScheduleAction _parseScheduleAction(
    Object? rawValue,
    ScheduleType type,
  ) {
    final candidate = rawValue?.toString();
    if (candidate != null) {
      for (final action in ScheduleAction.values) {
        if (action.name == candidate) {
          return action;
        }
      }
    }

    switch (type) {
      case ScheduleType.bedtime:
        return ScheduleAction.blockAll;
      case ScheduleType.school:
        return ScheduleAction.blockDistracting;
      case ScheduleType.homework:
      case ScheduleType.custom:
        return ScheduleAction.allowAll;
    }
  }

  static List<Day> _parseDays(Object? rawValue) {
    if (rawValue is! List) {
      return Day.values;
    }

    final result = <Day>[];
    for (final rawDay in rawValue) {
      final dayName = rawDay?.toString();
      if (dayName == null) {
        continue;
      }

      for (final day in Day.values) {
        if (day.name == dayName) {
          result.add(day);
          break;
        }
      }
    }

    return result.isEmpty ? Day.values : result;
  }

  static String _stringValue(
    Object? rawValue, {
    required String fallback,
  }) {
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return rawValue;
    }
    if (rawValue != null) {
      final converted = rawValue.toString().trim();
      if (converted.isNotEmpty) {
        return converted;
      }
    }
    return fallback;
  }

  static bool _boolValue(
    Object? rawValue, {
    required bool fallback,
  }) {
    if (rawValue is bool) {
      return rawValue;
    }
    if (rawValue is String) {
      if (rawValue.toLowerCase() == 'true') {
        return true;
      }
      if (rawValue.toLowerCase() == 'false') {
        return false;
      }
    }
    return fallback;
  }

  static String _defaultNameForType(ScheduleType type) {
    switch (type) {
      case ScheduleType.bedtime:
        return 'Bedtime';
      case ScheduleType.school:
        return 'School Time';
      case ScheduleType.homework:
        return 'Homework';
      case ScheduleType.custom:
        return 'Custom Schedule';
    }
  }
}
