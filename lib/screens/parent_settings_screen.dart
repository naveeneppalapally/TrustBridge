import 'package:flutter/material.dart';
import 'package:trustbridge_app/screens/privacy_center_screen.dart';
import 'package:trustbridge_app/screens/security_controls_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class ParentSettingsScreen extends StatefulWidget {
  const ParentSettingsScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<ParentSettingsScreen> createState() => _ParentSettingsScreenState();
}

class _ParentSettingsScreenState extends State<ParentSettingsScreen> {
  static const Map<String, String> _languageOptions = {
    'en': 'English',
    'hi': 'Hindi',
  };
  static const List<String> _timezoneOptions = [
    'Asia/Kolkata',
    'Asia/Dubai',
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
  ];

  AuthService? _authService;
  FirestoreService? _firestoreService;

  String _language = 'en';
  String _timezone = 'Asia/Kolkata';
  bool _pushNotificationsEnabled = true;
  bool _weeklySummaryEnabled = true;
  bool _securityAlertsEnabled = true;

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
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isSaving ? null : _saveSettings,
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
                        size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    const Text(
                      'Failed to load settings',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
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
                  : null) ??
              'No email linked';
          final accountPhone = _extractString(profile, 'phone') ??
              (widget.parentIdOverride == null
                  ? _resolvedAuthService.currentUser?.phoneNumber
                  : null) ??
              'No phone linked';
          final displayName = _extractString(profile, 'displayName') ??
              _displayNameFromEmail(accountEmail);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text(
                'Account & Preferences',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage your parent account settings and app preferences.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 16),
              _buildProfileCard(
                context,
                displayName: displayName,
                email: accountEmail,
              ),
              const SizedBox(height: 16),
              _buildSectionHeader('Account'),
              _buildAccountCard(context,
                  email: accountEmail, phone: accountPhone),
              const SizedBox(height: 16),
              _buildSectionHeader('Preferences'),
              _buildPreferencesCard(context),
              const SizedBox(height: 16),
              _buildSectionHeader('Notifications'),
              _buildNotificationsCard(context),
              const SizedBox(height: 16),
              _buildSectionHeader('Security & Privacy'),
              _buildSecurityCard(context),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileCard(
    BuildContext context, {
    required String displayName,
    required String email,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
              foregroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context, {
    required String email,
    required String phone,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.email_outlined, color: Colors.blue.shade600),
            title: const Text('Email'),
            subtitle: Text(email),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.phone_outlined, color: Colors.blue.shade600),
            title: const Text('Phone'),
            subtitle: Text(phone),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              key: const Key('settings_language_dropdown'),
              initialValue: _language,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Language',
                border: OutlineInputBorder(),
              ),
              items: _languageOptions.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value == null || value == _language) {
                        return;
                      }
                      setState(() {
                        _language = value;
                        _hasChanges = true;
                      });
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('settings_timezone_dropdown'),
              initialValue: _timezone,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Timezone',
                border: OutlineInputBorder(),
              ),
              items: _timezoneOptions
                  .map(
                    (timezone) => DropdownMenuItem<String>(
                      value: timezone,
                      child: Text(timezone),
                    ),
                  )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value == null || value == _timezone) {
                        return;
                      }
                      setState(() {
                        _timezone = value;
                        _hasChanges = true;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('settings_push_notifications_switch'),
            value: _pushNotificationsEnabled,
            title: const Text('Push Notifications'),
            subtitle: const Text('Important alerts and updates'),
            onChanged: _isSaving
                ? null
                : (value) {
                    setState(() {
                      _pushNotificationsEnabled = value;
                      _hasChanges = true;
                    });
                  },
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const Key('settings_weekly_summary_switch'),
            value: _weeklySummaryEnabled,
            title: const Text('Weekly Summary'),
            subtitle: const Text('Receive weekly activity digest'),
            onChanged: _isSaving
                ? null
                : (value) {
                    setState(() {
                      _weeklySummaryEnabled = value;
                      _hasChanges = true;
                    });
                  },
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const Key('settings_security_alerts_switch'),
            value: _securityAlertsEnabled,
            title: const Text('Security Alerts'),
            subtitle: const Text('Immediate notification for high-risk events'),
            onChanged: _isSaving
                ? null
                : (value) {
                    setState(() {
                      _securityAlertsEnabled = value;
                      _hasChanges = true;
                    });
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ListTile(
            leading:
                Icon(Icons.privacy_tip_outlined, color: Colors.green.shade700),
            title: const Text('Privacy Center'),
            subtitle: const Text('Manage data and visibility settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => _openPrivacyCenter(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.shield_outlined, color: Colors.green.shade700),
            title: const Text('Security Controls'),
            subtitle: const Text('Biometric login and account protections'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => _openSecurityControls(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
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
        language: _language,
        timezone: _timezone,
        pushNotificationsEnabled: _pushNotificationsEnabled,
        weeklySummaryEnabled: _weeklySummaryEnabled,
        securityAlertsEnabled: _securityAlertsEnabled,
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
          content: Text('Settings updated successfully'),
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
            content: Text('Unable to update settings: $error'),
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

  Future<void> _signOut() async {
    await _resolvedAuthService.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed('/login');
  }

  Future<void> _openPrivacyCenter(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivacyCenterScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openSecurityControls(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SecurityControlsScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  void _hydrateFromProfile(Map<String, dynamic>? profile) {
    if (_hasChanges) {
      return;
    }

    final preferences = _mapValue(profile?['preferences']);
    _language = _normalizeLanguage(preferences['language']);
    _timezone = _normalizeTimezone(preferences['timezone']);
    _pushNotificationsEnabled =
        _boolValue(preferences['pushNotificationsEnabled'], true);
    _weeklySummaryEnabled =
        _boolValue(preferences['weeklySummaryEnabled'], true);
    _securityAlertsEnabled =
        _boolValue(preferences['securityAlertsEnabled'], true);
  }

  String _normalizeLanguage(Object? value) {
    if (value is String && _languageOptions.containsKey(value)) {
      return value;
    }
    return 'en';
  }

  String _normalizeTimezone(Object? value) {
    if (value is String && _timezoneOptions.contains(value)) {
      return value;
    }
    return 'Asia/Kolkata';
  }

  bool _boolValue(Object? value, bool fallback) {
    return value is bool ? value : fallback;
  }

  String? _extractString(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
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

  String _displayNameFromEmail(String email) {
    if (email.contains('@')) {
      final prefix = email.split('@').first.trim();
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
    }
    return 'Parent Account';
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
