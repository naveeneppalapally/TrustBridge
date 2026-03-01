import 'package:flutter/material.dart';
import 'package:trustbridge_app/screens/change_password_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class SecurityControlsScreen extends StatefulWidget {
  const SecurityControlsScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<SecurityControlsScreen> createState() => _SecurityControlsScreenState();
}

class _SecurityControlsScreenState extends State<SecurityControlsScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;

  bool _biometricLoginEnabled = false;
  bool _isSavingBiometric = false;

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
    if (parentId == null || parentId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Security')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Security'),
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
          final securityMap = _asMap(profile?['security']);
          final activeSessions = _intValue(securityMap['activeSessions'], 1);
          final twoFactorEnabled =
              _boolValue(securityMap['twoFactorEnabled'], false);
          final accountEmail = _extractString(profile, 'email') ??
              (widget.parentIdOverride == null
                  ? _resolvedAuthService.currentUser?.email
                  : null);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Text(
                'Security',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Keep your TrustBridge app safe for parent-only controls',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 18),
              _buildSectionHeader('Lock Your TrustBridge App'),
              _buildAccessControlCard(context, parentId),
              const SizedBox(height: 8),
              Text(
                'Skip typing password - use fingerprint instead.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 18),
              _buildSectionHeader('Security Options'),
              _buildConfigurationCard(
                context,
                parentId: parentId,
                activeSessions: activeSessions,
                twoFactorEnabled: twoFactorEnabled,
                accountEmail: accountEmail,
              ),
              const SizedBox(height: 18),
              Container(
                key: const Key('security_encryption_info_card'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF93C5FD)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, color: Color(0xFF1D4ED8)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your data is secure and private.',
                        style: TextStyle(
                          color: Color(0xFF1E3A8A),
                          fontWeight: FontWeight.w600,
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildAccessControlCard(BuildContext context, String parentId) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        key: const Key('security_biometric_tile'),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.blue.withValues(alpha: 0.14),
          child: const Icon(Icons.fingerprint, color: Colors.blue),
        ),
        title: const Text('Use Fingerprint or Face to Open'),
        subtitle: const Text('Face unlock or fingerprint'),
        trailing: Switch(
          key: const Key('security_biometric_switch'),
          value: _biometricLoginEnabled,
          onChanged: _isSavingBiometric
              ? null
              : (value) {
                  _saveBiometricToggle(
                    parentId: parentId,
                    enabled: value,
                  );
                },
        ),
      ),
    );
  }

  Widget _buildConfigurationCard(
    BuildContext context, {
    required String parentId,
    required int activeSessions,
    required bool twoFactorEnabled,
    required String? accountEmail,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            key: const Key('security_change_password_tile'),
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openChangePassword(context, accountEmail),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('security_login_history_tile'),
            leading: const Icon(Icons.history),
            title: const Text('Devices That Opened TrustBridge'),
            subtitle: Text('Signed in on $activeSessions phone(s) right now'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _showInfo('Login history details are unavailable right now.'),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('security_two_factor_tile'),
            leading: const Icon(Icons.phonelink_lock_outlined),
            title: const Text('2-Step Login Protection'),
            subtitle: Text(twoFactorEnabled ? 'Enabled' : 'Disabled'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _toggleTwoFactor(parentId, twoFactorEnabled),
          ),
        ],
      ),
    );
  }

  Future<void> _saveBiometricToggle({
    required String parentId,
    required bool enabled,
  }) async {
    setState(() {
      _biometricLoginEnabled = enabled;
      _isSavingBiometric = true;
    });

    try {
      await _resolvedFirestoreService.updateParentPreferences(
        parentId: parentId,
        biometricLoginEnabled: enabled,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'Biometric unlock enabled' : 'Biometric unlock disabled',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _biometricLoginEnabled = !enabled;
      });
      _showInfo('Unable to update biometric setting: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBiometric = false;
        });
      }
    }
  }

  Future<void> _toggleTwoFactor(String parentId, bool current) async {
    try {
      await _resolvedFirestoreService.updateParentSecurityMetadata(
        parentId: parentId,
        twoFactorEnabled: !current,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !current ? 'Two-Factor Auth enabled' : 'Two-Factor Auth disabled',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showInfo('Unable to update two-factor setting: $error');
    }
  }

  Future<void> _openChangePassword(
    BuildContext context,
    String? accountEmail,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(
          authService: widget.authService,
          emailOverride: accountEmail,
        ),
      ),
    );
  }

  void _hydrateFromProfile(Map<String, dynamic>? profile) {
    final preferences = _asMap(profile?['preferences']);
    _biometricLoginEnabled =
        _boolValue(preferences['biometricLoginEnabled'], false);
  }

  bool _boolValue(Object? value, bool fallback) {
    return value is bool ? value : fallback;
  }

  int _intValue(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return const <String, dynamic>{};
  }

  String? _extractString(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
