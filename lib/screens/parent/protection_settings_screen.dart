import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/child_profile.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/heartbeat_service.dart';
import '../../services/vpn_service.dart';
import '../../utils/parent_pin_gate.dart';

/// Parent-focused protection settings with a simple overview and gated advanced tools.
class ProtectionSettingsScreen extends StatefulWidget {
  const ProtectionSettingsScreen({
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
  State<ProtectionSettingsScreen> createState() =>
      _ProtectionSettingsScreenState();
}

class _ProtectionSettingsScreenState extends State<ProtectionSettingsScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;
  VpnStatus _vpnStatus = const VpnStatus.unsupported();

  bool _loadingStatus = true;
  bool _updating = false;
  bool _advancedVisible = false;
  bool _runningDiagnostics = false;
  List<_DiagnosticResult> _diagnosticResults = const <_DiagnosticResult>[];
  DateTime? _lastDiagnosticsAt;

  bool _alertVpnDisabled = true;
  bool _alertBypassAttempts = true;

  final Map<String, Future<_ChildRuntimeStatus>> _runtimeStatusFutures =
      <String, Future<_ChildRuntimeStatus>>{};

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
    return _resolvedAuthService.currentUser?.uid;
  }

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return;
    }

    try {
      final profile =
          await _resolvedFirestoreService.getParentProfile(parentId);
      final prefs = _asMap(profile?['preferences']);
      final status = await _resolvedVpnService.getStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _alertVpnDisabled = prefs['alertVpnDisabled'] != false;
        _alertBypassAttempts = prefs['alertBypassAttempts'] != false;
        _vpnStatus = status;
        _loadingStatus = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingStatus = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Protection Settings')),
        body: const Center(child: Text('Please sign in first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Protection Settings'),
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<ChildProfile>>(
              stream: _resolvedFirestoreService.getChildrenStream(parentId),
              builder: (context, snapshot) {
                final children = snapshot.data ?? const <ChildProfile>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _buildStatusCard(children),
                    const SizedBox(height: 16),
                    _buildDiagnosticsCard(parentId, children),
                    const SizedBox(height: 16),
                    _buildDecisionLogCard(children),
                    const SizedBox(height: 16),
                    _buildAlertTogglesCard(parentId),
                    const SizedBox(height: 16),
                    _buildAdvancedCard(parentId),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildStatusCard(List<ChildProfile> children) {
    final lastSync = _vpnStatus.lastRuleUpdateAt;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Protection Status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            if (children.isEmpty)
              const Text('No child devices connected yet.')
            else
              ...children.map((child) {
                return FutureBuilder<_ChildRuntimeStatus>(
                  future: _runtimeStatusFutureFor(child),
                  builder: (context, snapshot) {
                    final runtimeStatus =
                        snapshot.data ?? const _ChildRuntimeStatus.unknown();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${child.nickname}\'s Phone',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            runtimeStatus.label,
                            style: TextStyle(
                              color: runtimeStatus.color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }),
            if (lastSync != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last local VPN sync: ${_timeAgo(lastSync)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<_ChildRuntimeStatus> _runtimeStatusFutureFor(ChildProfile child) {
    final fingerprint = '${child.id}:${child.deviceIds.join(',')}';
    final cached = _runtimeStatusFutures[fingerprint];
    if (cached != null) {
      return cached;
    }
    final future = _loadChildRuntimeStatus(child);
    _runtimeStatusFutures[fingerprint] = future;
    return future;
  }

  Future<_ChildRuntimeStatus> _loadChildRuntimeStatus(
      ChildProfile child) async {
    if (child.deviceIds.isEmpty) {
      return const _ChildRuntimeStatus.notLinked();
    }

    Duration? bestAge;
    bool bestVpnActive = false;

    for (final deviceId in child.deviceIds) {
      final normalizedDeviceId = deviceId.trim();
      if (normalizedDeviceId.isEmpty) {
        continue;
      }

      Duration? age;
      try {
        age = await HeartbeatService.timeSinceLastSeen(normalizedDeviceId);
      } catch (_) {
        age = null;
      }

      var vpnActive = false;
      try {
        final deviceDoc = await FirebaseFirestore.instance
            .collection('children')
            .doc(child.id)
            .collection('devices')
            .doc(normalizedDeviceId)
            .get();
        if (deviceDoc.exists) {
          vpnActive = deviceDoc.data()?['vpnActive'] == true;
        }
      } catch (_) {
        vpnActive = false;
      }

      if (age == null) {
        continue;
      }

      if (bestAge == null || age < bestAge) {
        bestAge = age;
        bestVpnActive = vpnActive;
      }
    }

    if (bestAge == null) {
      return const _ChildRuntimeStatus.offline();
    }

    if (bestAge > const Duration(minutes: 30)) {
      return const _ChildRuntimeStatus.offline();
    }

    if (bestVpnActive) {
      return const _ChildRuntimeStatus.active();
    }

    return const _ChildRuntimeStatus.onlineVpnOff();
  }

  Widget _buildAlertTogglesCard(String parentId) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _alertVpnDisabled,
              title: const Text('Alert me if protection is disabled'),
              onChanged: _updating
                  ? null
                  : (value) => _saveAlertToggle(
                        parentId: parentId,
                        vpnDisabled: value,
                        bypassAttempts: null,
                      ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _alertBypassAttempts,
              title: const Text('Alert me on bypass attempts'),
              onChanged: _updating
                  ? null
                  : (value) => _saveAlertToggle(
                        parentId: parentId,
                        vpnDisabled: null,
                        bypassAttempts: value,
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsCard(String parentId, List<ChildProfile> children) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run Diagnostic',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Checks child VPN signal, blocking evidence, and Firestore connectivity.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _runningDiagnostics
                    ? null
                    : () =>
                        _runDiagnostics(parentId: parentId, children: children),
                icon: _runningDiagnostics
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.health_and_safety_outlined),
                label: Text(
                  _runningDiagnostics ? 'Running...' : 'Run Diagnostic',
                ),
              ),
            ),
            if (_lastDiagnosticsAt != null) ...[
              const SizedBox(height: 10),
              Text(
                'Last run: ${_timeAgo(_lastDiagnosticsAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (_diagnosticResults.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._diagnosticResults.map(_buildDiagnosticRow),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticRow(_DiagnosticResult result) {
    final color = result.passed ? Colors.green : Colors.red;
    final icon = result.passed ? Icons.check_circle : Icons.error_outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  result.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecisionLogCard(List<ChildProfile> children) {
    return FutureBuilder<List<_DnsDecisionEvent>>(
      future: _loadRecentDecisionEvents(children),
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <_DnsDecisionEvent>[];
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'DNS Decision Log',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Last 100 blocked/allowed DNS decisions across children.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                if (events.isEmpty)
                  const Text('No DNS decision logs yet.')
                else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _exportDecisionLog(events),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Export Log'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...events.take(12).map((event) {
                    final color = event.blocked ? Colors.red : Colors.green;
                    final status = event.blocked ? 'BLOCKED' : 'ALLOWED';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            event.blocked ? Icons.block : Icons.check_circle,
                            color: color,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${event.childName}: $status ${event.domain} (${_timeAgo(event.timestamp)})',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (events.length > 12)
                    Text(
                      'Showing 12 of ${events.length} entries. Export for full log.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdvancedCard(String parentId) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _toggleAdvanced,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Advanced (for troubleshooting)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    Icon(
                      _advancedVisible
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ],
                ),
              ),
            ),
            if (_advancedVisible) ...[
              const SizedBox(height: 8),
              Text(
                'These settings are for troubleshooting only. Contact support if you need help.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.health_and_safety_outlined),
                title: Text('VPN Diagnostics'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.network_check_outlined),
                title: Text('DNS Query Test'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.sync_alt_outlined),
                title: Text('Blocklist Sync Details'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.security_outlined),
                title: Text('Private DNS Detection Status'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _updating
                    ? null
                    : () => _disableProtectionWithPin(parentId),
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Disable protection now'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAdvanced() async {
    if (_advancedVisible) {
      setState(() {
        _advancedVisible = false;
      });
      return;
    }

    final authorized = await requireParentPin(context);
    if (!authorized) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _advancedVisible = true;
    });
  }

  Future<void> _disableProtectionWithPin(String parentId) async {
    final authorized = await requireParentPin(context);
    if (!authorized) {
      return;
    }

    setState(() {
      _updating = true;
    });
    try {
      final stopped = await _resolvedVpnService.stopVpn();
      if (stopped) {
        await _resolvedFirestoreService.updateParentPreferences(
          parentId: parentId,
          vpnProtectionEnabled: false,
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            stopped
                ? 'Protection disabled.'
                : 'Could not disable protection right now.',
          ),
        ),
      );
      await _loadStatus();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not disable protection right now.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Future<void> _runDiagnostics({
    required String parentId,
    required List<ChildProfile> children,
  }) async {
    if (_runningDiagnostics) {
      return;
    }
    setState(() {
      _runningDiagnostics = true;
    });

    final results = <_DiagnosticResult>[];

    final firestoreCheck = await () async {
      try {
        final profile = await _resolvedFirestoreService
            .getParentProfile(parentId)
            .timeout(const Duration(seconds: 8));
        if (profile == null) {
          return const _DiagnosticResult(
            title: 'Firestore connectivity',
            passed: false,
            message: 'Account profile is unavailable. Try re-login.',
          );
        }
        return const _DiagnosticResult(
          title: 'Firestore connectivity',
          passed: true,
          message: 'Cloud connection is healthy.',
        );
      } catch (_) {
        return const _DiagnosticResult(
          title: 'Firestore connectivity',
          passed: false,
          message: 'Could not reach cloud data. Check internet and retry.',
        );
      }
    }();
    results.add(firestoreCheck);

    final vpnSignalCheck = await () async {
      if (children.isEmpty) {
        return const _DiagnosticResult(
          title: 'Child VPN signal',
          passed: false,
          message: 'No child profiles found.',
        );
      }
      final deviceIds = <String>{
        for (final child in children)
          ...child.deviceIds
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty),
      }.toList(growable: false);
      if (deviceIds.isEmpty) {
        return const _DiagnosticResult(
          title: 'Child VPN signal',
          passed: false,
          message: 'No linked child devices yet.',
        );
      }

      try {
        final snapshots = await _resolvedFirestoreService
            .watchDeviceStatuses(deviceIds, parentId: parentId)
            .first
            .timeout(const Duration(seconds: 8));
        final now = DateTime.now();
        var activeSignal = false;
        for (final status in snapshots.values) {
          final seenAt = status.lastSeen ?? status.updatedAt;
          final recentlySeen = seenAt != null &&
              now.difference(seenAt) <= const Duration(minutes: 10);
          if (recentlySeen && status.vpnActive) {
            activeSignal = true;
            break;
          }
        }
        return _DiagnosticResult(
          title: 'Child VPN signal',
          passed: activeSignal,
          message: activeSignal
              ? 'Child device is online and VPN reports active.'
              : 'No recent active VPN signal from child devices. Open child app and check permissions.',
        );
      } catch (_) {
        return const _DiagnosticResult(
          title: 'Child VPN signal',
          passed: false,
          message: 'Could not read device status. Try again in a moment.',
        );
      }
    }();
    results.add(vpnSignalCheck);

    final blockingCheck = await () async {
      final events = await _loadRecentDecisionEvents(children);
      if (events.isEmpty) {
        return const _DiagnosticResult(
          title: 'Blocking evidence',
          passed: false,
          message:
              'No recent DNS decisions yet. Open a blocked app/site on child phone, then rerun.',
        );
      }
      final latestBlocked = events.firstWhere(
        (event) => event.blocked,
        orElse: () => _DnsDecisionEvent(
          childId: '',
          childName: '',
          domain: '',
          blocked: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      if (!latestBlocked.blocked || latestBlocked.domain.isEmpty) {
        return const _DiagnosticResult(
          title: 'Blocking evidence',
          passed: false,
          message:
              'No blocked DNS events found yet. Ensure at least one category is blocked.',
        );
      }
      final recent = DateTime.now().difference(latestBlocked.timestamp) <
          const Duration(minutes: 20);
      return _DiagnosticResult(
        title: 'Blocking evidence',
        passed: recent,
        message: recent
            ? 'Recent blocked DNS detected (${latestBlocked.domain}).'
            : 'Blocked DNS evidence is stale. Re-test from child device and rerun.',
      );
    }();
    results.add(blockingCheck);

    if (!mounted) {
      return;
    }
    setState(() {
      _runningDiagnostics = false;
      _lastDiagnosticsAt = DateTime.now();
      _diagnosticResults = results;
    });
  }

  Future<List<_DnsDecisionEvent>> _loadRecentDecisionEvents(
    List<ChildProfile> children,
  ) async {
    if (children.isEmpty) {
      return const <_DnsDecisionEvent>[];
    }
    final events = <_DnsDecisionEvent>[];
    for (final child in children) {
      try {
        final diagnosticsDoc = await _resolvedFirestoreService.firestore
            .collection('children')
            .doc(child.id)
            .collection('vpn_diagnostics')
            .doc('current')
            .get();
        final data = diagnosticsDoc.data() ?? const <String, dynamic>{};
        final rawQueries = data['recentQueries'];
        if (rawQueries is! List) {
          continue;
        }
        for (final entry in rawQueries) {
          if (entry is! Map) {
            continue;
          }
          final map = entry.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final domain = (map['domain'] as String?)?.trim() ?? '';
          if (domain.isEmpty) {
            continue;
          }
          final timestampEpoch =
              (map['timestampEpochMs'] as num?)?.toInt() ?? 0;
          if (timestampEpoch <= 0) {
            continue;
          }
          events.add(
            _DnsDecisionEvent(
              childId: child.id,
              childName: child.nickname,
              domain: domain,
              blocked: map['blocked'] == true,
              timestamp: DateTime.fromMillisecondsSinceEpoch(timestampEpoch),
              reasonCode: (map['reasonCode'] as String?)?.trim(),
              matchedRule: (map['matchedRule'] as String?)?.trim(),
            ),
          );
        }
      } catch (_) {
        // Continue collecting from other children.
      }
    }
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (events.length > 100) {
      return events.take(100).toList(growable: false);
    }
    return events;
  }

  Future<void> _exportDecisionLog(List<_DnsDecisionEvent> events) async {
    if (events.isEmpty) {
      return;
    }
    final csv = StringBuffer();
    csv.writeln('timestamp,child,decision,domain,reason,matched_rule');
    for (final event in events) {
      final timestamp = event.timestamp.toIso8601String();
      final decision = event.blocked ? 'blocked' : 'allowed';
      final childName = _escapeCsv(event.childName);
      final domain = _escapeCsv(event.domain);
      final reason = _escapeCsv(event.reasonCode ?? '');
      final matchedRule = _escapeCsv(event.matchedRule ?? '');
      csv.writeln(
          '$timestamp,$childName,$decision,$domain,$reason,$matchedRule');
    }
    await Share.share(
      csv.toString(),
      subject: 'TrustBridge DNS decision log',
    );
  }

  String _escapeCsv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _saveAlertToggle({
    required String parentId,
    required bool? vpnDisabled,
    required bool? bypassAttempts,
  }) async {
    setState(() {
      _updating = true;
      if (vpnDisabled != null) {
        _alertVpnDisabled = vpnDisabled;
      }
      if (bypassAttempts != null) {
        _alertBypassAttempts = bypassAttempts;
      }
    });

    try {
      await _resolvedFirestoreService.updateAlertPreferences(
        parentId: parentId,
        vpnDisabled: vpnDisabled,
        uninstallAttempt: bypassAttempts,
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, raw) => MapEntry(key.toString(), raw));
    }
    return const <String, dynamic>{};
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} h ago';
    }
    return '${diff.inDays} d ago';
  }
}

class _ChildRuntimeStatus {
  const _ChildRuntimeStatus({
    required this.label,
    required this.color,
  });

  const _ChildRuntimeStatus.active()
      : label = 'Active',
        color = Colors.green;

  const _ChildRuntimeStatus.onlineVpnOff()
      : label = 'Online, VPN off',
        color = Colors.orange;

  const _ChildRuntimeStatus.offline()
      : label = 'Offline',
        color = Colors.red;

  const _ChildRuntimeStatus.notLinked()
      : label = 'Not linked',
        color = Colors.grey;

  const _ChildRuntimeStatus.unknown()
      : label = 'Checking...',
        color = Colors.grey;

  final String label;
  final Color color;
}

class _DiagnosticResult {
  const _DiagnosticResult({
    required this.title,
    required this.passed,
    required this.message,
  });

  final String title;
  final bool passed;
  final String message;
}

class _DnsDecisionEvent {
  const _DnsDecisionEvent({
    required this.childId,
    required this.childName,
    required this.domain,
    required this.blocked,
    required this.timestamp,
    this.reasonCode,
    this.matchedRule,
  });

  final String childId;
  final String childName;
  final String domain;
  final bool blocked;
  final DateTime timestamp;
  final String? reasonCode;
  final String? matchedRule;
}
