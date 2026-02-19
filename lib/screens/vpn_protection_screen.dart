import 'dart:async';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/dns_filter_engine.dart';
import 'package:trustbridge_app/services/dns_packet_parser.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_service.dart';
import 'package:trustbridge_app/services/performance_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';
import 'package:trustbridge_app/screens/dns_query_log_screen.dart';
import 'package:trustbridge_app/screens/domain_policy_tester_screen.dart';
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
  final NextDnsService _nextDnsService = const NextDnsService();
  final PerformanceService _performanceService = PerformanceService();

  VpnStatus _status = const VpnStatus.unsupported();
  bool _isBusy = false;
  bool _isRefreshingStatus = false;
  bool _isCheckingDns = false;
  bool _isSyncingRules = false;
  bool _isRestartingVpn = false;
  bool _isRequestingPermission = false;
  String? _dnsSelfCheckMessage;
  Timer? _statusAutoRefreshTimer;
  DateTime? _lastStatusRefreshAt;
  bool _ignoringBatteryOptimizations = true;
  bool _isOpeningBatterySettings = false;
  bool _isRunningReadinessTest = false;
  bool _isOpeningVpnSettings = false;
  bool _isOpeningPrivateDnsSettings = false;
  List<_ReadinessCheckItem> _readinessItems = const [];
  DateTime? _lastReadinessRunAt;
  RuleCacheSnapshot _ruleCacheSnapshot = const RuleCacheSnapshot.empty();
  bool _isClearingRuleCache = false;

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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vpnProtectionEngineTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            l10n.dnsFilteringFoundationTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.vpnIntroSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          _buildStatusCard(context),
          const SizedBox(height: 16),
          _buildSyncStatusCard(context),
          const SizedBox(height: 16),
          _buildPermissionRecoveryCard(context),
          const SizedBox(height: 16),
          _buildActionCard(context),
          const SizedBox(height: 16),
          _buildTelemetryCard(context),
          const SizedBox(height: 16),
          _buildRuleCacheCard(context),
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
    final l10n = AppLocalizations.of(context)!;
    final statusColor = _statusColor(_status);
    final statusLabel = _statusLabel(context, _status);

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
                    l10n.currentStatusLabel,
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
              tooltip: l10n.refreshStatusTooltip,
              onPressed: _isBusy ? null : _refreshStatus,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final syncService = context.watch<PolicyVpnSyncService?>();
    if (syncService == null) {
      return const SizedBox.shrink();
    }

    final result = syncService.lastSyncResult;
    final isSyncing = syncService.isSyncing;
    final iconColor = isSyncing
        ? Colors.blue
        : result?.success == false
            ? Colors.red
            : Colors.green;

    return Card(
      key: const Key('vpn_policy_sync_card'),
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
                Icon(Icons.sync, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  l10n.policySyncTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('vpn_policy_sync_now_button'),
                  onPressed: isSyncing ? null : syncService.syncNow,
                  child: isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.syncNowButton),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (result == null)
              Text(
                l10n.notYetSyncedMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else if (!result.success)
              Text(
                l10n.syncFailedMessage(result.error ?? l10n.errorGeneric),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red.shade700,
                    ),
              )
            else ...[
              _buildSyncMetricRow(
                context,
                icon: Icons.people_outline,
                label: l10n.childrenSyncedLabel,
                value: '${result.childrenSynced}',
              ),
              _buildSyncMetricRow(
                context,
                icon: Icons.block,
                label: l10n.categoriesBlockedMetricLabel,
                value: '${result.totalCategories}',
              ),
              _buildSyncMetricRow(
                context,
                icon: Icons.domain,
                label: l10n.domainsBlockedMetricLabel,
                value: '${result.totalDomains}',
              ),
              _buildSyncMetricRow(
                context,
                icon: Icons.access_time,
                label: l10n.lastSyncedLabel,
                value: _formatSyncTime(result.timestamp),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncMetricRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canEnable = _status.supported && !_status.isRunning;
    final canDisable = _status.supported && _status.isRunning;
    final canSyncRules = _status.supported &&
        _status.permissionGranted &&
        _status.isRunning &&
        !_isBusy;
    final canRestartVpn = _status.supported &&
        _status.permissionGranted &&
        _status.isRunning &&
        !_isBusy &&
        !_isSyncingRules;

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
                    ? l10n.processingLabel
                    : canEnable
                        ? l10n.enableProtectionButton
                        : canDisable
                            ? l10n.disableProtectionButton
                            : l10n.notAvailableLabel,
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
                _isSyncingRules
                    ? l10n.syncingButton
                    : l10n.syncPolicyRulesButton,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('vpn_restart_button'),
              onPressed:
                  _isRestartingVpn || !canRestartVpn ? null : _restartVpnNow,
              icon: _isRestartingVpn
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt),
              label: Text(
                _isRestartingVpn
                    ? l10n.restartingButton
                    : l10n.restartVpnServiceButton,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('vpn_view_logs_button'),
              onPressed: _status.supported ? _openDnsQueryLogs : null,
              icon: const Icon(Icons.list_alt),
              label: Text(l10n.viewDnsQueryLogsButton),
            ),
            TextButton.icon(
              key: const Key('vpn_nextdns_button'),
              onPressed: _status.supported ? _openNextDnsSettings : null,
              icon: const Icon(Icons.dns_outlined),
              label: Text(l10n.nextDnsIntegrationButton),
            ),
            TextButton.icon(
              key: const Key('vpn_domain_tester_button'),
              onPressed: _status.supported ? _openDomainTester : null,
              icon: const Icon(Icons.rule_folder_outlined),
              label: Text(l10n.domainPolicyTesterButton),
            ),
            const SizedBox(height: 10),
            if (!_status.supported)
              Text(
                l10n.vpnAndroidOnlyMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else if (!_status.permissionGranted)
              Text(
                l10n.vpnPermissionRequiredMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                    ),
              )
            else if (!_status.isRunning)
              Text(
                l10n.startProtectionHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else
              Text(
                l10n.protectionChangesHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionRecoveryCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_status.supported) {
      return const SizedBox.shrink();
    }

    final permissionColor = _status.permissionGranted
        ? Colors.green.shade700
        : Colors.orange.shade700;
    final permissionLabel = _status.permissionGranted
        ? l10n.vpnPermissionGrantedLabel
        : l10n.vpnPermissionRequiredLabel;

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
                Icon(
                  _status.permissionGranted
                      ? Icons.verified_user
                      : Icons.warning_amber_rounded,
                  color: permissionColor,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.permissionRecoveryTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              permissionLabel,
              key: const Key('vpn_permission_recovery_label'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: permissionColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('vpn_request_permission_button'),
                  onPressed: _isRequestingPermission
                      ? null
                      : _requestVpnPermissionOnly,
                  icon: _isRequestingPermission
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.vpn_key_outlined),
                  label: Text(
                    _isRequestingPermission
                        ? l10n.requestingButton
                        : l10n.requestPermissionButton,
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('vpn_open_vpn_settings_secondary_button'),
                  onPressed:
                      _isOpeningVpnSettings ? null : _openVpnSettingsShortcut,
                  icon: const Icon(Icons.settings_ethernet),
                  label: Text(l10n.vpnSettingsButton),
                ),
              ],
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
              label: 'Resolver Failures / Fallbacks',
              value:
                  '${_status.upstreamFailureCount} / ${_status.fallbackQueryCount}',
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
              label: 'Upstream DNS',
              value: _status.upstreamDns ?? 'Default (8.8.8.8)',
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
              'If NextDNS upstream is unreachable, VPN now auto-falls back to default DNS to keep internet working.',
            ),
            _buildBullet(
              context,
              'Some apps use encrypted DNS that can bypass local VPN DNS filtering. Configure NextDNS Integration to improve coverage.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('vpn_open_vpn_settings_button'),
                  onPressed:
                      _isOpeningVpnSettings ? null : _openVpnSettingsShortcut,
                  icon: _isOpeningVpnSettings
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.settings_ethernet),
                  label: Text(
                    _isOpeningVpnSettings ? 'Opening...' : 'Open VPN Settings',
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('vpn_open_private_dns_button'),
                  onPressed: _isOpeningPrivateDnsSettings
                      ? null
                      : _openPrivateDnsSettingsShortcut,
                  icon: _isOpeningPrivateDnsSettings
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.dns_outlined),
                  label: Text(
                    _isOpeningPrivateDnsSettings
                        ? 'Opening...'
                        : 'Open Private DNS',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleCacheCard(BuildContext context) {
    final hasRules = _ruleCacheSnapshot.categoryCount > 0 ||
        _ruleCacheSnapshot.domainCount > 0;
    final updatedLabel = _ruleCacheSnapshot.lastUpdatedAt == null
        ? 'Not synced yet'
        : '${_formatDateTime(_ruleCacheSnapshot.lastUpdatedAt!)} (${_formatRelativeTime(_ruleCacheSnapshot.lastUpdatedAt!)})';

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
                const Icon(Icons.storage_outlined),
                const SizedBox(width: 8),
                Text(
                  'Rule Cache',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildMetricRow(
              context,
              label: 'Persisted Categories',
              value: '${_ruleCacheSnapshot.categoryCount}',
            ),
            _buildMetricRow(
              context,
              label: 'Persisted Domains',
              value: '${_ruleCacheSnapshot.domainCount}',
            ),
            _buildMetricRow(
              context,
              label: 'Last Cache Update',
              value: updatedLabel,
            ),
            if (_ruleCacheSnapshot.sampleDomains.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Sample Domains: ${_ruleCacheSnapshot.sampleDomains.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ],
            if (_ruleCacheSnapshot.sampleCategories.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Sample Categories: ${_ruleCacheSnapshot.sampleCategories.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('vpn_clear_rule_cache_button'),
              onPressed:
                  _isClearingRuleCache || !hasRules ? null : _clearRuleCache,
              icon: _isClearingRuleCache
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
              label: Text(
                _isClearingRuleCache ? 'Clearing...' : 'Clear Rule Cache',
              ),
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

  String _statusLabel(BuildContext context, VpnStatus status) {
    final l10n = AppLocalizations.of(context)!;
    if (!status.supported) {
      return l10n.notAvailableLabel;
    }
    if (!status.permissionGranted) {
      return l10n.vpnPermissionRequiredLabel;
    }
    if (status.isRunning) {
      return l10n.protectionActiveMessage;
    }
    return l10n.protectionInactiveMessage;
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
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMd(locale).add_jms().format(dateTime);
  }

  String _formatRelativeTime(DateTime dateTime) {
    final l10n = AppLocalizations.of(context)!;
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 5) {
      return l10n.justNow;
    }
    if (diff.inMinutes < 1) {
      return l10n.justNow;
    }
    if (diff.inHours < 1) {
      return l10n.minutesAgo(diff.inMinutes);
    }
    if (diff.inDays < 1) {
      return l10n.hoursAgo(diff.inHours);
    }
    return l10n.daysAgo(diff.inDays);
  }

  String _formatSyncTime(DateTime time) {
    final l10n = AppLocalizations.of(context)!;
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) {
      return l10n.justNow;
    }
    if (diff.inMinutes < 60) {
      return l10n.minutesAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) {
      return l10n.hoursAgo(diff.inHours);
    }
    return l10n.daysAgo(diff.inDays);
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

    final trace = await _performanceService.startTrace('vpn_telemetry_fetch');
    final stopwatch = Stopwatch()..start();
    _isRefreshingStatus = true;
    VpnStatus status = _status;
    var ignoringBatteryOptimizations = _ignoringBatteryOptimizations;
    var ruleCache = _ruleCacheSnapshot;
    Object? refreshError;
    try {
      status = await _resolvedVpnService.getStatus();
      ignoringBatteryOptimizations =
          await _resolvedVpnService.isIgnoringBatteryOptimizations();
      ruleCache =
          await _resolvedVpnService.getRuleCacheSnapshot(sampleLimit: 4);
    } catch (error) {
      refreshError = error;
    } finally {
      _isRefreshingStatus = false;
      final elapsedSeconds = status.startedAt == null
          ? 0
          : DateTime.now().difference(status.startedAt!).inSeconds;
      final queriesPerSecX100 =
          (elapsedSeconds > 0 && status.queriesProcessed > 0)
              ? ((status.queriesProcessed / elapsedSeconds) * 100).round()
              : 0;
      final blockRatePct = (status.blockedRate * 100).round();
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.setMetric(
        trace,
        'queries_processed',
        status.queriesProcessed,
      );
      await _performanceService.setMetric(
        trace,
        'queries_blocked',
        status.queriesBlocked,
      );
      await _performanceService.setMetric(
        trace,
        'queries_allowed',
        status.queriesAllowed,
      );
      await _performanceService.setMetric(
        trace,
        'dns_queries_per_sec_x100',
        queriesPerSecX100,
      );
      await _performanceService.setMetric(
        trace,
        'dns_block_rate_pct',
        blockRatePct,
      );
      await _performanceService.setAttribute(
        trace,
        'vpn_running',
        status.isRunning ? 'true' : 'false',
      );
      await _performanceService.annotateThreshold(
        trace: trace,
        name: 'vpn_telemetry_ms',
        actualValue: stopwatch.elapsedMilliseconds,
        warningValue: PerformanceThresholds.vpnTelemetryFetchWarningMs,
      );
      await _performanceService.annotateThreshold(
        trace: trace,
        name: 'dns_block_rate_pct',
        actualValue: blockRatePct,
        warningValue: PerformanceThresholds.dnsBlockRateHighPct,
      );
      await _performanceService.stopTrace(trace);
    }

    if (!mounted) {
      return;
    }
    if (refreshError != null) {
      return;
    }
    setState(() {
      _status = status;
      _ignoringBatteryOptimizations = ignoringBatteryOptimizations;
      _ruleCacheSnapshot = ruleCache;
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
        upstreamDns: rules.upstreamDns,
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
      final resolverUpdated = await _resolvedVpnService.setUpstreamDns(
        upstreamDns: rules.upstreamDns,
      );
      final updated = await _resolvedVpnService.updateFilterRules(
        blockedCategories: rules.blockedCategories,
        blockedDomains: rules.blockedDomains,
      );
      if (!mounted) {
        return;
      }
      if (updated) {
        if (rules.upstreamDns != null) {
          _showMessage(
            resolverUpdated
                ? 'Policy rules and NextDNS resolver synced to active VPN.'
                : 'Policy rules synced. Resolver update not confirmed.',
          );
        } else {
          _showMessage('Policy rules synced to active VPN.');
        }
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

  Future<void> _restartVpnNow() async {
    setState(() => _isRestartingVpn = true);
    try {
      final rules = await _loadRulesForVpnStart();
      final restarted = await _resolvedVpnService.restartVpn(
        blockedCategories: rules.blockedCategories,
        blockedDomains: rules.blockedDomains,
        upstreamDns: rules.upstreamDns,
      );
      if (!mounted) {
        return;
      }
      if (restarted) {
        _showMessage(
          rules.upstreamDns == null
              ? 'VPN service restarted with latest policy rules.'
              : 'VPN service restarted with latest policy rules and NextDNS resolver.',
        );
      } else {
        _showMessage('Unable to restart VPN service.', isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to restart VPN service.', isError: true);
      }
    } finally {
      await _refreshStatus();
      if (mounted) {
        setState(() => _isRestartingVpn = false);
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

  Future<_VpnStartConfig> _loadRulesForVpnStart() async {
    final blockedCategories = <String>{'social-networks', 'adult-content'};
    final blockedDomains = <String>{...DnsFilterEngine.defaultSeedDomains};
    String? upstreamDns;
    final parentId = _parentId;

    if (parentId == null) {
      return _VpnStartConfig(
        blockedCategories: blockedCategories.toList()..sort(),
        blockedDomains: blockedDomains.toList()..sort(),
        upstreamDns: null,
      );
    }

    try {
      final parentProfile =
          await _resolvedFirestoreService.getParentProfile(parentId);
      final preferences = _toMap(parentProfile?['preferences']);
      final nextDnsEnabled = preferences['nextDnsEnabled'] == true;
      final rawProfileId = preferences['nextDnsProfileId'];
      final nextDnsProfileId = _nextDnsService.sanitizedProfileIdOrNull(
        rawProfileId is String ? rawProfileId : null,
      );
      if (nextDnsEnabled &&
          nextDnsProfileId != null &&
          _nextDnsService.isValidProfileId(nextDnsProfileId)) {
        upstreamDns = _nextDnsService.upstreamDnsHost(nextDnsProfileId);
      }

      final children = await _resolvedFirestoreService.getChildren(parentId);
      for (final child in children) {
        blockedCategories.addAll(child.policy.blockedCategories);
        blockedDomains.addAll(child.policy.blockedDomains);
      }
    } catch (_) {
      // Keep safe defaults when policy fetch fails.
    }

    return _VpnStartConfig(
      blockedCategories: blockedCategories.toList()..sort(),
      blockedDomains: blockedDomains.toList()..sort(),
      upstreamDns: upstreamDns,
    );
  }

  Map<String, dynamic> _toMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    return const {};
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

  Future<void> _openDomainTester() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DomainPolicyTesterScreen(
          vpnService: widget.vpnService,
        ),
      ),
    );
  }

  Future<void> _requestVpnPermissionOnly() async {
    if (!_status.supported) {
      return;
    }

    setState(() => _isRequestingPermission = true);
    try {
      final granted = await _resolvedVpnService.requestPermission();
      if (!mounted) {
        return;
      }
      if (granted) {
        _showMessage('VPN permission granted.');
      } else {
        _showMessage('VPN permission not granted.', isError: true);
      }
    } finally {
      await _refreshStatus();
      if (mounted) {
        setState(() => _isRequestingPermission = false);
      }
    }
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

  Future<void> _openVpnSettingsShortcut() async {
    setState(() => _isOpeningVpnSettings = true);
    try {
      final opened = await _resolvedVpnService.openVpnSettings();
      if (!mounted) {
        return;
      }
      if (!opened) {
        _showMessage('Unable to open VPN settings.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningVpnSettings = false);
      }
    }
  }

  Future<void> _openPrivateDnsSettingsShortcut() async {
    setState(() => _isOpeningPrivateDnsSettings = true);
    try {
      final opened = await _resolvedVpnService.openPrivateDnsSettings();
      if (!mounted) {
        return;
      }
      if (!opened) {
        _showMessage('Unable to open Private DNS settings.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningPrivateDnsSettings = false);
      }
    }
  }

  Future<void> _clearRuleCache() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear VPN Rule Cache?'),
        content: const Text(
          'This clears persisted domains/categories from native cache. '
          'If VPN is running, active rules are also reset until next sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (shouldClear != true) {
      return;
    }

    setState(() => _isClearingRuleCache = true);
    try {
      final cleared = await _resolvedVpnService.clearRuleCache();
      if (!mounted) {
        return;
      }
      if (cleared) {
        _showMessage('Native rule cache cleared.');
      } else {
        _showMessage('Unable to clear native rule cache.', isError: true);
      }
    } finally {
      await _refreshStatus();
      if (mounted) {
        setState(() => _isClearingRuleCache = false);
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

class _VpnStartConfig {
  const _VpnStartConfig({
    required this.blockedCategories,
    required this.blockedDomains,
    required this.upstreamDns,
  });

  final List<String> blockedCategories;
  final List<String> blockedDomains;
  final String? upstreamDns;
}

class _ReadinessCheckItem {
  const _ReadinessCheckItem({
    required this.passed,
    required this.message,
  });

  final bool passed;
  final String message;
}
