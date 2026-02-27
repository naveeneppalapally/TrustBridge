import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/rollout_flags.dart';
import '../config/service_definitions.dart';
import '../models/child_profile.dart';
import '../services/auth_service.dart';
import '../services/app_usage_service.dart';
import '../services/firestore_service.dart';
import '../services/nextdns_api_service.dart';
import '../widgets/skeleton_loaders.dart';

class UsageReportsScreen extends StatefulWidget {
  const UsageReportsScreen({
    super.key,
    this.showLoadingState = false,
    this.showAppBar = true,
    this.appUsageService,
    this.authService,
    this.firestoreService,
    this.nextDnsApiService,
    this.parentIdOverride,
    this.childIdOverride,
  });

  final bool showLoadingState;
  final bool showAppBar;
  final AppUsageService? appUsageService;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final NextDnsApiService? nextDnsApiService;
  final String? parentIdOverride;
  final String? childIdOverride;

  @override
  State<UsageReportsScreen> createState() => _UsageReportsScreenState();
}

class _UsageReportsScreenState extends State<UsageReportsScreen> {
  AppUsageService? _appUsageService;
  AuthService? _authService;
  FirestoreService? _firestoreService;
  NextDnsApiService? _nextDnsApiService;
  UsageReportData? _report;
  List<ChildProfile> _children = const <ChildProfile>[];
  int? _nextDnsBlockedToday;
  List<NextDnsDomainStat> _nextDnsTopBlockedDomains = const [];
  bool _nextDnsConfigured = false;
  bool _usageAccessGranted = true;
  bool _loading = true;
  String? _error;
  DateTime _selectedDay = DateTime.now();

  bool get _perAppUsageReportsEnabled => RolloutFlags.perAppUsageReports;

  AppUsageService get _resolvedAppUsageService {
    _appUsageService ??= widget.appUsageService ?? AppUsageService();
    return _appUsageService!;
  }

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  NextDnsApiService get _resolvedNextDnsApiService {
    _nextDnsApiService ??= widget.nextDnsApiService ?? NextDnsApiService();
    return _nextDnsApiService!;
  }

  String? get _parentId {
    final override = widget.parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    try {
      return _resolvedAuthService.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.showLoadingState) {
      _loading = true;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parentId = _parentId;
      List<ChildProfile> children = const <ChildProfile>[];
      if (parentId != null && parentId.trim().isNotEmpty) {
        children = await _resolvedFirestoreService.getChildrenOnce(parentId);
        final childIdFilter = widget.childIdOverride?.trim();
        if (childIdFilter != null && childIdFilter.isNotEmpty) {
          children = children
              .where((child) => child.id.trim() == childIdFilter)
              .toList(growable: false);
        }
      }
      UsageReportData? report = await _loadAggregatedChildUsageReport(
        children,
        selectedDay: _selectedDay,
      );
      final usageAccessGranted =
          await _resolvedAppUsageService.hasUsageAccessPermission();
      if (report == null) {
        final localReport = await _resolvedAppUsageService.getUsageReport(
          pastDays: 7,
        );
        if (localReport.hasData) {
          report = localReport;
        }
      }
      final analytics = await _loadNextDnsAnalytics();
      if (!mounted) {
        return;
      }
      setState(() {
        _report = report;
        _children = children;
        _nextDnsConfigured = analytics.configured;
        _nextDnsBlockedToday = analytics.blockedToday;
        _nextDnsTopBlockedDomains = analytics.topBlockedDomains;
        _usageAccessGranted = usageAccessGranted;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (!widget.showAppBar) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage Reports'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 16),
              label: const Text('This Week'),
              onPressed: _loading ? null : _load,
            ),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (widget.showLoadingState || _loading) {
      return _buildLoadingState();
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to load usage report.\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!_usageAccessGranted) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildUsageAccessRequiredCard(),
        ],
      );
    }

    final report = _report;
    if (report == null || !report.hasData) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_perAppUsageReportsEnabled) ...[
            _buildDaySelectorCard(),
            const SizedBox(height: 12),
          ],
          _buildChildSummaryFallbackCard(),
          const SizedBox(height: 14),
          _buildChildUsagePendingCard(),
          const SizedBox(height: 14),
          _buildNextDnsAnalyticsCard(),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_perAppUsageReportsEnabled) ...[
          _buildDaySelectorCard(),
          const SizedBox(height: 12),
        ],
        _HeroStatsCard(report: report),
        const SizedBox(height: 14),
        _CategoryCard(report: report),
        if (_perAppUsageReportsEnabled) ...[
          const SizedBox(height: 14),
          _TrendCard(report: report),
          const SizedBox(height: 14),
          _MostUsedAppsCard(report: report),
        ],
        const SizedBox(height: 14),
        _buildNextDnsAnalyticsCard(),
      ],
    );
  }

  Widget _buildChildUsagePendingCard() {
    final hasChildren = _children.isNotEmpty;
    if (!_usageAccessGranted) {
      return _buildUsageAccessRequiredCard();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              hasChildren
                  ? 'Waiting for child usage data'
                  : 'No child devices paired',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasChildren
                  ? 'Open TrustBridge on the child phone and grant Usage Access there. '
                      'Reports update automatically after the next heartbeat.'
                  : 'Add and pair a child device to start receiving reports.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _load,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageAccessRequiredCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Usage access required',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'To see which apps your child uses, tap here to grant access.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _openUsageAccessSettings,
              child: const Text('Grant Access'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUsageAccessSettings() async {
    final opened = await _resolvedAppUsageService.openUsageAccessSettings();
    if (!opened || !mounted) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      return;
    }
    await _load();
  }

  Widget _buildChildSummaryFallbackCard() {
    if (_children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Child summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Quick snapshot from child profiles and active controls.',
            ),
            const SizedBox(height: 12),
            ..._children.map((child) {
              final categories = child.policy.blockedCategories.length;
              final domains = child.policy.blockedDomains.length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            child.nickname,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text('$categories cats • $domains domains'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _ChildRemoteUsageRow(
                      childId: child.id,
                      firestoreService: _resolvedFirestoreService,
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDaySelectorCard() {
    final options = _recentDayOptions();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Day Filter',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((day) {
                final selected = _sameDay(day, _selectedDay);
                return ChoiceChip(
                  label: Text(_dayChipLabel(day)),
                  selected: selected,
                  onSelected: (_) {
                    if (selected) {
                      return;
                    }
                    setState(() {
                      _selectedDay = day;
                    });
                    _load();
                  },
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  List<DateTime> _recentDayOptions() {
    final today = _dayStart(DateTime.now());
    return List<DateTime>.generate(
      7,
      (index) => today.subtract(Duration(days: index)),
    );
  }

  String _dayChipLabel(DateTime day) {
    final today = _dayStart(DateTime.now());
    if (_sameDay(day, today)) {
      return 'Today';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (_sameDay(day, yesterday)) {
      return 'Yesterday';
    }
    return '${day.month}/${day.day}';
  }

  DateTime _dayStart(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _sameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _dayKey(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<UsageReportData?> _loadAggregatedChildUsageReport(
    List<ChildProfile> children, {
    required DateTime selectedDay,
  }) async {
    if (children.isEmpty) {
      return null;
    }

    final selectedDayStart = _dayStart(selectedDay);
    final selectedDayKey = _dayKey(selectedDayStart);
    final trendDays = List<DateTime>.generate(
      7,
      (index) => selectedDayStart.subtract(Duration(days: 6 - index)),
    );

    var totalScreenTimeMs = 0;
    var hasAnyData = false;
    final categoryTotalsMs = <String, int>{};
    final trendTotalsMs = List<int>.filled(trendDays.length, 0);
    final trendLabels = trendDays
        .map((day) => '${day.month}/${day.day}')
        .toList(growable: false);
    final appTotals = <String, _AggregatedAppUsage>{};

    for (final child in children) {
      final usageRef = _resolvedFirestoreService.firestore
          .collection('children')
          .doc(child.id)
          .collection('usage_reports');
      final latestFuture = usageRef.doc('latest').get();
      final selectedNestedFuture =
          usageRef.doc('daily').collection('days').doc(selectedDayKey).get();
      final selectedFlatFuture = usageRef.doc('daily_$selectedDayKey').get();
      final trendNestedFutures = trendDays
          .map((day) =>
              usageRef.doc('daily').collection('days').doc(_dayKey(day)).get())
          .toList(growable: false);
      final trendFlatFutures = trendDays
          .map((day) => usageRef.doc('daily_${_dayKey(day)}').get())
          .toList(growable: false);

      final latestSnapshot = await latestFuture;
      final selectedNestedSnapshot = await selectedNestedFuture;
      final selectedFlatSnapshot = await selectedFlatFuture;
      final trendNestedSnapshots = await Future.wait(trendNestedFutures);
      final trendFlatSnapshots = await Future.wait(trendFlatFutures);

      final latestData = latestSnapshot.data() ?? const <String, dynamic>{};
      final selectedDailyData =
          (selectedNestedSnapshot.data() ?? selectedFlatSnapshot.data()) ??
              const <String, dynamic>{};

      if (selectedDailyData.isNotEmpty) {
        final totalMinutes = _toInt(selectedDailyData['totalScreenMinutes']);
        totalScreenTimeMs += totalMinutes * Duration.millisecondsPerMinute;
        if (totalMinutes > 0) {
          hasAnyData = true;
        }

        final categoryTotalsRaw = selectedDailyData['categoryTotals'];
        if (categoryTotalsRaw is Map) {
          for (final entry in categoryTotalsRaw.entries) {
            final label = entry.key.toString().trim();
            if (label.isEmpty) {
              continue;
            }
            final durationMs = _toInt(entry.value);
            if (durationMs <= 0) {
              continue;
            }
            categoryTotalsMs[label] =
                (categoryTotalsMs[label] ?? 0) + durationMs;
            hasAnyData = true;
          }
        }

        final appUsageRaw = selectedDailyData['appUsageByPackage'];
        if (appUsageRaw is Map) {
          for (final entry in appUsageRaw.entries) {
            final packageName = entry.key.toString().trim().toLowerCase();
            if (packageName.isEmpty) {
              continue;
            }
            final appMap = entry.value is Map
                ? (entry.value as Map).map(
                    (key, value) => MapEntry(key.toString(), value),
                  )
                : const <String, dynamic>{};
            final durationMs = _toInt(appMap['durationMs']);
            final minutes = _toInt(appMap['minutes']);
            final resolvedDurationMs = durationMs > 0
                ? durationMs
                : minutes * Duration.millisecondsPerMinute;
            if (resolvedDurationMs <= 0) {
              continue;
            }
            final appName = _resolveAppName(
              packageName: packageName,
              reportedName: (appMap['appName'] as String?)?.trim(),
            );
            final aggregateKey = packageName;
            final existing = appTotals[aggregateKey];
            if (existing == null) {
              appTotals[aggregateKey] = _AggregatedAppUsage(
                packageName: packageName,
                appName: appName,
                category: _categoryFromPackage(packageName),
                durationMs: resolvedDurationMs,
              );
            } else {
              appTotals[aggregateKey] = existing.copyWith(
                durationMs: existing.durationMs + resolvedDurationMs,
              );
            }
            hasAnyData = true;
          }
        }
      } else if (latestData.isNotEmpty) {
        final reportTotalMs = _toInt(latestData['totalScreenTimeMs']);
        if (reportTotalMs > 0) {
          totalScreenTimeMs += reportTotalMs;
          hasAnyData = true;
        }

        for (final slice in _parseMapList(latestData['categorySlices'])) {
          final label = (slice['label'] as String?)?.trim();
          if (label == null || label.isEmpty) {
            continue;
          }
          final durationMs = _toInt(slice['durationMs']);
          if (durationMs <= 0) {
            continue;
          }
          categoryTotalsMs[label] = (categoryTotalsMs[label] ?? 0) + durationMs;
          hasAnyData = true;
        }

        final appUsageRaw = latestData['appUsageByPackage'];
        if (appUsageRaw is Map) {
          for (final entry in appUsageRaw.entries) {
            final packageName = entry.key.toString().trim().toLowerCase();
            if (packageName.isEmpty) {
              continue;
            }
            final appMap = entry.value is Map
                ? (entry.value as Map).map(
                    (key, value) => MapEntry(key.toString(), value),
                  )
                : const <String, dynamic>{};
            final durationMs = _toInt(appMap['durationMs']);
            final minutes = _toInt(appMap['minutes']);
            final resolvedDurationMs = durationMs > 0
                ? durationMs
                : minutes * Duration.millisecondsPerMinute;
            if (resolvedDurationMs <= 0) {
              continue;
            }
            final appName = _resolveAppName(
              packageName: packageName,
              reportedName: (appMap['appName'] as String?)?.trim(),
            );
            final existing = appTotals[packageName];
            if (existing == null) {
              appTotals[packageName] = _AggregatedAppUsage(
                packageName: packageName,
                appName: appName,
                category: _categoryFromPackage(packageName),
                durationMs: resolvedDurationMs,
              );
            } else {
              appTotals[packageName] = existing.copyWith(
                durationMs: existing.durationMs + resolvedDurationMs,
              );
            }
            hasAnyData = true;
          }
        } else {
          for (final app in _parseMapList(latestData['topApps'])) {
            final packageName =
                (app['packageName'] as String?)?.trim().toLowerCase() ?? '';
            final appName = _resolveAppName(
              packageName: packageName,
              reportedName: (app['appName'] as String?)?.trim(),
            );
            final category = (app['category'] as String?)?.trim() ?? 'Other';
            final durationMs = _toInt(app['durationMs']);
            if (durationMs <= 0) {
              continue;
            }

            final aggregateKey =
                packageName.isNotEmpty ? packageName : appName.toLowerCase();
            final existing = appTotals[aggregateKey];
            if (existing == null) {
              appTotals[aggregateKey] = _AggregatedAppUsage(
                packageName: packageName,
                appName: appName.isEmpty ? 'App' : appName,
                category: category.isEmpty ? 'Other' : category,
                durationMs: durationMs,
              );
            } else {
              appTotals[aggregateKey] = existing.copyWith(
                durationMs: existing.durationMs + durationMs,
              );
            }
            hasAnyData = true;
          }
        }
      }

      for (var index = 0; index < trendNestedSnapshots.length; index++) {
        final trendData = (trendNestedSnapshots[index].data() ??
                trendFlatSnapshots[index].data()) ??
            const <String, dynamic>{};
        if (trendData.isEmpty) {
          continue;
        }
        final totalMinutes = _toInt(trendData['totalScreenMinutes']);
        if (totalMinutes <= 0) {
          continue;
        }
        final durationMs = totalMinutes * Duration.millisecondsPerMinute;
        trendTotalsMs[index] += durationMs;
        hasAnyData = true;
      }

      if (trendNestedSnapshots.every((snapshot) => !snapshot.exists) &&
          trendFlatSnapshots.every((snapshot) => !snapshot.exists) &&
          latestData.isNotEmpty) {
        final trend = _parseMapList(latestData['dailyTrend']);
        for (var index = 0;
            index < trend.length && index < trendTotalsMs.length;
            index++) {
          final point = trend[index];
          final durationMs = _toInt(point['durationMs']);
          trendTotalsMs[index] += durationMs;
          if (durationMs > 0) {
            hasAnyData = true;
          }
        }
      }
    }

    if (!hasAnyData) {
      return null;
    }

    final trendTotalMs = trendTotalsMs.fold<int>(0, (sum, item) => sum + item);
    final averageDailyScreenTimeMs = trendTotalMs > 0
        ? (trendTotalMs / trendTotalsMs.length).round()
        : (totalScreenTimeMs / 7).round();

    final categorySlices = categoryTotalsMs.entries
        .map(
          (entry) => UsageCategorySlice(
            label: entry.key,
            duration: Duration(milliseconds: entry.value),
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => b.duration.compareTo(a.duration));

    final topAppsRaw = appTotals.values.toList(growable: false)
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
    final topAppsTopFive = topAppsRaw.take(5).toList(growable: false);
    final maxAppDurationMs =
        topAppsTopFive.isEmpty ? 1 : topAppsTopFive.first.durationMs;
    final topApps = topAppsTopFive
        .map(
          (entry) => AppUsageSummary(
            packageName: entry.packageName,
            appName: entry.appName,
            category: entry.category,
            duration: Duration(milliseconds: entry.durationMs),
            progress: (entry.durationMs / maxAppDurationMs).clamp(0.0, 1.0),
          ),
        )
        .toList(growable: false);

    final trend = <DailyUsagePoint>[];
    for (var index = 0; index < trendTotalsMs.length; index++) {
      trend.add(
        DailyUsagePoint(
          label: trendLabels[index],
          duration: Duration(milliseconds: trendTotalsMs[index]),
        ),
      );
    }

    return UsageReportData(
      permissionGranted: true,
      totalScreenTime: Duration(milliseconds: totalScreenTimeMs),
      averageDailyScreenTime: Duration(milliseconds: averageDailyScreenTimeMs),
      categorySlices: categorySlices,
      dailyTrend: trend,
      topApps: topApps,
    );
  }

  List<Map<String, dynamic>> _parseMapList(Object? rawValue) {
    if (rawValue is! List) {
      return const <Map<String, dynamic>>[];
    }
    final parsed = <Map<String, dynamic>>[];
    for (final item in rawValue) {
      if (item is Map<String, dynamic>) {
        parsed.add(item);
        continue;
      }
      if (item is Map) {
        parsed.add(
          item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
      }
    }
    return parsed;
  }

  int _toInt(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return 0;
  }

  static const Map<String, String> _friendlyPackageNames = <String, String>{
    'com.android.chrome': 'Chrome',
    'com.android.systemui': 'System UI',
    'com.android.launcher3': 'System Launcher',
    'com.android.settings': 'Settings',
    'com.google.android.apps.nexuslauncher': 'System Launcher',
    'com.google.android.gms': 'Google Play services',
    'com.google.android.youtube': 'YouTube',
    'com.whatsapp': 'WhatsApp',
    'com.instagram.android': 'Instagram',
    'com.snapchat.android': 'Snapchat',
    'com.dts.freefireth': 'Free Fire',
    'com.pubg.imobile': 'BGMI',
    'com.josh.app': 'Josh',
    'in.mohalla.video': 'Moj',
    'com.sharechat.app': 'ShareChat',
    'in.mohalla.sharechat': 'ShareChat',
  };

  String _resolveAppName({
    required String packageName,
    String? reportedName,
  }) {
    final normalizedPackage = packageName.trim().toLowerCase();
    final candidate = (reportedName ?? '').trim();
    if (candidate.isNotEmpty && !_looksLikePackageName(candidate)) {
      return candidate;
    }
    if (normalizedPackage.isEmpty) {
      return candidate.isEmpty ? 'App' : candidate;
    }
    return _appNameFromPackage(normalizedPackage);
  }

  String _appNameFromPackage(String packageName) {
    final mappedName = _friendlyPackageNames[packageName];
    if (mappedName != null) {
      return mappedName;
    }

    for (final service in ServiceDefinitions.all) {
      for (final pkg in service.androidPackages) {
        if (pkg.trim().toLowerCase() == packageName) {
          return service.displayName;
        }
      }
    }
    final pieces = packageName.split('.');
    if (pieces.isEmpty) {
      return packageName;
    }
    final tail = pieces.last;
    if (tail.trim().isEmpty) {
      return packageName;
    }
    final words = tail
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) {
      return tail;
    }
    return words
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  bool _looksLikePackageName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.contains('.') && normalized == normalized.toLowerCase();
  }

  String _categoryFromPackage(String packageName) {
    for (final service in ServiceDefinitions.all) {
      for (final pkg in service.androidPackages) {
        if (pkg.trim().toLowerCase() == packageName) {
          return service.categoryId;
        }
      }
    }
    return 'Other';
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: const [
        SkeletonCard(height: 150),
        SizedBox(height: 14),
        SkeletonChart(height: 260),
        SizedBox(height: 14),
        SkeletonChart(height: 220),
        SizedBox(height: 14),
        SkeletonListTile(),
        SizedBox(height: 10),
        SkeletonListTile(),
        SizedBox(height: 10),
        SkeletonListTile(),
      ],
    );
  }

  Widget _buildNextDnsAnalyticsCard() {
    if (!_nextDnsConfigured) {
      return const Card(
        key: Key('usage_reports_nextdns_card'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Web Protection Analytics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text('Connect web profile to view blocked domain insights.'),
            ],
          ),
        ),
      );
    }

    final blockedToday = _nextDnsBlockedToday ?? 0;
    return Card(
      key: const Key('usage_reports_nextdns_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Web Protection Analytics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Sites Blocked Today: $blockedToday',
              key: const Key('usage_reports_nextdns_blocked_today'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 10),
            if (_nextDnsTopBlockedDomains.isEmpty)
              const Text('No blocked-domain samples available yet.')
            else
              ..._nextDnsTopBlockedDomains.map(
                (domain) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.block, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          domain.domain,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${domain.queries}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<_NextDnsUsageAnalytics> _loadNextDnsAnalytics() async {
    final parentId = _parentId;
    if (parentId == null) {
      return const _NextDnsUsageAnalytics(configured: false);
    }

    try {
      final preferences = await _resolvedFirestoreService.getParentPreferences(
        parentId,
      );
      final enabled = preferences?['nextDnsEnabled'] == true;
      final profileId =
          (preferences?['nextDnsProfileId'] as String? ?? '').trim();
      if (!enabled || profileId.isEmpty) {
        return const _NextDnsUsageAnalytics(configured: false);
      }

      final topDomains = await _resolvedNextDnsApiService.getTopDomains(
        profileId: profileId,
        status: 'blocked',
        limit: 5,
      );
      final status = await _resolvedNextDnsApiService.getAnalyticsStatus(
        profileId: profileId,
        limit: 20,
      );

      var blockedFromStatus = 0;
      for (final entry in status) {
        if (entry.status.toLowerCase().contains('block')) {
          blockedFromStatus += entry.queries;
        }
      }
      final blockedFromTopDomains = topDomains.fold<int>(
        0,
        (sum, domain) => sum + domain.queries,
      );

      return _NextDnsUsageAnalytics(
        configured: true,
        blockedToday:
            blockedFromStatus > 0 ? blockedFromStatus : blockedFromTopDomains,
        topBlockedDomains: topDomains,
      );
    } catch (_) {
      return const _NextDnsUsageAnalytics(configured: true);
    }
  }
}

class _NextDnsUsageAnalytics {
  const _NextDnsUsageAnalytics({
    required this.configured,
    this.blockedToday,
    this.topBlockedDomains = const [],
  });

  final bool configured;
  final int? blockedToday;
  final List<NextDnsDomainStat> topBlockedDomains;
}

class _AggregatedAppUsage {
  const _AggregatedAppUsage({
    required this.packageName,
    required this.appName,
    required this.category,
    required this.durationMs,
  });

  final String packageName;
  final String appName;
  final String category;
  final int durationMs;

  _AggregatedAppUsage copyWith({
    String? packageName,
    String? appName,
    String? category,
    int? durationMs,
  }) {
    return _AggregatedAppUsage(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      category: category ?? this.category,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}

class _HeroStatsCard extends StatelessWidget {
  const _HeroStatsCard({required this.report});

  final UsageReportData report;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('usage_reports_hero_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF2E86FF), Color(0xFF235CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Screen Time',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                _formatDuration(report.totalScreenTime),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'LIVE',
                style: TextStyle(
                  color: Color(0xFFDDF3FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'DAILY AVERAGE: ${_formatDuration(report.averageDailyScreenTime)}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.report});

  final UsageReportData report;

  @override
  Widget build(BuildContext context) {
    final slices = report.categorySlices.take(5).toList(growable: false);
    final totalMs = report.totalScreenTime.inMilliseconds <= 0
        ? 1
        : report.totalScreenTime.inMilliseconds;

    if (slices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      key: const Key('usage_reports_category_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'By Category',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 52,
                  startDegreeOffset: -95,
                  sections: slices.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return PieChartSectionData(
                      value: item.duration.inMilliseconds / totalMs * 100,
                      color: _categoryColor(index),
                      title: '',
                      radius: 46,
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...slices.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _categoryColor(index),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _formatDuration(item.duration),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.report});

  final UsageReportData report;

  @override
  Widget build(BuildContext context) {
    final points = report.dailyTrend;
    final values =
        points.map((point) => point.duration.inMinutes / 60.0).toList();
    final peak = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);

    return Card(
      key: const Key('usage_reports_trend_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '7-Day Trend',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 190,
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1.5,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.18),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              points[index].label,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: values.asMap().entries.map((entry) {
                    final value = entry.value;
                    final isPeak = value == peak;
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: value,
                          width: 16,
                          borderRadius: BorderRadius.circular(6),
                          color: isPeak
                              ? const Color(0xFF2E86FF)
                              : const Color(0xFF9FC8FF),
                        ),
                      ],
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MostUsedAppsCard extends StatelessWidget {
  const _MostUsedAppsCard({required this.report});

  final UsageReportData report;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('usage_reports_apps_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Most Used Apps',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            if (report.topApps.isEmpty)
              const Text('No usage data available yet.')
            else
              ...report.topApps.map((app) => _UsageRowTile(row: app)),
          ],
        ),
      ),
    );
  }
}

class _UsageRowTile extends StatelessWidget {
  const _UsageRowTile({required this.row});

  final AppUsageSummary row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.apps,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.appName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      row.category,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDuration(row.duration),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: row.progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: const Color(0xFFDBEAFE),
            color: const Color(0xFF3B82F6),
          ),
        ],
      ),
    );
  }
}

Color _categoryColor(int index) {
  const colors = <Color>[
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFF43F5E),
  ];
  return colors[index % colors.length];
}

String _formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours <= 0) {
    return '${minutes}m';
  }
  if (minutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${minutes}m';
}

/// Reads the latest usage report uploaded by the child device from Firestore
/// and displays total screen time + top apps inline.
class _ChildRemoteUsageRow extends StatelessWidget {
  const _ChildRemoteUsageRow({
    required this.childId,
    required this.firestoreService,
  });

  final String childId;
  final FirestoreService firestoreService;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchLatestUsage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text(
            'Loading screen time...',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Text(
            'No screen time data yet',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          );
        }

        final totalMs = data['totalScreenTimeMs'] as int? ?? 0;
        final totalDuration = Duration(milliseconds: totalMs);
        final topApps = data['topApps'] as List<dynamic>? ?? const [];

        final topAppLabels = topApps
            .take(3)
            .map((app) {
              if (app is Map) {
                final name = app['appName'] ?? app['packageName'] ?? '?';
                final appMs = app['durationMs'] as int? ?? 0;
                return '$name (${_formatDuration(Duration(milliseconds: appMs))})';
              }
              return '';
            })
            .where((label) => label.isNotEmpty)
            .join(', ');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Screen time (7d): ${_formatDuration(totalDuration)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (topAppLabels.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Top: $topAppLabels',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _fetchLatestUsage() async {
    try {
      final doc = await firestoreService.firestore
          .collection('children')
          .doc(childId)
          .collection('usage_reports')
          .doc('latest')
          .get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
