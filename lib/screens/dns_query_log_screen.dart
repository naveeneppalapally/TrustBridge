import 'package:flutter/material.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';
import 'package:trustbridge_app/widgets/empty_state.dart';

class DnsQueryLogScreen extends StatefulWidget {
  const DnsQueryLogScreen({
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
  State<DnsQueryLogScreen> createState() => _DnsQueryLogScreenState();
}

class _DnsQueryLogScreenState extends State<DnsQueryLogScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;

  VpnStatus _status = const VpnStatus.unsupported();
  List<DnsQueryLogEntry> _entries = const [];
  bool _isLoading = false;
  bool _isClearing = false;
  String? _errorMessage;

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
    _refreshLogs();
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('DNS Query Log')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _resolvedFirestoreService.watchParentProfile(parentId),
      builder: (context, snapshot) {
        final incognitoEnabled = _isIncognitoEnabled(snapshot.data);
        return Scaffold(
          appBar: AppBar(
            title: const Text('DNS Query Log'),
            actions: [
              IconButton(
                key: const Key('dns_log_refresh_button'),
                tooltip: 'Refresh logs',
                onPressed: _isLoading || _isClearing ? null : _refreshLogs,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                key: const Key('dns_log_clear_button'),
                tooltip: 'Clear logs',
                onPressed: _isLoading ||
                        _isClearing ||
                        _entries.isEmpty ||
                        incognitoEnabled
                    ? null
                    : _clearLogs,
                icon: _isClearing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _buildStatusSummary(context),
              const SizedBox(height: 12),
              if (incognitoEnabled) _buildIncognitoModeCard(context),
              if (_errorMessage != null) ...[
                _buildErrorCard(context),
                const SizedBox(height: 12),
              ],
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!incognitoEnabled && _entries.isEmpty)
                _buildEmptyState(context)
              else if (!incognitoEnabled)
                ..._entries.map((entry) => _buildLogEntryCard(context, entry)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusSummary(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Overview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              _status.isRunning
                  ? 'VPN is active. Logs update while DNS traffic is processed.'
                  : 'VPN is not running. Start protection to collect query logs.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Processed: ${_status.queriesProcessed}  |  Blocked: ${_status.queriesBlocked}  |  Allowed: ${_status.queriesAllowed}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncognitoModeCard(BuildContext context) {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.visibility_off, color: Colors.amber.shade800),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                key: const Key('dns_log_privacy_mode_message'),
                'Incognito Mode is enabled. Domain query logs are hidden for privacy.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.amber.shade900,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.red.shade900,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: EmptyState(
          key: Key('dns_log_empty_state'),
          icon: Text('\u{1F50D}'),
          title: 'No queries yet',
          subtitle: 'Start VPN to see DNS activity.',
        ),
      ),
    );
  }

  Widget _buildLogEntryCard(BuildContext context, DnsQueryLogEntry entry) {
    final statusColor = entry.blocked ? Colors.red : Colors.green;
    final statusLabel = entry.blocked ? 'BLOCKED' : 'ALLOWED';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          entry.blocked ? Icons.block : Icons.check_circle,
          color: statusColor,
        ),
        title: Text(
          entry.domain,
          key: Key('dns_log_entry_${entry.domain}'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(_formatTimeAgo(entry.timestamp)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshLogs() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final status = await _resolvedVpnService.getStatus();
      final entries = await _resolvedVpnService.getRecentDnsQueries(limit: 120);
      if (!mounted) {
        return;
      }

      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() {
        _status = status;
        _entries = entries;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load DNS query logs: $error';
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear DNS Query Logs?'),
            content: const Text(
              'This removes locally captured domain query history from the current VPN session.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    setState(() => _isClearing = true);
    try {
      final success = await _resolvedVpnService.clearDnsQueryLogs();
      if (!mounted) {
        return;
      }
      if (success) {
        await _refreshLogs();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DNS query logs cleared.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to clear DNS query logs.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  bool _isIncognitoEnabled(Map<String, dynamic>? profile) {
    final preferences = _toMap(profile?['preferences']);
    return preferences['incognitoModeEnabled'] == true;
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

  String _formatTimeAgo(DateTime timestamp) {
    if (timestamp.millisecondsSinceEpoch <= 0) {
      return 'unknown time';
    }

    final difference = DateTime.now().difference(timestamp);
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }
    return '${difference.inDays}d ago';
  }
}
