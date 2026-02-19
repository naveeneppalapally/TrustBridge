import 'dart:math' as math;

import 'package:flutter/services.dart';

class AppUsageEntry {
  const AppUsageEntry({
    required this.packageName,
    required this.appName,
    required this.totalForegroundTimeMs,
    this.lastTimeUsed,
    this.dailyUsageMs = const <String, int>{},
  });

  final String packageName;
  final String appName;
  final int totalForegroundTimeMs;
  final DateTime? lastTimeUsed;
  final Map<String, int> dailyUsageMs;

  Duration get duration => Duration(milliseconds: totalForegroundTimeMs);

  factory AppUsageEntry.fromMap(Map<dynamic, dynamic> map) {
    final rawDailyUsage = map['dailyUsageMs'];
    final dailyUsage = <String, int>{};
    if (rawDailyUsage is Map) {
      for (final entry in rawDailyUsage.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) {
          continue;
        }
        dailyUsage[key] = _asInt(entry.value);
      }
    }

    return AppUsageEntry(
      packageName: (map['packageName'] as String? ?? '').trim(),
      appName: (map['appName'] as String? ?? '').trim(),
      totalForegroundTimeMs: _asInt(map['totalForegroundTimeMs']),
      lastTimeUsed: _asDateTime(map['lastTimeUsedEpochMs']),
      dailyUsageMs: dailyUsage,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  static DateTime? _asDateTime(Object? value) {
    final epoch = _asInt(value);
    if (epoch <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(epoch);
  }
}

class UsageCategorySlice {
  const UsageCategorySlice({
    required this.label,
    required this.duration,
  });

  final String label;
  final Duration duration;
}

class DailyUsagePoint {
  const DailyUsagePoint({
    required this.label,
    required this.duration,
  });

  final String label;
  final Duration duration;
}

class AppUsageSummary {
  const AppUsageSummary({
    required this.packageName,
    required this.appName,
    required this.category,
    required this.duration,
    required this.progress,
  });

  final String packageName;
  final String appName;
  final String category;
  final Duration duration;
  final double progress;
}

class UsageReportData {
  const UsageReportData({
    required this.permissionGranted,
    required this.totalScreenTime,
    required this.averageDailyScreenTime,
    required this.categorySlices,
    required this.dailyTrend,
    required this.topApps,
  });

  final bool permissionGranted;
  final Duration totalScreenTime;
  final Duration averageDailyScreenTime;
  final List<UsageCategorySlice> categorySlices;
  final List<DailyUsagePoint> dailyTrend;
  final List<AppUsageSummary> topApps;

  bool get hasData =>
      totalScreenTime.inMilliseconds > 0 &&
      (categorySlices.isNotEmpty || topApps.isNotEmpty);

  factory UsageReportData.permissionDenied() {
    return const UsageReportData(
      permissionGranted: false,
      totalScreenTime: Duration.zero,
      averageDailyScreenTime: Duration.zero,
      categorySlices: <UsageCategorySlice>[],
      dailyTrend: <DailyUsagePoint>[],
      topApps: <AppUsageSummary>[],
    );
  }
}

class AppUsageService {
  AppUsageService({
    MethodChannel? channel,
  }) : _channel =
            channel ?? const MethodChannel('com.navee.trustbridge/usage_stats');

  final MethodChannel _channel;

  Future<bool> hasUsageAccessPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsageStatsPermission') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openUsageAccessSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openUsageStatsSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<List<AppUsageEntry>> getUsageEntries({
    int pastDays = 7,
  }) async {
    if (pastDays <= 0) {
      return const <AppUsageEntry>[];
    }

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getUsageStats',
        <String, dynamic>{'pastDays': pastDays},
      );
      if (result == null || result.isEmpty) {
        return const <AppUsageEntry>[];
      }
      return result
          .whereType<Map>()
          .map((map) => AppUsageEntry.fromMap(map))
          .where((entry) => entry.packageName.isNotEmpty)
          .toList(growable: false);
    } on PlatformException {
      return const <AppUsageEntry>[];
    } on MissingPluginException {
      return const <AppUsageEntry>[];
    }
  }

  Future<UsageReportData> getUsageReport({
    int pastDays = 7,
    int topAppCount = 5,
  }) async {
    final permissionGranted = await hasUsageAccessPermission();
    if (!permissionGranted) {
      return UsageReportData.permissionDenied();
    }

    final entries = await getUsageEntries(pastDays: pastDays);
    if (entries.isEmpty) {
      return UsageReportData(
        permissionGranted: true,
        totalScreenTime: Duration.zero,
        averageDailyScreenTime: Duration.zero,
        categorySlices: const <UsageCategorySlice>[],
        dailyTrend: _emptyDailyTrend(pastDays),
        topApps: const <AppUsageSummary>[],
      );
    }

    var totalMs = 0;
    final categoryTotals = <String, int>{};
    final dailyTotals = _initializeDailyTotals(pastDays);

    for (final entry in entries) {
      totalMs += entry.totalForegroundTimeMs;
      final category = _categoryFromPackage(entry.packageName);
      categoryTotals[category] =
          (categoryTotals[category] ?? 0) + entry.totalForegroundTimeMs;

      for (final daily in entry.dailyUsageMs.entries) {
        if (!dailyTotals.containsKey(daily.key)) {
          continue;
        }
        dailyTotals[daily.key] = (dailyTotals[daily.key] ?? 0) + daily.value;
      }
    }

    final totalDuration = Duration(milliseconds: totalMs);
    final averageDaily = pastDays <= 0
        ? Duration.zero
        : Duration(milliseconds: totalMs ~/ pastDays);

    final categories = categoryTotals.entries
        .map(
          (entry) => UsageCategorySlice(
            label: entry.key,
            duration: Duration(milliseconds: entry.value),
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => b.duration.compareTo(a.duration));

    final topRawApps = List<AppUsageEntry>.from(entries)
      ..sort(
        (a, b) => b.totalForegroundTimeMs.compareTo(a.totalForegroundTimeMs),
      );
    final topApps = topRawApps.take(topAppCount).toList(growable: false);
    final maxMs =
        topApps.isEmpty ? 1 : math.max(1, topApps.first.totalForegroundTimeMs);

    final appSummaries = topApps
        .map(
          (app) => AppUsageSummary(
            packageName: app.packageName,
            appName: app.appName.isEmpty ? app.packageName : app.appName,
            category: _categoryFromPackage(app.packageName),
            duration: Duration(milliseconds: app.totalForegroundTimeMs),
            progress: (app.totalForegroundTimeMs / maxMs).clamp(0.0, 1.0),
          ),
        )
        .toList(growable: false);

    final trend = dailyTotals.entries
        .map(
          (entry) => DailyUsagePoint(
            label: _weekdayLabel(entry.key),
            duration: Duration(milliseconds: entry.value),
          ),
        )
        .toList(growable: false);

    return UsageReportData(
      permissionGranted: true,
      totalScreenTime: totalDuration,
      averageDailyScreenTime: averageDaily,
      categorySlices: categories,
      dailyTrend: trend,
      topApps: appSummaries,
    );
  }

  Map<String, int> _initializeDailyTotals(int pastDays) {
    final now = DateTime.now();
    final map = <String, int>{};
    for (var offset = pastDays - 1; offset >= 0; offset--) {
      final day = now.subtract(Duration(days: offset));
      final key = _dateKey(day);
      map[key] = 0;
    }
    return map;
  }

  List<DailyUsagePoint> _emptyDailyTrend(int pastDays) {
    return _initializeDailyTotals(pastDays)
        .keys
        .map(
          (key) => DailyUsagePoint(
            label: _weekdayLabel(key),
            duration: Duration.zero,
          ),
        )
        .toList(growable: false);
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _weekdayLabel(String dateKey) {
    final parsed = DateTime.tryParse(dateKey);
    if (parsed == null) {
      return '?';
    }
    const labels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return labels[parsed.weekday - 1];
  }

  String _categoryFromPackage(String packageName) {
    final normalized = packageName.toLowerCase();
    if (normalized.contains('youtube') ||
        normalized.contains('netflix') ||
        normalized.contains('hotstar') ||
        normalized.contains('spotify')) {
      return 'Entertainment';
    }
    if (normalized.contains('instagram') ||
        normalized.contains('facebook') ||
        normalized.contains('whatsapp') ||
        normalized.contains('telegram') ||
        normalized.contains('snapchat')) {
      return 'Social';
    }
    if (normalized.contains('classroom') ||
        normalized.contains('khan') ||
        normalized.contains('duolingo') ||
        normalized.contains('edu')) {
      return 'Education';
    }
    if (normalized.contains('game') ||
        normalized.contains('roblox') ||
        normalized.contains('minecraft') ||
        normalized.contains('pubg') ||
        normalized.contains('freefire')) {
      return 'Games';
    }
    return 'Other';
  }
}
