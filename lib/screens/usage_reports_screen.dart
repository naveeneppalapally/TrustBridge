import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../widgets/skeleton_loaders.dart';

class UsageReportsScreen extends StatelessWidget {
  const UsageReportsScreen({
    super.key,
    this.showLoadingState = false,
  });

  final bool showLoadingState;

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
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: showLoadingState ? _buildLoadingState() : _buildContent(),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: const [
        _HeroStatsCard(),
        SizedBox(height: 14),
        _CategoryCard(),
        SizedBox(height: 14),
        _TrendCard(),
        SizedBox(height: 14),
        _MostUsedAppsCard(),
      ],
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
  const _HeroStatsCard();

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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Screen Time',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Text(
                '5h 47m',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 10),
              Text(
                '+12%',
                style: TextStyle(
                  color: Color(0xFFDDF3FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'DAILY AVERAGE: 4H 12M',
            style: TextStyle(
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
  const _CategoryCard();

  static const _sections = <_CategorySlice>[
    _CategorySlice('Social Media', 0.39, '2h 15m', Color(0xFF3B82F6)),
    _CategorySlice('Education', 0.35, '2h 02m', Color(0xFF10B981)),
    _CategorySlice('Games', 0.26, '1h 30m', Color(0xFFF59E0B)),
  ];

  @override
  Widget build(BuildContext context) {
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 52,
                      startDegreeOffset: -95,
                      sections: _sections
                          .map(
                            (item) => PieChartSectionData(
                              value: item.percent * 100,
                              color: item.color,
                              title: '',
                              radius: 46,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Mainly',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Social',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._sections.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: item.color,
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
                      item.time,
                      style: const TextStyle(
                        color: Colors.black87,
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
}

class _TrendCard extends StatelessWidget {
  const _TrendCard();

  static const _days = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _values = <double>[3.5, 4.1, 4.0, 3.8, 4.2, 5.3, 5.1];

  @override
  Widget build(BuildContext context) {
    final peak = _values.reduce((a, b) => a > b ? a : b);

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
                          if (index < 0 || index >= _days.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _days[index],
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
                  barGroups: _values.asMap().entries.map((entry) {
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Weekend screen time is 24% higher than usual. Consider setting a Saturday limit.',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w600,
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
  const _MostUsedAppsCard();

  static const _rows = <_AppUsageRow>[
    _AppUsageRow('YouTube', 'Entertainment', '1h 25m', 0.83, Icons.play_circle),
    _AppUsageRow('WhatsApp', 'Social', '1h 12m', 0.70, Icons.chat_bubble),
    _AppUsageRow('Chrome', 'Education', '58m', 0.56, Icons.public),
    _AppUsageRow('Roblox', 'Games', '44m', 0.42, Icons.sports_esports),
  ];

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
            ..._rows.map((row) => _UsageRowTile(row: row)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {},
                child: const Text('View All App Usage'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageRowTile extends StatelessWidget {
  const _UsageRowTile({required this.row});

  final _AppUsageRow row;

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
                child: Icon(row.icon, color: const Color(0xFF2563EB), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
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
                row.time,
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

class _CategorySlice {
  const _CategorySlice(this.label, this.percent, this.time, this.color);

  final String label;
  final double percent;
  final String time;
  final Color color;
}

class _AppUsageRow {
  const _AppUsageRow(
    this.name,
    this.category,
    this.time,
    this.progress,
    this.icon,
  );

  final String name;
  final String category;
  final String time;
  final double progress;
  final IconData icon;
}
