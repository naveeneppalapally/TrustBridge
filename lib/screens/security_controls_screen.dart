import 'package:flutter/material.dart';
import 'package:trustbridge_app/screens/change_password_screen.dart';
import 'package:trustbridge_app/screens/vpn_protection_screen.dart';
import 'package:trustbridge_app/screens/vpn_test_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';
import 'package:trustbridge_app/utils/app_lock_guard.dart';

class SecurityControlsScreen extends StatefulWidget {
  const SecurityControlsScreen({
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
  State<SecurityControlsScreen> createState() => _SecurityControlsScreenState();
}

class _SecurityControlsScreenState extends State<SecurityControlsScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;

  bool _biometricLoginEnabled = false;
  bool _incognitoModeEnabled = false;
  bool _hasChanges = false;
  bool _isSaving = false;

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
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Security Controls')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Controls'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'SAVE',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _resolvedFirestoreService.watchParentProfile(parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    const Text(
                      'Unable to load security settings',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final profile = snapshot.data;
          _hydrateFromProfile(profile);
          final accountEmail = _extractString(profile, 'email') ??
              (widget.parentIdOverride == null
                  ? _resolvedAuthService.currentUser?.email
                  : null);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text(
                'Protect Your Account',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Configure login security and privacy mode controls.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const Key('security_biometric_switch'),
                      value: _biometricLoginEnabled,
                      title: const Text('Biometric Login'),
                      subtitle: const Text(
                        'Use fingerprint or face unlock to open app',
                      ),
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              setState(() {
                                _biometricLoginEnabled = value;
                                _hasChanges = true;
                              });
                            },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      key: const Key('security_incognito_switch'),
                      value: _incognitoModeEnabled,
                      title: const Text('Incognito Mode'),
                      subtitle: const Text(
                        'Hide sensitive activity details in shared spaces',
                      ),
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              setState(() {
                                _incognitoModeEnabled = value;
                                _hasChanges = true;
                              });
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _openChangePassword(context, accountEmail),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Change Password'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('security_vpn_button'),
                onPressed: _isSaving ? null : () => _openVpnProtection(context),
                icon: const Icon(Icons.shield_outlined),
                label: const Text('VPN Protection Engine'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('security_vpn_test_button'),
                onPressed: _isSaving ? null : () => _openVpnTest(context),
                child: const Text('VPN Test (Dev)'),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 18, color: Colors.green.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Security changes apply to this parent account only and sync across your signed-in devices.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade900,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_isSaving || !_hasChanges) {
      return;
    }

    final parentId = _parentId;
    if (parentId == null) {
      _showInfo('Not logged in');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _resolvedFirestoreService.updateParentPreferences(
        parentId: parentId,
        biometricLoginEnabled: _biometricLoginEnabled,
        incognitoModeEnabled: _incognitoModeEnabled,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _hasChanges = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Security settings updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Save Failed'),
            content: Text('Unable to update security settings: $error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  void _hydrateFromProfile(Map<String, dynamic>? profile) {
    if (_hasChanges) {
      return;
    }

    final preferences = _mapValue(profile?['preferences']);
    _biometricLoginEnabled =
        _boolValue(preferences['biometricLoginEnabled'], false);
    _incognitoModeEnabled =
        _boolValue(preferences['incognitoModeEnabled'], false);
  }

  bool _boolValue(Object? value, bool fallback) {
    return value is bool ? value : fallback;
  }

  Map<String, dynamic> _mapValue(Object? value) {
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

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openChangePassword(BuildContext context, String? email) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(
          authService: widget.authService,
          emailOverride: email,
        ),
      ),
    );
  }

  Future<void> _openVpnProtection(BuildContext context) async {
    await guardedNavigate(
      context,
      () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VpnProtectionScreen(
              authService: widget.authService,
              firestoreService: widget.firestoreService,
              vpnService: widget.vpnService,
              parentIdOverride: widget.parentIdOverride,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openVpnTest(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VpnTestScreen(
          vpnService: widget.vpnService,
        ),
      ),
    );
  }

  String? _extractString(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}
