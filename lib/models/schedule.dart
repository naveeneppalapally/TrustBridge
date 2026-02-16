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
    return Schedule(
      id: map['id'] as String,
      name: map['name'] as String,
      type: ScheduleType.values.byName(map['type'] as String),
      days: (map['days'] as List<dynamic>)
          .map((d) => Day.values.byName(d as String))
          .toList(),
      startTime: map['startTime'] as String,
      endTime: map['endTime'] as String,
      enabled: map['enabled'] as bool? ?? true,
      action: ScheduleAction.values.byName(map['action'] as String),
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
}
