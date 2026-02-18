import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class DuplicateAnalyticsScreen extends StatefulWidget {
  const DuplicateAnalyticsScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
    this.onShareCsv,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;
  final Future<void> Function(String csv)? onShareCsv;

  @override
  State<DuplicateAnalyticsScreen> createState() =>
      _DuplicateAnalyticsScreenState();
}

class _DuplicateAnalyticsScreenState extends State<DuplicateAnalyticsScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;

  Map<String, dynamic>? _analytics;
  bool _loading = true;
  String? _error;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  String? get _parentId {
    return widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
  }

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final parentId = _parentId;
      if (parentId == null || parentId.trim().isEmpty) {
        throw StateError('Not logged in');
      }

      final analytics =
          await _resolvedFirestoreService.getDuplicateAnalytics(parentId);

      if (!mounted) {
        return;
      }
      setState(() {
        _analytics = analytics;
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

  Future<void> _exportCsv() async {
    try {
      final parentId = _parentId;
      if (parentId == null || parentId.trim().isEmpty) {
        throw StateError('Not logged in');
      }

      final csv =
          await _resolvedFirestoreService.exportDuplicateClustersCSV(parentId);
      if (widget.onShareCsv != null) {
        await widget.onShareCsv!(csv);
      } else {
        await Share.share(
          csv,
          subject: 'TrustBridge Duplicate Report',
        );
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV exported')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicate Analytics'),
        actions: [
          IconButton(
            key: const Key('duplicate_analytics_refresh_button'),
            onPressed: _loadAnalytics,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            key: const Key('duplicate_analytics_export_button'),
            onPressed: _exportCsv,
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 44),
            const SizedBox(height: 10),
            const Text(
              'Unable to load duplicate analytics',
              style: TextStyle(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadAnalytics,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final analytics = _analytics ?? const <String, dynamic>{};
    final totalClusters = (analytics['totalDuplicateClusters'] as int?) ?? 0;
    final totalReports = (analytics['totalDuplicateReports'] as int?) ?? 0;
    final resolutionRate =
        (analytics['resolutionRate'] as num?)?.toDouble() ?? 0;

    if (analytics.isEmpty || totalClusters == 0 || totalReports == 0) {
      return _buildEmptyState();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(
          totalClusters: totalClusters,
          totalReports: totalReports,
          resolutionRate: resolutionRate,
        ),
        const SizedBox(height: 12),
        _buildTopIssuesCard(
          analytics['topIssues'] as List<dynamic>? ?? const <dynamic>[],
        ),
        const SizedBox(height: 12),
        _buildVelocityCard(
          average: (analytics['avgVelocityDays'] as num?)?.toDouble() ?? 0,
          fastest: (analytics['minVelocityDays'] as num?)?.toDouble() ?? 0,
          slowest: (analytics['maxVelocityDays'] as num?)?.toDouble() ?? 0,
        ),
        const SizedBox(height: 12),
        _buildCategoryBreakdownCard(
          analytics['categoryBreakdown'] as Map<String, dynamic>? ??
              const <String, dynamic>{},
        ),
        const SizedBox(height: 12),
        _buildVolumeTrendCard(
          analytics['volumeByWeek'] as Map<String, dynamic>? ??
              const <String, dynamic>{},
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.analytics_outlined,
                size: 64, color: Colors.blueGrey),
            const SizedBox(height: 14),
            const Text(
              'No duplicate reports yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Analytics appears after repeated reports are detected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required int totalClusters,
    required int totalReports,
    required double resolutionRate,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _summaryStat(
              label: 'Clusters',
              value: '$totalClusters',
              color: Colors.blue.shade700,
            ),
            _summaryStat(
              label: 'Reports',
              value: '$totalReports',
              color: Colors.orange.shade700,
            ),
            _summaryStat(
              label: 'Resolved',
              value: '${(resolutionRate * 100).toStringAsFixed(0)}%',
              color: Colors.green.shade700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildTopIssuesCard(List<dynamic> rawTopIssues) {
    if (rawTopIssues.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Duplicate Issues',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Most reported repeated issues',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ...rawTopIssues.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              if (item is! Map) {
                return const SizedBox.shrink();
              }
              final subject = (item['subject'] as String? ?? 'Unknown issue');
              final count = (item['count'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _rankColor(index).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: _rankColor(index),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(subject)),
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: Colors.orange.shade700,
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

  Color _rankColor(int rank) {
    switch (rank) {
      case 0:
        return Colors.red.shade700;
      case 1:
        return Colors.orange.shade700;
      case 2:
        return Colors.amber.shade800;
      default:
        return Colors.blue.shade700;
    }
  }

  Widget _buildVelocityCard({
    required double average,
    required double fastest,
    required double slowest,
  }) {
    if (average <= 0) {
      return const SizedBox.shrink();
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resolution Velocity',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Days from report to resolved',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            _velocityRow('Average', average, Colors.blue.shade700),
            const SizedBox(height: 8),
            _velocityRow('Fastest', fastest, Colors.green.shade700),
            const SizedBox(height: 8),
            _velocityRow('Slowest', slowest, Colors.red.shade700),
          ],
        ),
      ),
    );
  }

  Widget _velocityRow(String label, double days, Color color) {
    final normalized = (days / 7.0).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: normalized,
            color: color,
            minHeight: 8,
            backgroundColor: Colors.grey.shade300,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${days.toStringAsFixed(1)}d',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildCategoryBreakdownCard(
      Map<String, dynamic> rawCategoryBreakdown) {
    if (rawCategoryBreakdown.isEmpty) {
      return const SizedBox.shrink();
    }

    final sorted = rawCategoryBreakdown.entries.toList()
      ..sort((a, b) => ((b.value as num?)?.toInt() ?? 0)
          .compareTo((a.value as num?)?.toInt() ?? 0));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Category Breakdown',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Duplicate reports by topic',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ...sorted.map((entry) {
              final category = entry.key;
              final count = (entry.value as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      _categoryIcon(category),
                      size: 18,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(category)),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: Colors.blue.shade700,
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

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'VPN':
        return Icons.vpn_lock;
      case 'Notifications':
        return Icons.notifications_active;
      case 'Policy':
        return Icons.policy;
      case 'Crashes':
        return Icons.bug_report;
      case 'Requests':
        return Icons.request_page;
      case 'DNS':
        return Icons.dns;
      default:
        return Icons.category;
    }
  }

  Widget _buildVolumeTrendCard(Map<String, dynamic> rawVolumeByWeek) {
    if (rawVolumeByWeek.isEmpty) {
      return const SizedBox.shrink();
    }

    final entries = rawVolumeByWeek.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final maxValue = entries
        .map((entry) => (entry.value as num?)?.toInt() ?? 0)
        .fold<int>(0, (max, value) => value > max ? value : max);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Volume Trend',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Duplicate reports in the last 4 weeks',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ...entries.map((entry) {
              final count = (entry.value as num?)?.toInt() ?? 0;
              final normalized = maxValue == 0 ? 0.0 : count / maxValue;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(entry.key),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: normalized,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade300,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
