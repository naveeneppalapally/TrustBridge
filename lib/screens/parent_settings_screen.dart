import 'package:flutter/material.dart';
import 'package:trustbridge_app/l10n/app_localizations.dart';
import 'package:trustbridge_app/l10n/app_localizations_en.dart';
import 'package:trustbridge_app/screens/beta_feedback_history_screen.dart';
import 'package:trustbridge_app/screens/beta_feedback_screen.dart';
import 'package:trustbridge_app/screens/change_password_screen.dart';
import 'package:trustbridge_app/screens/help_support_screen.dart';
import 'package:trustbridge_app/screens/onboarding_screen.dart';
import 'package:trustbridge_app/screens/privacy_center_screen.dart';
import 'package:trustbridge_app/screens/security_controls_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final l10n = _l10n(context);
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.settingsTitle)),
        body: Center(child: Text(l10n.notLoggedInMessage)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
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
                  : Text(
                      l10n.saveButton.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _resolvedFirestoreService.watchParentProfile(parentId),
        builder: (
          BuildContext context,
          AsyncSnapshot<Map<String, dynamic>?> snapshot,
        ) {
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
                    Text('${snapshot.error}', textAlign: TextAlign.center),
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
          final subscriptionTier = _extractSubscriptionTier(profile);
          final isPremium = subscriptionTier == 'premium';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _buildProfileCard(
                context,
                displayName: displayName,
                email: accountEmail,
              ),
              const SizedBox(height: 18),
              _buildSectionHeader('Account'),
              _buildAccountCard(
                context,
                email: accountEmail,
                phone: accountPhone,
              ),
              const SizedBox(height: 18),
              _buildSectionHeader('Subscription'),
              _buildSubscriptionCard(
                context,
                isPremium: isPremium,
              ),
              const SizedBox(height: 18),
              _buildSectionHeader('Security & Privacy'),
              _buildSecurityPrivacyCard(context),
              const SizedBox(height: 18),
              _buildSectionHeader('About'),
              _buildAboutCard(context),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        key: const Key('settings_profile_card'),
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Personal information editor is coming soon.'),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.16),
                foregroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 22),
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
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            key: const Key('settings_email_tile'),
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email Address'),
            subtitle: Text(email),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Email editor is coming soon.')),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_change_password_tile'),
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openChangePassword(context, email),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_phone_tile'),
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Phone'),
            subtitle: Text(phone),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Phone linking is coming soon.')),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_setup_guide_tile'),
            leading: const Icon(Icons.help_outline),
            title: const Text('Setup Guide'),
            subtitle: const Text('Revisit onboarding walkthrough'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSetupGuide(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(
    BuildContext context, {
    required bool isPremium,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        key: const Key('settings_subscription_tile'),
        leading: const Icon(Icons.workspace_premium_outlined),
        title: const Text('Family Subscription'),
        subtitle: const Text('Manage your TrustBridge plan'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isPremium
                    ? Colors.amber.withValues(alpha: 0.2)
                    : Colors.blueGrey.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                isPremium ? 'PREMIUM' : 'FREE',
                style: TextStyle(
                  color: isPremium ? Colors.amber.shade800 : Colors.blueGrey,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Premium upgrade screen will arrive on Day 108.'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSecurityPrivacyCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('settings_biometric_login_switch'),
            value: _biometricLoginEnabled,
            title: const Text('Biometric Login'),
            subtitle:
                const Text('Use fingerprint/face unlock for parent controls'),
            onChanged: _isSaving
                ? null
                : (bool value) {
                    setState(() {
                      _biometricLoginEnabled = value;
                      _hasChanges = true;
                    });
                  },
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_privacy_center_tile'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Center'),
            subtitle: const Text('Control data and visibility settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPrivacyCenter(context),
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const Key('settings_incognito_mode_switch'),
            value: _incognitoModeEnabled,
            title: const Text('Incognito Mode'),
            subtitle: const Text('Hide sensitive activity details'),
            onChanged: _isSaving
                ? null
                : (bool value) {
                    setState(() {
                      _incognitoModeEnabled = value;
                      _hasChanges = true;
                    });
                  },
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_security_controls_tile'),
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Security Controls'),
            subtitle: const Text('App PIN, sessions, two-factor settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSecurityControls(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              'TrustBridge never sells your family\'s data.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            key: const Key('settings_terms_tile'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openExternalUrl('https://trustbridge.app/terms'),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_privacy_policy_tile'),
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openExternalUrl('https://trustbridge.app/privacy'),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_analytics_tile'),
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('Protection Analytics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/dns-analytics'),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_help_support_tile'),
            leading: const Icon(Icons.support_agent),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openHelpSupport(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_beta_feedback_tile'),
            leading: const Icon(Icons.science_outlined),
            title: const Text('Beta Feedback'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openBetaFeedback(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_feedback_history_tile'),
            leading: const Icon(Icons.history),
            title: const Text('Feedback History'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openBetaFeedbackHistory(context),
          ),
          const Divider(height: 1),
          const ListTile(
            key: Key('settings_version_tile'),
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0-alpha.1 (Build 60)'),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_sign_out_tile'),
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.red),
            ),
            onTap: _signOut,
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
    if (parentId == null || parentId.trim().isEmpty) {
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
        const SnackBar(content: Text('Settings updated successfully')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save settings: $error')),
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

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open link right now.')),
      );
    }
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

  Future<void> _openHelpSupport(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HelpSupportScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openBetaFeedback(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BetaFeedbackScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openBetaFeedbackHistory(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BetaFeedbackHistoryScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openSetupGuide(BuildContext context) async {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          parentId: parentId,
          isRevisit: true,
          firestoreService: widget.firestoreService,
        ),
      ),
    );
  }

  Future<void> _openChangePassword(BuildContext context, String email) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(
          authService: widget.authService,
          emailOverride: email,
        ),
      ),
    );
  }

  void _hydrateFromProfile(Map<String, dynamic>? profile) {
    if (_hasChanges) {
      return;
    }
    final preferences = _asMap(profile?['preferences']);
    _biometricLoginEnabled =
        _boolValue(preferences['biometricLoginEnabled'], false);
    _incognitoModeEnabled =
        _boolValue(preferences['incognitoModeEnabled'], false);
  }

  bool _boolValue(Object? value, bool fallback) {
    return value is bool ? value : fallback;
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

  String _displayNameFromEmail(String email) {
    if (email.contains('@')) {
      final prefix = email.split('@').first.trim();
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
    }
    return 'Parent Account';
  }

  String _extractSubscriptionTier(Map<String, dynamic>? profile) {
    final subscription = _asMap(profile?['subscription']);
    final tier = subscription['tier'];
    if (tier is String && tier.trim().isNotEmpty) {
      return tier.trim().toLowerCase();
    }
    return 'free';
  }
}

AppLocalizations _l10n(BuildContext context) {
  return AppLocalizations.of(context) ?? AppLocalizationsEn();
}
