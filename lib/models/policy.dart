import 'child_profile.dart';
import 'schedule.dart';
import '../config/category_ids.dart';

class ModeOverrideSet {
  const ModeOverrideSet({
    this.forceBlockServices = const <String>[],
    this.forceAllowServices = const <String>[],
    this.forceBlockPackages = const <String>[],
    this.forceAllowPackages = const <String>[],
    this.forceBlockDomains = const <String>[],
    this.forceAllowDomains = const <String>[],
  });

  final List<String> forceBlockServices;
  final List<String> forceAllowServices;
  final List<String> forceBlockPackages;
  final List<String> forceAllowPackages;
  final List<String> forceBlockDomains;
  final List<String> forceAllowDomains;

  bool get isEmpty =>
      forceBlockServices.isEmpty &&
      forceAllowServices.isEmpty &&
      forceBlockPackages.isEmpty &&
      forceAllowPackages.isEmpty &&
      forceBlockDomains.isEmpty &&
      forceAllowDomains.isEmpty;

  factory ModeOverrideSet.fromMap(Map<String, dynamic> map) {
    return ModeOverrideSet(
      forceBlockServices: _normalizedStringList(map['forceBlockServices']),
      forceAllowServices: _normalizedStringList(map['forceAllowServices']),
      forceBlockPackages: _normalizedStringList(
        map['forceBlockPackages'],
        lowercase: true,
      ),
      forceAllowPackages: _normalizedStringList(
        map['forceAllowPackages'],
        lowercase: true,
      ),
      forceBlockDomains: _normalizedStringList(
        map['forceBlockDomains'],
        lowercase: true,
      ),
      forceAllowDomains: _normalizedStringList(
        map['forceAllowDomains'],
        lowercase: true,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'forceBlockServices': forceBlockServices,
      'forceAllowServices': forceAllowServices,
      'forceBlockPackages': forceBlockPackages,
      'forceAllowPackages': forceAllowPackages,
      'forceBlockDomains': forceBlockDomains,
      'forceAllowDomains': forceAllowDomains,
    };
  }

  ModeOverrideSet copyWith({
    List<String>? forceBlockServices,
    List<String>? forceAllowServices,
    List<String>? forceBlockPackages,
    List<String>? forceAllowPackages,
    List<String>? forceBlockDomains,
    List<String>? forceAllowDomains,
  }) {
    return ModeOverrideSet(
      forceBlockServices: forceBlockServices ?? this.forceBlockServices,
      forceAllowServices: forceAllowServices ?? this.forceAllowServices,
      forceBlockPackages: forceBlockPackages ?? this.forceBlockPackages,
      forceAllowPackages: forceAllowPackages ?? this.forceAllowPackages,
      forceBlockDomains: forceBlockDomains ?? this.forceBlockDomains,
      forceAllowDomains: forceAllowDomains ?? this.forceAllowDomains,
    );
  }

  static List<String> _normalizedStringList(
    Object? value, {
    bool lowercase = false,
  }) {
    if (value is! List) {
      return const <String>[];
    }
    final unique = <String>{};
    for (final item in value) {
      var next = item.toString().trim();
      if (next.isEmpty) {
        continue;
      }
      if (lowercase) {
        next = next.toLowerCase();
      }
      unique.add(next);
    }
    final ordered = unique.toList()..sort();
    return ordered;
  }
}

class Policy {
  final List<String> blockedCategories;
  final List<String> blockedServices;
  final List<String> blockedDomains;
  final List<String> blockedPackages;
  final Map<String, ModeOverrideSet> modeOverrides;
  final int policySchemaVersion;
  final List<Schedule> schedules;
  final bool safeSearchEnabled;

  Policy({
    required this.blockedCategories,
    this.blockedServices = const <String>[],
    required this.blockedDomains,
    this.blockedPackages = const <String>[],
    this.modeOverrides = const <String, ModeOverrideSet>{},
    this.policySchemaVersion = 2,
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
          blockedServices: const <String>[],
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
          blockedServices: const <String>[],
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
          blockedServices: const <String>[],
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
      blockedCategories: _categoryList(map['blockedCategories']),
      blockedServices: _stringList(map['blockedServices']),
      blockedDomains: _stringList(map['blockedDomains']),
      blockedPackages: _packageList(map['blockedPackages']),
      modeOverrides: _modeOverridesMap(map['modeOverrides']),
      policySchemaVersion: _intValue(map['policySchemaVersion'], fallback: 1),
      schedules: parsedSchedules,
      safeSearchEnabled: _boolValue(map['safeSearchEnabled']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'blockedCategories': normalizeCategoryIds(blockedCategories),
      'blockedServices': blockedServices
          .map((service) => service.trim().toLowerCase())
          .where((service) => service.isNotEmpty)
          .toSet()
          .toList(growable: false),
      'blockedDomains': blockedDomains,
      'blockedPackages': blockedPackages
          .map((pkg) => pkg.trim().toLowerCase())
          .where((pkg) => pkg.isNotEmpty)
          .toSet()
          .toList(growable: false),
      'modeOverrides': modeOverrides.map(
        (modeName, overrideSet) => MapEntry(
          modeName.trim().toLowerCase(),
          overrideSet.toMap(),
        ),
      ),
      'policySchemaVersion': policySchemaVersion,
      'schedules': schedules.map((s) => s.toMap()).toList(),
      'safeSearchEnabled': safeSearchEnabled,
    };
  }

  Policy copyWith({
    List<String>? blockedCategories,
    List<String>? blockedServices,
    List<String>? blockedDomains,
    List<String>? blockedPackages,
    Map<String, ModeOverrideSet>? modeOverrides,
    int? policySchemaVersion,
    List<Schedule>? schedules,
    bool? safeSearchEnabled,
  }) {
    return Policy(
      blockedCategories: blockedCategories ?? this.blockedCategories,
      blockedServices: blockedServices ?? this.blockedServices,
      blockedDomains: blockedDomains ?? this.blockedDomains,
      blockedPackages: blockedPackages ?? this.blockedPackages,
      modeOverrides: modeOverrides ?? this.modeOverrides,
      policySchemaVersion: policySchemaVersion ?? this.policySchemaVersion,
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

  static int _intValue(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
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

  static List<String> _categoryList(Object? value) {
    return normalizeCategoryIds(_stringList(value));
  }

  static List<String> _packageList(Object? value) {
    return _stringList(value)
        .map((pkg) => pkg.trim().toLowerCase())
        .where((pkg) => pkg.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static Map<String, ModeOverrideSet> _modeOverridesMap(Object? value) {
    if (value is! Map) {
      return const <String, ModeOverrideSet>{};
    }
    final result = <String, ModeOverrideSet>{};
    for (final entry in value.entries) {
      final modeName = entry.key.toString().trim().toLowerCase();
      if (modeName.isEmpty) {
        continue;
      }
      final modeMap = _asMap(entry.value);
      if (modeMap.isEmpty) {
        continue;
      }
      final overrideSet = ModeOverrideSet.fromMap(modeMap);
      if (overrideSet.isEmpty) {
        continue;
      }
      result[modeName] = overrideSet;
    }
    return result;
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
