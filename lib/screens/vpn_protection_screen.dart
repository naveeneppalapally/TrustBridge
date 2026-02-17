import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/dns_filter_engine.dart';
import 'package:trustbridge_app/services/dns_packet_parser.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';
import 'package:trustbridge_app/screens/dns_query_log_screen.dart';
import 'package:trustbridge_app/screens/nextdns_settings_screen.dart';

class VpnProtectionScreen extends StatefulWidget {
  const VpnProtectionScreen({
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
  State<VpnProtectionScreen> createState() => _VpnProtectionScreenState();
}

class _VpnProtectionScreenState extends State<VpnProtectionScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;
  late final DnsFilterEngine _dnsFilterEngine;

  VpnStatus _status = const VpnStatus.unsupported();
  bool _isBusy = false;
  bool _isRefreshingStatus = false;
  bool _isCheckingDns = false;
  bool _isSyncingRules = false;
  String? _dnsSelfCheckMessage;
  Timer? _statusAutoRefreshTimer;
  DateTime? _lastStatusRefreshAt;
  bool _ignoringBatteryOptimizations = true;
  bool _isOpeningBatterySettings = false;
  bool _isRunningReadinessTest = false;
  List<_ReadinessCheckItem> _readinessItems = const [];
  DateTime? _lastReadinessRunAt;

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
    return widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
  }

  @override
  void initState() {
    super.initState();
    _dnsFilterEngine = DnsFilterEngine(
      blockedDomains: DnsFilterEngine.defaultSeedDomains,
    );
    _refreshStatus();
    _startStatusAutoRefresh();
  }

  @override
  void dispose() {
    _statusAutoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VPN Protection Engine'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'DNS Filtering Foundation',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enable Android VPN permission to run TrustBridge network protection.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          _buildStatusCard(context),
          const SizedBox(height: 16),
          _buildActionCard(context),
          const SizedBox(height: 16),
          _buildTelemetryCard(context),
          const SizedBox(height: 16),
          _buildBatteryCard(context),
          const SizedBox(height: 16),
          _buildReadinessCard(context),
          const SizedBox(height: 16),
          _buildDnsSelfCheckCard(context),
          const SizedBox(height: 16),
          _buildDiagnosticsCard(context),
          const SizedBox(height: 16),
          _buildInfoCard(context),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final statusColor = _statusColor(_status);
    final statusLabel = _statusLabel(_status);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _status.isRunning ? Icons.shield : Icons.shield_outlined,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Status',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusLabel,
                    key: const Key('vpn_status_label'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('vpn_refresh_button'),
              tooltip: 'Refresh status',
              onPressed: _isBusy ? null : _refreshStatus,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context) {
    final canEnable = _status.supported && !_status.isRunning;
    final canDisable = _status.supported && _status.isRunning;
    final canSyncRules = _status.supported &&
        _status.permissionGranted &&
        _status.isRunning &&
        !_isBusy;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const Key('vpn_primary_button'),
              onPressed: _isBusy
                  ? null
                  : canEnable
                      ? _enableProtection
                      : canDisable
                          ? _disableProtection
                          : null,
              icon: _isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(canEnable
                      ? Icons.play_arrow
                      : canDisable
                          ? Icons.stop
                          : Icons.block),
              label: Text(
                _isBusy
                    ? 'Processing...'
                    : canEnable
                        ? 'Enable Protection'
                        : canDisable
                            ? 'Disable Protection'
                            : 'Not Available',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('vpn_sync_rules_button'),
              onPressed:
                  _isSyncingRules || !canSyncRules ? null : _syncRulesNow,
              icon: _isSyncingRules
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(
                _isSyncingRules ? 'Syncing...' : 'Sync Policy Rules',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('vpn_view_logs_button'),
              onPressed: _status.supported ? _openDnsQueryLogs : null,
              icon: const Icon(Icons.list_alt),
              label: const Text('View DNS Query Logs'),
            ),
            TextButton.icon(
              key: const Key('vpn_nextdns_button'),
              onPressed: _status.supported ? _openNextDnsSettings : null,
              icon: const Icon(Icons.dns_outlined),
              label: const Text('NextDNS Integration'),
            ),
            const SizedBox(height: 10),
            if (!_status.supported)
              Text(
                'VPN engine is available on Android only.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else if (!_status.permissionGranted)
              Text(
                'VPN permission is required before protection can start.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                    ),
              )
            else if (!_status.isRunning)
              Text(
                'Start protection to enforce category and domain policies.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else
              Text(
                'Protection changes apply immediately. Sync after policy edits.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What this enables',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            _buildBullet(
              context,
              'Prepares Android VPN service integration for DNS filtering.',
            ),
            _buildBullet(
              context,
              'Provides the permission and lifecycle hooks used by future enforcement layers.',
            ),
            _buildBullet(
              context,
              'Persists VPN enabled state in parent preferences for cross-screen visibility.',
            ),
            _buildBullet(
              context,
              'Includes DNS query parsing and block decision engine self-checks.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryCard(BuildContext context) {
    final uptimeLabel = _formatUptime(_status.startedAt);
    final syncLabel = _status.lastRuleUpdateAt == null
        ? 'No rule sync yet'
        : '${_formatDateTime(_status.lastRuleUpdateAt!)} (${_formatRelativeTime(_status.lastRuleUpdateAt!)})';
    final lastRefreshLabel = _lastStatusRefreshAt == null
        ? 'Pending'
        : _formatDateTime(_lastStatusRefreshAt!);
    final blockRate = (_status.blockedRate * 100).toStringAsFixed(1);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live Status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            _buildMetricRow(
              context,
              label: 'Processed DNS Queries',
              value: '${_status.queriesProcessed}',
            ),
            _buildMetricRow(
              context,
              label: 'Blocked / Allowed',
              value: '${_status.queriesBlocked} / ${_status.queriesAllowed}',
            ),
            _buildMetricRow(
              context,
              label: 'Block Rate',
              value: '$blockRate%',
            ),
            _buildMetricRow(
              context,
              label: 'Rules (Categories / Domains)',
              value:
                  '${_status.blockedCategoryCount} / ${_status.blockedDomainCount}',
            ),
            _buildMetricRow(
              context,
              label: 'VPN Uptime',
              value: uptimeLabel,
            ),
            _buildMetricRow(
              context,
              label: 'Last Rules Sync',
              value: syncLabel,
            ),
            _buildMetricRow(
              context,
              label: 'Last Status Refresh',
              value: lastRefreshLabel,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If Blocking Seems Inconsistent',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            _buildBullet(
              context,
              'Set device Private DNS to Automatic or Off while VPN protection is active.',
            ),
            _buildBullet(
              context,
              'Disable browser Secure DNS / DNS-over-HTTPS if blocked sites still load.',
            ),
            _buildBullet(
              context,
              'Use Sync Policy Rules after changing blocked categories or custom domains.',
            ),
            _buildBullet(
              context,
              'Some apps use encrypted DNS that can bypass local VPN DNS filtering. NextDNS integration is planned.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryCard(BuildContext context) {
    final statusColor = _ignoringBatteryOptimizations
        ? Colors.green.shade700
        : Colors.orange.shade700;
    final statusLabel = _ignoringBatteryOptimizations
        ? 'Battery optimization ignored'
        : 'Battery optimization active';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_saver, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  'Battery Optimization',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              statusLabel,
              key: const Key('vpn_battery_status_label'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _ignoringBatteryOptimizations
                  ? 'TrustBridge is less likely to be stopped in the background.'
                  : 'Allow TrustBridge in battery settings for better VPN reliability.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('vpn_open_battery_settings_button'),
              onPressed: _isOpeningBatterySettings
                  ? null
                  : _openBatteryOptimizationSettings,
              icon: _isOpeningBatterySettings
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new),
              label: Text(_isOpeningBatterySettings
                  ? 'Opening...'
                  : 'Open Battery Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessCard(BuildContext context) {
    final passedCount = _readinessItems.where((item) => item.passed).length;
    final totalCount = _readinessItems.length;
    final summary = totalCount == 0
        ? 'Run the check to validate VPN reliability.'
        : '$passedCount/$totalCount checks passed';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 8),
                Text(
                  'VPN Readiness Test',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              summary,
              key: const Key('vpn_readiness_summary'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_lastReadinessRunAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last run: ${_formatRelativeTime(_lastReadinessRunAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('vpn_run_health_check_button'),
              onPressed: _isRunningReadinessTest ? null : _runReadinessTest,
              icon: _isRunningReadinessTest
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_outlined),
              label: Text(
                _isRunningReadinessTest ? 'Running...' : 'Run Readiness Test',
              ),
            ),
            if (_readinessItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._readinessItems.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.passed ? Icons.check_circle : Icons.warning_amber,
                        size: 18,
                        color: item.passed ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.message,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade800,
                                  ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDnsSelfCheckCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DNS Engine Self-check',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Runs a parser + block decision check using sample query: m.facebook.com',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('vpn_dns_self_check_button'),
              onPressed: _isCheckingDns ? null : _runDnsSelfCheck,
              icon: _isCheckingDns
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rule_folder_outlined),
              label: Text(_isCheckingDns ? 'Running...' : 'Run Self-check'),
            ),
            if (_dnsSelfCheckMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _dnsSelfCheckMessage!,
                key: const Key('vpn_dns_self_check_result'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(VpnStatus status) {
    if (!status.supported) {
      return Colors.grey.shade600;
    }
    if (!status.permissionGranted) {
      return Colors.orange.shade700;
    }
    if (status.isRunning) {
      return Colors.green.shade700;
    }
    return Colors.blue.shade700;
  }

  String _statusLabel(VpnStatus status) {
    if (!status.supported) {
      return 'Unsupported on this platform';
    }
    if (!status.permissionGranted) {
      return 'Permission required';
    }
    if (status.isRunning) {
      return 'Protection running';
    }
    return 'Ready to start';
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final hours = dateTime.hour.toString().padLeft(2, '0');
    final minutes = dateTime.minute.toString().padLeft(2, '0');
    final seconds = dateTime.second.toString().padLeft(2, '0');
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} $hours:$minutes:$seconds';
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 5) {
      return 'just now';
    }
    if (diff.inMinutes < 1) {
      return '${diff.inSeconds}s ago';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    }
    return '${diff.inDays}d ago';
  }

  String _formatUptime(DateTime? startedAt) {
    if (startedAt == null || !_status.isRunning) {
      return _status.isRunning ? 'Starting...' : 'Not running';
    }

    final diff = DateTime.now().difference(startedAt);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  Future<void> _refreshStatus() async {
    if (_isRefreshingStatus) {
      return;
    }

    _isRefreshingStatus = true;
    VpnStatus status = _status;
    var ignoringBatteryOptimizations = _ignoringBatteryOptimizations;
    try {
      status = await _resolvedVpnService.getStatus();
      ignoringBatteryOptimizations =
          await _resolvedVpnService.isIgnoringBatteryOptimizations();
    } finally {
      _isRefreshingStatus = false;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _ignoringBatteryOptimizations = ignoringBatteryOptimizations;
      _lastStatusRefreshAt = DateTime.now();
    });
  }

  void _startStatusAutoRefresh() {
    _statusAutoRefreshTimer?.cancel();
    _statusAutoRefreshTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _refreshStatus();
    });
  }

  Future<void> _enableProtection() async {
    setState(() => _isBusy = true);
    try {
      var permissionGranted = _status.permissionGranted;
      if (!permissionGranted) {
        permissionGranted = await _resolvedVpnService.requestPermission();
      }

      if (!permissionGranted) {
        if (!mounted) {
          return;
        }
        _showMessage(
          'VPN permission was not granted.',
          isError: true,
        );
        return;
      }

      final rules = await _loadRulesForVpnStart();
      final started = await _resolvedVpnService.startVpn(
        blockedCategories: rules.blockedCategories,
        blockedDomains: rules.blockedDomains,
      );
      if (!mounted) {
        return;
      }
      if (!started) {
        _showMessage('Unable to start VPN protection.', isError: true);
      } else {
        await _persistPreference(true);
        if (!mounted) {
          return;
        }
        _showMessage('VPN protection enabled.');
      }
    } finally {
      await _refreshStatus();
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _disableProtection() async {
    setState(() => _isBusy = true);
    try {
      final stopped = await _resolvedVpnService.stopVpn();
      if (!mounted) {
        return;
      }
      if (!stopped) {
        _showMessage('Unable to stop VPN protection.', isError: true);
      } else {
        await _persistPreference(false);
        if (!mounted) {
          return;
        }
        _showMessage('VPN protection disabled.');
      }
    } finally {
      await _refreshStatus();
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _syncRulesNow() async {
    setState(() => _isSyncingRules = true);
    try {
      final rules = await _loadRulesForVpnStart();
      final updated = await _resolvedVpnService.updateFilterRules(
        blockedCategories: rules.blockedCategories,
        blockedDomains: rules.blockedDomains,
      );
      if (!mounted) {
        return;
      }
      if (updated) {
        _showMessage('Policy rules synced to active VPN.');
      } else {
        _showMessage('Unable to sync VPN policy rules.', isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to sync VPN policy rules.', isError: true);
      }
    } finally {
      await _refreshStatus();
      if (mounted) {
        setState(() => _isSyncingRules = false);
      }
    }
  }

  Future<void> _persistPreference(bool enabled) async {
    final parentId = _parentId;
    if (parentId == null) {
      return;
    }
    await _resolvedFirestoreService.updateParentPreferences(
      parentId: parentId,
      vpnProtectionEnabled: enabled,
    );
  }

  Future<_VpnFilterRules> _loadRulesForVpnStart() async {
    final blockedCategories = <String>{'social-networks', 'adult-content'};
    final blockedDomains = <String>{...DnsFilterEngine.defaultSeedDomains};
    final parentId = _parentId;

    if (parentId == null) {
      return _VpnFilterRules(
        blockedCategories: blockedCategories.toList()..sort(),
        blockedDomains: blockedDomains.toList()..sort(),
      );
    }

    try {
      final children = await _resolvedFirestoreService.getChildren(parentId);
      for (final child in children) {
        blockedCategories.addAll(child.policy.blockedCategories);
        blockedDomains.addAll(child.policy.blockedDomains);
      }
    } catch (_) {
      // Keep safe defaults when policy fetch fails.
    }

    return _VpnFilterRules(
      blockedCategories: blockedCategories.toList()..sort(),
      blockedDomains: blockedDomains.toList()..sort(),
    );
  }

  Future<void> _runDnsSelfCheck() async {
    setState(() {
      _isCheckingDns = true;
      _dnsSelfCheckMessage = null;
    });

    final queryPacket = DnsPacketParser.buildQueryPacket('m.facebook.com');
    final decision = _dnsFilterEngine.evaluatePacket(queryPacket);
    final nxDomainPacket = decision.blocked
        ? DnsPacketParser.buildNxDomainResponse(queryPacket)
        : null;

    if (!mounted) {
      return;
    }

    final message = decision.parseError
        ? 'Self-check failed: parser could not decode sample query.'
        : decision.blocked &&
                nxDomainPacket != null &&
                nxDomainPacket.isNotEmpty
            ? 'Self-check passed: ${decision.domain} -> BLOCKED (NXDOMAIN ready).'
            : 'Self-check passed: ${decision.domain} -> ALLOWED.';

    setState(() {
      _isCheckingDns = false;
      _dnsSelfCheckMessage = message;
    });
  }

  Future<void> _openDnsQueryLogs() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DnsQueryLogScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          vpnService: widget.vpnService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openNextDnsSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NextDnsSettingsScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          vpnService: widget.vpnService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openBatteryOptimizationSettings() async {
    setState(() => _isOpeningBatterySettings = true);
    try {
      final opened =
          await _resolvedVpnService.openBatteryOptimizationSettings();
      if (!mounted) {
        return;
      }
      if (!opened) {
        _showMessage('Unable to open battery optimization settings.',
            isError: true);
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refreshStatus();
      if (mounted) {
        setState(() => _isOpeningBatterySettings = false);
      }
    }
  }

  Future<void> _runReadinessTest() async {
    setState(() => _isRunningReadinessTest = true);
    try {
      final checks = <_ReadinessCheckItem>[
        _ReadinessCheckItem(
          passed: _status.supported,
          message: _status.supported
              ? 'Platform support check passed.'
              : 'Platform support check failed.',
        ),
        _ReadinessCheckItem(
          passed: _status.permissionGranted,
          message: _status.permissionGranted
              ? 'VPN permission is granted.'
              : 'VPN permission is missing.',
        ),
        _ReadinessCheckItem(
          passed: _status.isRunning,
          message: _status.isRunning
              ? 'VPN service is running.'
              : 'VPN service is not running.',
        ),
        _ReadinessCheckItem(
          passed: _ignoringBatteryOptimizations,
          message: _ignoringBatteryOptimizations
              ? 'Battery optimization exemption is active.'
              : 'Battery optimization may stop VPN in background.',
        ),
        _ReadinessCheckItem(
          passed: _status.blockedDomainCount > 0,
          message: _status.blockedDomainCount > 0
              ? 'DNS rules are loaded (${_status.blockedDomainCount} domains).'
              : 'No DNS rules were reported by the service.',
        ),
      ];

      if (_status.isRunning) {
        final recentQueries =
            await _resolvedVpnService.getRecentDnsQueries(limit: 1);
        checks.add(
          _ReadinessCheckItem(
            passed: recentQueries.isNotEmpty,
            message: recentQueries.isNotEmpty
                ? 'Recent DNS traffic observed.'
                : 'No DNS traffic observed yet. Browse a website and retry.',
          ),
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _readinessItems = checks;
        _lastReadinessRunAt = DateTime.now();
      });
    } finally {
      if (mounted) {
        setState(() => _isRunningReadinessTest = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}

class _VpnFilterRules {
  const _VpnFilterRules({
    required this.blockedCategories,
    required this.blockedDomains,
  });

  final List<String> blockedCategories;
  final List<String> blockedDomains;
}

class _ReadinessCheckItem {
  const _ReadinessCheckItem({
    required this.passed,
    required this.message,
  });

  final bool passed;
  final String message;
}
