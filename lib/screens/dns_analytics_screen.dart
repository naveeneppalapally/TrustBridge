import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class DnsAnalyticsScreen extends StatefulWidget {
  const DnsAnalyticsScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.vpnService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final VpnServiceBase? vpnService;
  final String? parentIdOverride;

  @override
  State<DnsAnalyticsScreen> createState() => _DnsAnalyticsScreenState();
}

class _DnsAnalyticsScreenState extends State<DnsAnalyticsScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;

  VpnTelemetry _telemetry = VpnTelemetry.empty();
  List<ChildProfile> _children = const <ChildProfile>[];
  Map<String, dynamic>? _parentPreferences;
  Map<String, int> _topBlockedDomains = const <String, int>{};

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

  VpnServiceBase get _resolvedVpnService {
    _vpnService ??= widget.vpnService ?? VpnService();
    return _vpnService!;
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
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final parentId = _parentId;
      if (parentId == null || parentId.isEmpty) {
        throw StateError('Not logged in');
      }

      final results = await Future.wait<dynamic>([
        _resolvedFirestoreService.getChildrenOnce(parentId),
        _resolvedFirestoreService.getParentPreferences(parentId),
      ]);
      final children = results[0] as List<ChildProfile>;
      final parentPreferences = results[1] as Map<String, dynamic>?;
      final telemetryPayload = await _loadFleetTelemetry(
        parentId: parentId,
        children: children,
      );
      final topBlockedDomains = await _loadTopBlockedDomains(children);

      setState(() {
        _telemetry = telemetryPayload.telemetry;
        _topBlockedDomains = topBlockedDomains;
        _children = children;
        _parentPreferences = parentPreferences;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Analytics unavailable right now.';
      });
    }
  }

  Future<({VpnTelemetry telemetry, Map<String, DeviceStatusSnapshot> statuses})>
      _loadFleetTelemetry({
    required String parentId,
    required List<ChildProfile> children,
  }) async {
    final deviceIds = children
        .expand((child) => child.deviceIds)
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    final childIdByDeviceId = <String, String>{
      for (final child in children)
        for (final deviceId in child.deviceIds)
          if (deviceId.trim().isNotEmpty) deviceId.trim(): child.id,
    };

    if (deviceIds.isNotEmpty) {
      try {
        final statuses = await _resolvedFirestoreService
            .watchDeviceStatuses(
              deviceIds,
              parentId: parentId,
              childIdByDeviceId: childIdByDeviceId,
            )
            .first
            .timeout(const Duration(seconds: 8));
        var totalProcessed = 0;
        var totalBlocked = 0;
        var totalAllowed = 0;
        var anyVpnRunning = false;
        for (final status in statuses.values) {
          final processed = status.queriesProcessed > 0
              ? status.queriesProcessed
              : status.queriesBlocked + status.queriesAllowed;
          totalProcessed += processed;
          totalBlocked += status.queriesBlocked;
          totalAllowed += status.queriesAllowed;
          if (status.vpnActive) {
            anyVpnRunning = true;
          }
        }
        return (
          telemetry: VpnTelemetry(
            queriesIntercepted: totalProcessed,
            queriesBlocked: totalBlocked,
            queriesAllowed: totalAllowed,
            isRunning: anyVpnRunning,
          ),
          statuses: statuses,
        );
      } catch (_) {
        // Fall back to local status when fleet telemetry cannot be loaded.
      }
    }

    final localStatus = await _resolvedVpnService.getStatus();
    return (
      telemetry: VpnTelemetry.fromStatus(localStatus),
      statuses: const <String, DeviceStatusSnapshot>{},
    );
  }

  Future<Map<String, int>> _loadTopBlockedDomains(
    List<ChildProfile> children,
  ) async {
    final fleetCounts = <String, int>{};
    for (final child in children) {
      final childId = child.id.trim();
      if (childId.isEmpty) {
        continue;
      }
      try {
        final diagnosticsDoc = await _resolvedFirestoreService.firestore
            .collection('children')
            .doc(childId)
            .collection('vpn_diagnostics')
            .doc('current')
            .get();
        final diagnostics = diagnosticsDoc.data() ?? const <String, dynamic>{};
        final blockedQuery = _mapValue(diagnostics['lastBlockedDnsQuery']);
        final rawDomain = (blockedQuery['domain'] as String?)?.trim();
        if (rawDomain == null || rawDomain.isEmpty) {
          continue;
        }
        final domain = rawDomain.toLowerCase();
        fleetCounts.update(domain, (value) => value + 1, ifAbsent: () => 1);
      } catch (_) {
        // Best effort per child.
      }
    }

    if (fleetCounts.isNotEmpty) {
      final sorted = fleetCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return Map<String, int>.fromEntries(sorted.take(5));
    }

    try {
      final localLogs =
          await _resolvedVpnService.getRecentDnsQueries(limit: 300);
      return _calculateTopBlockedDomains(localLogs);
    } catch (_) {
      return const <String, int>{};
    }
  }

  Map<String, dynamic> _mapValue(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }
    if (rawValue is Map) {
      return rawValue.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protection Analytics'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: 'Refresh',
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
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 44),
            const SizedBox(height: 10),
            Text(
              _error ?? 'Analytics unavailable right now.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadAll,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeroCard(_telemetry),
        const SizedBox(height: 16),
        if (!_telemetry.isRunning) ...[
          _buildVpnOffBanner(),
          const SizedBox(height: 16),
        ],
        if (_telemetry.queriesIntercepted > 0) ...[
          _buildBreakdownCard(_telemetry),
          const SizedBox(height: 16),
        ],
        _buildTopBlockedDomainsCard(),
        const SizedBox(height: 16),
        if (_children.isNotEmpty) ...[
          _buildCategoryBreakdownCard(),
          const SizedBox(height: 16),
          _buildPerChildSummaryCard(),
          const SizedBox(height: 16),
        ],
        if (_isNextDnsEnabled()) ...[
          _buildNextDnsCard(),
          const SizedBox(height: 16),
        ],
        if (_telemetry.upstreamFailureCount > 0 ||
            _telemetry.fallbackQueryCount > 0) ...[
          _buildResolverHealthCard(_telemetry),
          const SizedBox(height: 16),
        ],
        _buildPrivacyNote(),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildHeroCard(VpnTelemetry telemetry) {
    final blockRateLabel = (telemetry.blockRate * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.shield_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            '${telemetry.queriesBlocked}',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          Text(
            'queries blocked',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatPill(
                label: 'Intercepted',
                value: '${telemetry.queriesIntercepted}',
                color: Colors.blue,
              ),
              _buildStatPill(
                label: 'Allowed',
                value: '${telemetry.queriesAllowed}',
                color: Colors.green,
              ),
              _buildStatPill(
                label: 'Block rate',
                value: '$blockRateLabel%',
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildVpnOffBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No active protection signal from child devices right now.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.orange.shade900,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard(VpnTelemetry telemetry) {
    final blockedPercent = (telemetry.blockRate * 100).round().clamp(0, 100);
    final allowedPercent = 100 - blockedPercent;
    final blockedFlex = blockedPercent == 0 ? 1 : blockedPercent;
    final allowedFlex = allowedPercent == 0 ? 1 : allowedPercent;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Traffic Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  Expanded(
                    flex: blockedFlex,
                    child: Container(
                      height: 12,
                      color: Colors.red.withValues(alpha: 0.76),
                    ),
                  ),
                  Expanded(
                    flex: allowedFlex,
                    child: Container(
                      height: 12,
                      color: Colors.green.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _legendItem(
                  color: Colors.red.withValues(alpha: 0.76),
                  label: 'Blocked ($blockedPercent%)',
                ),
                _legendItem(
                  color: Colors.green.withValues(alpha: 0.58),
                  label: 'Allowed ($allowedPercent%)',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildTopBlockedDomainsCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Blocked Domains',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'From on-device DNS query logs',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 12),
            if (_topBlockedDomains.isEmpty)
              Text(
                'No blocked domain data yet. Once filtering runs, top domains will appear here.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else
              ..._topBlockedDomains.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${entry.value}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
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

  Widget _buildCategoryBreakdownCard() {
    final categoryCounts = <String, int>{};
    for (final child in _children) {
      for (final category in child.policy.blockedCategories) {
        categoryCounts.update(category, (value) => value + 1,
            ifAbsent: () => 1);
      }
    }
    final sorted = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Category Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'How many child profiles block each category',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 12),
            if (sorted.isEmpty)
              Text(
                'No blocked categories configured yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else
              ...sorted.take(6).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(_formatCategoryName(entry.key))),
                          _countBadge('${entry.value} child'),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerChildSummaryCard() {
    final rows = _children.map(_buildChildScore).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final topChild = rows.isEmpty ? null : rows.first;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Per-Child Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            if (topChild != null)
              Text(
                '${topChild.nickname} currently has the strongest blocking policy configured.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            const SizedBox(height: 12),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.14),
                      child: Text(
                        row.nickname[0].toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        row.nickname,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    _countBadge('${row.categoryCount} categories'),
                    const SizedBox(width: 6),
                    _countBadge('${row.domainCount} domains'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.blue.shade700,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildNextDnsCard() {
    final profileId =
        (_parentPreferences?['nextDnsProfileId'] as String? ?? '').trim();
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'NextDNS Analytics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Open your NextDNS dashboard for deeper resolver analytics and query-level insights.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openNextDnsDashboard(profileId),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open NextDNS Dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNextDnsDashboard(String profileId) async {
    final targetUrl = profileId.isEmpty
        ? 'https://my.nextdns.io'
        : 'https://my.nextdns.io/$profileId/analytics';
    final uri = Uri.parse(targetUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open NextDNS dashboard.')),
      );
    }
  }

  Widget _buildResolverHealthCard(VpnTelemetry telemetry) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resolver Health',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            _metricRow(
              label: 'Primary DNS failures',
              value: '${telemetry.upstreamFailureCount}',
              valueColor: telemetry.upstreamFailureCount > 0
                  ? Colors.orange.shade800
                  : Colors.green.shade700,
            ),
            const SizedBox(height: 6),
            _metricRow(
              label: 'Fallback queries used',
              value: '${telemetry.fallbackQueryCount}',
              valueColor: telemetry.fallbackQueryCount > 0
                  ? Colors.blue.shade700
                  : Colors.green.shade700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildPrivacyNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'We track counts, not content. TrustBridge does not collect browsing history.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _calculateTopBlockedDomains(List<DnsQueryLogEntry> entries) {
    final counts = <String, int>{};
    for (final entry in entries) {
      if (!entry.blocked) {
        continue;
      }
      final domain = entry.domain.trim().toLowerCase();
      if (domain.isEmpty || domain == '<unknown>') {
        continue;
      }
      counts.update(domain, (value) => value + 1, ifAbsent: () => 1);
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(sorted.take(5));
  }

  _ChildPolicySummary _buildChildScore(ChildProfile child) {
    final categoryCount = child.policy.blockedCategories.length;
    final domainCount = child.policy.blockedDomains.length;
    final score = (categoryCount * 5) + domainCount;
    return _ChildPolicySummary(
      nickname: child.nickname,
      categoryCount: categoryCount,
      domainCount: domainCount,
      score: score,
    );
  }

  String _formatCategoryName(String category) {
    return category
        .split('-')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  bool _isNextDnsEnabled() {
    final enabled = _parentPreferences?['nextDnsEnabled'] == true;
    final profileId =
        (_parentPreferences?['nextDnsProfileId'] as String? ?? '').trim();
    return enabled && profileId.isNotEmpty;
  }
}

class _ChildPolicySummary {
  const _ChildPolicySummary({
    required this.nickname,
    required this.categoryCount,
    required this.domainCount,
    required this.score,
  });

  final String nickname;
  final int categoryCount;
  final int domainCount;
  final int score;
}
