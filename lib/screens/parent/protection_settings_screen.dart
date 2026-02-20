import 'package:flutter/material.dart';

import '../../models/child_profile.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
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
  State<ProtectionSettingsScreen> createState() => _ProtectionSettingsScreenState();
}

class _ProtectionSettingsScreenState extends State<ProtectionSettingsScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;
  VpnStatus _vpnStatus = const VpnStatus.unsupported();

  bool _loadingStatus = true;
  bool _updating = false;
  bool _advancedVisible = false;

  bool _alertVpnDisabled = true;
  bool _alertBypassAttempts = true;

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
      final profile = await _resolvedFirestoreService.getParentProfile(parentId);
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
    final running = _vpnStatus.isRunning;
    final statusColor = running ? Colors.green : Colors.red;
    final lastSync = _vpnStatus.lastRuleUpdateAt;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🛡️ Protection Status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            if (children.isEmpty)
              const Text('No child devices connected yet.')
            else
              ...children.map((child) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${child.nickname}\'s Phone',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        running ? '✅ Active' : '🔴 Offline',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (lastSync != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last sync: ${_timeAgo(lastSync)}',
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
        const SnackBar(content: Text('Could not disable protection right now.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
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
