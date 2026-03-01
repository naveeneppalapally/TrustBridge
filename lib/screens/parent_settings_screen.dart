import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trustbridge_app/l10n/app_localizations.dart';
import 'package:trustbridge_app/l10n/app_localizations_en.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/beta_feedback_history_screen.dart';
import 'package:trustbridge_app/screens/beta_feedback_screen.dart';
import 'package:trustbridge_app/screens/blocklist_management_screen.dart';
import 'package:trustbridge_app/screens/change_password_screen.dart';
import 'package:trustbridge_app/screens/family_management_screen.dart';
import 'package:trustbridge_app/screens/help_support_screen.dart';
import 'package:trustbridge_app/screens/mode_overrides_screen.dart';
import 'package:trustbridge_app/screens/modes_screen.dart';
import 'package:trustbridge_app/screens/parent/alert_preferences_screen.dart';
import 'package:trustbridge_app/screens/parent/protection_settings_screen.dart';
import 'package:trustbridge_app/screens/privacy_center_screen.dart';
import 'package:trustbridge_app/screens/premium_screen.dart';
import 'package:trustbridge_app/screens/usage_reports_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/app_mode_service.dart';
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

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
            ),
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
      child: Padding(
        key: const Key('settings_profile_card'),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
              foregroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
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
              const SnackBar(
                  content: Text('Phone linking is unavailable right now.')),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_family_management_tile'),
            leading: const Icon(Icons.family_restroom),
            title: const Text('Family Management'),
            subtitle: const Text('Manage parents and child seats'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openFamilyManagement(context),
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
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PremiumScreen(),
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
                    });
                    unawaited(
                      _saveSettings(
                        biometricLoginEnabled: value,
                      ),
                    );
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
                    });
                    unawaited(
                      _saveSettings(
                        incognitoModeEnabled: value,
                      ),
                    );
                  },
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_protection_settings_tile'),
            leading: const Icon(Icons.shield_moon_outlined),
            title: const Text('Protection Settings'),
            subtitle:
                const Text('Status, alerts, and advanced troubleshooting'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openProtectionSettings(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_open_source_blocklists_tile'),
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Open-Source Blocklists'),
            subtitle: const Text('Automatic daily updates and source status'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openBlocklistManagement(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_modes_tile'),
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Modes'),
            subtitle: const Text('Free Play, Homework, Bedtime, Lockdown'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openModes(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_mode_overrides_tile'),
            leading: const Icon(Icons.rule_folder_outlined),
            title: const Text('Easy Mode Setup'),
            subtitle: const Text(
                'Pick what to block in each mode with simple toggles'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openModeOverridesPicker(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_alert_preferences_tile'),
            leading: const Icon(Icons.tune_outlined),
            title: const Text('Alert Preferences'),
            subtitle: const Text('Choose which protection alerts you receive'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openAlertPreferences(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              'TrustBridge never sells your family\'s data.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            key: const Key('settings_open_source_licenses_tile'),
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Open Source Licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openOpenSourceLicenses(context),
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
            key: const Key('settings_usage_reports_tile'),
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Usage Reports'),
            subtitle: const Text('Screen time and app usage by child'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openUsageReports(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_bypass_alerts_tile'),
            leading: const Icon(Icons.notification_important_outlined),
            title: const Text('Protection Alerts'),
            subtitle: const Text('Bypass attempts and safety events'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openBypassAlerts(context),
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
            subtitle: Text(
              '${String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '1.0.0-beta.1')} '
              '(Build ${String.fromEnvironment('FLUTTER_BUILD_NUMBER', defaultValue: '114')})',
            ),
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
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _saveSettings({
    bool? biometricLoginEnabled,
    bool? incognitoModeEnabled,
  }) async {
    if (_isSaving) {
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
        biometricLoginEnabled: biometricLoginEnabled,
        incognitoModeEnabled: incognitoModeEnabled,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
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
    await AppModeService().clearMode();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed('/welcome');
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

  Future<void> _openProtectionSettings(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProtectionSettingsScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openBlocklistManagement(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BlocklistManagementScreen(),
      ),
    );
  }

  Future<void> _openAlertPreferences(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlertPreferencesScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openModes(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModesScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openModeOverridesPicker(BuildContext context) async {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return;
    }

    List<ChildProfile> children;
    try {
      children = await _resolvedFirestoreService.getChildrenOnce(parentId);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load children: $error')),
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    if (children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a child first to edit custom modes.')),
      );
      return;
    }

    final selectedChild = await showModalBottomSheet<ChildProfile>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: children.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final child = children[index];
              return ListTile(
                title: Text(child.nickname),
                subtitle: Text('Age group: ${child.ageBand.value} years'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(sheetContext).pop(child),
              );
            },
          ),
        );
      },
    );
    if (selectedChild == null || !context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModeOverridesScreen(
          child: selectedChild,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openUsageReports(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UsageReportsScreen(
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

  Future<void> _openFamilyManagement(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FamilyManagementScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openBypassAlerts(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).pushNamed('/parent/bypass-alerts');
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

  Future<void> _openOpenSourceLicenses(BuildContext context) async {
    await Navigator.of(context).pushNamed('/open-source-licenses');
  }

  void _hydrateFromProfile(Map<String, dynamic>? profile) {
    if (_isSaving) {
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
