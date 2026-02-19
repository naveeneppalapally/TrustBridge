import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/app_usage_service.dart';
import '../widgets/skeleton_loaders.dart';

class UsageReportsScreen extends StatefulWidget {
  const UsageReportsScreen({
    super.key,
    this.showLoadingState = false,
    this.appUsageService,
  });

  final bool showLoadingState;
  final AppUsageService? appUsageService;

  @override
  State<UsageReportsScreen> createState() => _UsageReportsScreenState();
}

class _UsageReportsScreenState extends State<UsageReportsScreen> {
  AppUsageService? _appUsageService;
  UsageReportData? _report;
  bool _loading = true;
  String? _error;

  AppUsageService get _resolvedAppUsageService {
    _appUsageService ??= widget.appUsageService ?? AppUsageService();
    return _appUsageService!;
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
      final report = await _resolvedAppUsageService.getUsageReport(pastDays: 7);
      if (!mounted) {
        return;
      }
      setState(() {
        _report = report;
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
      body: _buildBody(),
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

    final report = _report;
    if (report == null) {
      return const Center(child: Text('No report data available.'));
    }
    if (!report.permissionGranted) {
      return _buildPermissionMissingState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _HeroStatsCard(report: report),
        const SizedBox(height: 14),
        _CategoryCard(report: report),
        const SizedBox(height: 14),
        _TrendCard(report: report),
        const SizedBox(height: 14),
        _MostUsedAppsCard(report: report),
      ],
    );
  }

  Widget _buildPermissionMissingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bar_chart_outlined, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Usage access required',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enable Android Usage Access so TrustBridge can show real app-time reports.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await _resolvedAppUsageService.openUsageAccessSettings();
                  },
                  child: const Text('Open Usage Access Settings'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _load,
                  child: const Text('I enabled it, refresh'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
