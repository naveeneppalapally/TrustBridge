import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/content_categories.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:uuid/uuid.dart';

enum PolicyQuickMode {
  strictShield,
  balanced,
  relaxed,
  schoolNight,
}

class PolicyQuickModeConfig {
  const PolicyQuickModeConfig({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.blockedCategories,
    required this.schedules,
    required this.safeSearchEnabled,
  });

  final PolicyQuickMode mode;
  final String title;
  final String subtitle;
  final List<String> blockedCategories;
  final List<Schedule> schedules;
  final bool safeSearchEnabled;
}

class PolicyQuickModes {
  const PolicyQuickModes._();

  static List<String> get _allCategories =>
      ContentCategories.allCategories.map((item) => item.id).toList();

  static List<String> get _highRiskCategories =>
      ContentCategories.highRisk.map((item) => item.id).toList();

  static List<PolicyQuickModeConfig> configsForAgeBand(AgeBand ageBand) {
    return [
      _strictShield(ageBand),
      _balanced(ageBand),
      _relaxed(ageBand),
      _schoolNight(ageBand),
    ];
  }

  static PolicyQuickModeConfig configFor({
    required PolicyQuickMode mode,
    required AgeBand ageBand,
  }) {
    switch (mode) {
      case PolicyQuickMode.strictShield:
        return _strictShield(ageBand);
      case PolicyQuickMode.balanced:
        return _balanced(ageBand);
      case PolicyQuickMode.relaxed:
        return _relaxed(ageBand);
      case PolicyQuickMode.schoolNight:
        return _schoolNight(ageBand);
    }
  }

  static Policy applyMode({
    required Policy currentPolicy,
    required PolicyQuickMode mode,
    required AgeBand ageBand,
  }) {
    final config = configFor(mode: mode, ageBand: ageBand);
    return currentPolicy.copyWith(
      blockedCategories: config.blockedCategories,
      schedules: config.schedules,
      safeSearchEnabled: config.safeSearchEnabled,
    );
  }

  static PolicyQuickModeConfig _strictShield(AgeBand ageBand) {
    return PolicyQuickModeConfig(
      mode: PolicyQuickMode.strictShield,
      title: 'Strict Shield',
      subtitle: 'Maximum protection for high-control mode.',
      blockedCategories: _allCategories,
      schedules: [
        Schedule.bedtime(startTime: '20:00', endTime: '07:00'),
        Schedule.schoolTime(startTime: '09:00', endTime: '15:00'),
        _homeworkSchedule(startTime: '17:00', endTime: '19:00'),
      ],
      safeSearchEnabled: true,
    );
  }

  static PolicyQuickModeConfig _balanced(AgeBand ageBand) {
    final agePreset = Policy.presetForAgeBand(ageBand);
    final union = {
      ...agePreset.blockedCategories,
      ..._highRiskCategories,
    }.toList()
      ..sort();

    return PolicyQuickModeConfig(
      mode: PolicyQuickMode.balanced,
      title: 'Balanced',
      subtitle: 'Recommended default based on age with safety baseline.',
      blockedCategories: union,
      schedules: agePreset.schedules,
      safeSearchEnabled: agePreset.safeSearchEnabled || ageBand != AgeBand.teen,
    );
  }

  static PolicyQuickModeConfig _relaxed(AgeBand ageBand) {
    return PolicyQuickModeConfig(
      mode: PolicyQuickMode.relaxed,
      title: 'Relaxed',
      subtitle: 'Block high-risk content, allow broader access.',
      blockedCategories: List<String>.from(_highRiskCategories),
      schedules: [_relaxedBedtime(ageBand)],
      safeSearchEnabled: ageBand != AgeBand.teen,
    );
  }

  static PolicyQuickModeConfig _schoolNight(AgeBand ageBand) {
    final blocked = {
      ..._highRiskCategories,
      'social-networks',
      'streaming',
      'chat',
      'games',
    }.toList()
      ..sort();

    return PolicyQuickModeConfig(
      mode: PolicyQuickMode.schoolNight,
      title: 'School Night',
      subtitle: 'Prioritize focus with stricter evening controls.',
      blockedCategories: blocked,
      schedules: [
        _bedtimeForAge(ageBand),
        Schedule.schoolTime(startTime: '09:00', endTime: '15:00'),
        _homeworkSchedule(startTime: '18:00', endTime: '20:00'),
      ],
      safeSearchEnabled: true,
    );
  }

  static Schedule _bedtimeForAge(AgeBand ageBand) {
    switch (ageBand) {
      case AgeBand.young:
        return Schedule.bedtime(startTime: '20:30', endTime: '07:00');
      case AgeBand.middle:
        return Schedule.bedtime(startTime: '21:30', endTime: '07:00');
      case AgeBand.teen:
        return Schedule.bedtime(startTime: '22:30', endTime: '07:00');
    }
  }

  static Schedule _relaxedBedtime(AgeBand ageBand) {
    switch (ageBand) {
      case AgeBand.young:
        return Schedule.bedtime(startTime: '21:00', endTime: '07:00');
      case AgeBand.middle:
        return Schedule.bedtime(startTime: '22:30', endTime: '07:00');
      case AgeBand.teen:
        return Schedule.bedtime(startTime: '23:30', endTime: '07:00');
    }
  }

  static Schedule _homeworkSchedule({
    required String startTime,
    required String endTime,
  }) {
    return Schedule(
      id: const Uuid().v4(),
      name: 'Homework Time',
      type: ScheduleType.homework,
      days: const [
        Day.monday,
        Day.tuesday,
        Day.wednesday,
        Day.thursday,
        Day.friday,
      ],
      startTime: startTime,
      endTime: endTime,
      enabled: true,
      action: ScheduleAction.blockDistracting,
    );
  }
}
