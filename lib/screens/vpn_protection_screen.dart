import 'package:flutter/material.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/dns_filter_engine.dart';
import 'package:trustbridge_app/services/dns_packet_parser.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

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
  bool _isCheckingDns = false;
  String? _dnsSelfCheckMessage;

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
          _buildDnsSelfCheckCard(context),
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
            else
              Text(
                'Protection changes apply immediately for this device.',
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

  Future<void> _refreshStatus() async {
    final status = await _resolvedVpnService.getStatus();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
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

      final started = await _resolvedVpnService.startVpn();
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

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}
