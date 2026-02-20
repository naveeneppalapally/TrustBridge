import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

/// Parent alert preference configuration screen.
class AlertPreferencesScreen extends StatefulWidget {
  const AlertPreferencesScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<AlertPreferencesScreen> createState() => _AlertPreferencesScreenState();
}

class _AlertPreferencesScreenState extends State<AlertPreferencesScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;

  bool _loading = true;
  bool _saving = false;

  bool _vpnDisabled = true;
  bool _uninstallAttempt = true;
  bool _privateDnsChanged = true;
  bool _deviceOffline30m = true;
  bool _deviceOffline24h = true;
  bool _emailSerious = false;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
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
    _load();
  }

  Future<void> _load() async {
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return;
    }

    final prefs = await _resolvedFirestoreService.getAlertPreferences(parentId);
    if (!mounted) {
      return;
    }
    setState(() {
      _vpnDisabled = true;
      _uninstallAttempt = true;
      _privateDnsChanged = prefs['privateDnsChanged'] != false;
      _deviceOffline30m = prefs['deviceOffline30m'] != false;
      _deviceOffline24h = true;
      _emailSerious = prefs['emailSeriousAlerts'] == true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alert Preferences')),
        body: const Center(child: Text('Please sign in first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Alert Preferences')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const Text(
                  'Notify me when:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _buildToggle(
                  title: 'Protection turned off',
                  value: _vpnDisabled,
                  requiredAlert: true,
                  onChanged: (value) => _update(parentId, vpnDisabled: value),
                ),
                _buildToggle(
                  title: 'Uninstall attempt',
                  value: _uninstallAttempt,
                  requiredAlert: true,
                  onChanged: (value) => _update(parentId, uninstallAttempt: value),
                ),
                _buildToggle(
                  title: 'DNS settings changed',
                  value: _privateDnsChanged,
                  requiredAlert: false,
                  onChanged: (value) => _update(parentId, privateDnsChanged: value),
                ),
                _buildToggle(
                  title: 'Device offline (30 min)',
                  value: _deviceOffline30m,
                  requiredAlert: false,
                  onChanged: (value) => _update(parentId, deviceOffline30m: value),
                ),
                _buildToggle(
                  title: 'Device offline (24 hours)',
                  value: _deviceOffline24h,
                  requiredAlert: true,
                  onChanged: (value) => _update(parentId, deviceOffline24h: value),
                ),
                const Divider(height: 32),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _emailSerious,
                  title: const Text('Also send email for serious alerts'),
                  subtitle: const Text('(requires email on file)'),
                  onChanged: _saving
                      ? null
                      : (value) => _update(
                            parentId,
                            emailSeriousAlerts: value ?? false,
                          ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Some alerts cannot be turned off to ensure your child\'s safety.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
    );
  }

  Widget _buildToggle({
    required String title,
    required bool value,
    required bool requiredAlert,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      title: Row(
        children: [
          Expanded(child: Text(title)),
          if (requiredAlert)
            const Tooltip(
              message: 'This alert is required for your child\'s safety.',
              child: Icon(Icons.lock_outline, size: 18),
            ),
        ],
      ),
      onChanged: requiredAlert || _saving ? null : onChanged,
    );
  }

  Future<void> _update(
    String parentId, {
    bool? vpnDisabled,
    bool? uninstallAttempt,
    bool? privateDnsChanged,
    bool? deviceOffline30m,
    bool? deviceOffline24h,
    bool? emailSeriousAlerts,
  }) async {
    setState(() {
      _saving = true;
      if (vpnDisabled != null) {
        _vpnDisabled = vpnDisabled;
      }
      if (uninstallAttempt != null) {
        _uninstallAttempt = uninstallAttempt;
      }
      if (privateDnsChanged != null) {
        _privateDnsChanged = privateDnsChanged;
      }
      if (deviceOffline30m != null) {
        _deviceOffline30m = deviceOffline30m;
      }
      if (deviceOffline24h != null) {
        _deviceOffline24h = deviceOffline24h;
      }
      if (emailSeriousAlerts != null) {
        _emailSerious = emailSeriousAlerts;
      }
    });

    await _resolvedFirestoreService.updateAlertPreferences(
      parentId: parentId,
      vpnDisabled: vpnDisabled,
      uninstallAttempt: uninstallAttempt,
      privateDnsChanged: privateDnsChanged,
      deviceOffline30m: deviceOffline30m,
      deviceOffline24h: deviceOffline24h,
      emailSeriousAlerts: emailSeriousAlerts,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
    });
  }
}
