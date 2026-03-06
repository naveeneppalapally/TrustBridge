import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trustbridge_app/core/utils/responsive.dart';
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
import 'package:trustbridge_app/theme/app_text_styles.dart';
import 'package:trustbridge_app/theme/app_theme.dart';
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
    R.init(context);
    final l10n = _l10n(context);
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            l10n.notLoggedInMessage,
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Map<String, dynamic>?>(
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
                          size: 48, color: AppColors.danger),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load settings',
                        style: AppTextStyles.headingLarge(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => setState(() {}),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryDim,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Retry',
                            style: AppTextStyles.label(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
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
              padding: EdgeInsets.fromLTRB(
                R.sp(20),
                R.sp(20),
                R.sp(20),
                R.sp(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileCard(
                    context,
                    displayName: displayName,
                    email: accountEmail,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Account'),
                  _buildAccountCard(
                    context,
                    email: accountEmail,
                    phone: accountPhone,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Subscription'),
                  _buildSubscriptionCard(
                    context,
                    isPremium: isPremium,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Security & Privacy'),
                  _buildSecurityPrivacyCard(context),
                  const SizedBox(height: 24),
                  _buildSectionHeader('About'),
                  _buildAboutCard(context),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileCard(
    BuildContext context, {
    required String displayName,
    required String email,
  }) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P';
    return Padding(
      key: const Key('settings_profile_card'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryDim,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                initial,
                style: AppTextStyles.displayMedium(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headingLarge(),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context, {
    required String email,
    required String phone,
  }) {
    return Column(
      children: [
        _SettingsRow(
          key: const Key('settings_change_password_tile'),
          icon: Icons.lock_outline,
          label: 'Change Password',
          onTap: () => _openChangePassword(context, email),
        ),
        _SettingsRow(
          key: const Key('settings_phone_tile'),
          icon: Icons.phone_outlined,
          label: 'Phone',
          subtitle: phone,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Phone linking is unavailable right now.')),
          ),
        ),
        _SettingsRow(
          key: const Key('settings_family_management_tile'),
          icon: Icons.family_restroom,
          label: 'Family Management',
          onTap: () => _openFamilyManagement(context),
        ),
      ],
    );
  }

  Widget _buildSubscriptionCard(
    BuildContext context, {
    required bool isPremium,
  }) {
    return _SettingsRow(
      key: const Key('settings_subscription_tile'),
      icon: Icons.workspace_premium_outlined,
      label: 'Family Subscription',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isPremium ? AppColors.warningDim : AppColors.surfaceBorder,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          isPremium ? 'PREMIUM' : 'FREE',
          style: AppTextStyles.labelCaps(
            color: isPremium ? AppColors.gold : AppColors.textMuted,
          ),
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PremiumScreen(),
          ),
        );
      },
    );
  }

  Widget _buildSecurityPrivacyCard(BuildContext context) {
    return Column(
      children: [
        _SettingsRow(
          key: const Key('settings_biometric_login_switch'),
          icon: Icons.fingerprint,
          label: 'Biometric Login',
          trailing: Switch.adaptive(
            value: _biometricLoginEnabled,
            onChanged: _isSaving
                ? null
                : (bool value) {
                    setState(() {
                      _biometricLoginEnabled = value;
                    });
                    unawaited(
                      _saveSettings(biometricLoginEnabled: value),
                    );
                  },
          ),
        ),
        _SettingsRow(
          key: const Key('settings_privacy_center_tile'),
          icon: Icons.privacy_tip_outlined,
          label: 'Privacy Center',
          onTap: () => _openPrivacyCenter(context),
        ),
        _SettingsRow(
          key: const Key('settings_incognito_mode_switch'),
          icon: Icons.visibility_off_outlined,
          label: 'Incognito Mode',
          trailing: Switch.adaptive(
            value: _incognitoModeEnabled,
            onChanged: _isSaving
                ? null
                : (bool value) {
                    setState(() {
                      _incognitoModeEnabled = value;
                    });
                    unawaited(
                      _saveSettings(incognitoModeEnabled: value),
                    );
                  },
          ),
        ),
        _SettingsRow(
          key: const Key('settings_protection_settings_tile'),
          icon: Icons.shield_moon_outlined,
          label: 'Protection Settings',
          onTap: () => _openProtectionSettings(context),
        ),
        _SettingsRow(
          key: const Key('settings_open_source_blocklists_tile'),
          icon: Icons.cloud_sync_outlined,
          label: 'Open-Source Blocklists',
          onTap: () => _openBlocklistManagement(context),
        ),
        _SettingsRow(
          key: const Key('settings_modes_tile'),
          icon: Icons.tune_rounded,
          label: 'Modes',
          onTap: () => _openModes(context),
        ),
        _SettingsRow(
          key: const Key('settings_mode_overrides_tile'),
          icon: Icons.rule_folder_outlined,
          label: 'Easy Mode Setup',
          onTap: () => _openModeOverridesPicker(context),
        ),
        _SettingsRow(
          key: const Key('settings_alert_preferences_tile'),
          icon: Icons.tune_outlined,
          label: 'Alert Preferences',
          onTap: () => _openAlertPreferences(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 4, 16, 8),
          child: Text(
            'TrustBridge never sells your family\'s data.',
            style: AppTextStyles.bodySmall(
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Column(
      children: [
        _SettingsRow(
          key: const Key('settings_terms_tile'),
          icon: Icons.description_outlined,
          label: 'Terms of Service',
          onTap: () => _openExternalUrl('https://trustbridge.app/terms'),
        ),
        _SettingsRow(
          key: const Key('settings_privacy_policy_tile'),
          icon: Icons.policy_outlined,
          label: 'Privacy Policy',
          onTap: () => _openExternalUrl('https://trustbridge.app/privacy'),
        ),
        _SettingsRow(
          key: const Key('settings_open_source_licenses_tile'),
          icon: Icons.gavel_outlined,
          label: 'Open Source Licenses',
          onTap: () => _openOpenSourceLicenses(context),
        ),
        _SettingsRow(
          key: const Key('settings_analytics_tile'),
          icon: Icons.bar_chart_outlined,
          label: 'Protection Analytics',
          onTap: () => Navigator.of(context).pushNamed('/dns-analytics'),
        ),
        _SettingsRow(
          key: const Key('settings_usage_reports_tile'),
          icon: Icons.insights_outlined,
          label: 'Usage Reports',
          onTap: () => _openUsageReports(context),
        ),
        _SettingsRow(
          key: const Key('settings_bypass_alerts_tile'),
          icon: Icons.notification_important_outlined,
          label: 'Protection Alerts',
          onTap: () => _openBypassAlerts(context),
        ),
        _SettingsRow(
          key: const Key('settings_help_support_tile'),
          icon: Icons.support_agent,
          label: 'Help & Support',
          onTap: () => _openHelpSupport(context),
        ),
        _SettingsRow(
          key: const Key('settings_beta_feedback_tile'),
          icon: Icons.science_outlined,
          label: 'Beta Feedback',
          onTap: () => _openBetaFeedback(context),
        ),
        _SettingsRow(
          key: const Key('settings_feedback_history_tile'),
          icon: Icons.history,
          label: 'Feedback History',
          onTap: () => _openBetaFeedbackHistory(context),
        ),
        const _SettingsRow(
          key: Key('settings_version_tile'),
          icon: Icons.info_outline,
          label: 'Version',
          subtitle:
              '${String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '1.0.0-beta.1')} '
              '(Build ${String.fromEnvironment('FLUTTER_BUILD_NUMBER', defaultValue: '114')})',
        ),
        const SizedBox(height: 8),
        GestureDetector(
          key: const Key('settings_sign_out_tile'),
          onTap: _signOut,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.dangerDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'Sign Out',
                style: AppTextStyles.headingMedium(color: AppColors.danger),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.labelCaps(color: AppColors.textMuted),
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
    final parentId = _parentId?.trim();
    if (parentId != null && parentId.isNotEmpty) {
      try {
        await _resolvedFirestoreService.revokeChildSessionsForParent(parentId);
      } catch (_) {
        // Best effort: continue sign-out even if network is unavailable.
      }
      try {
        await _resolvedFirestoreService.removeFcmToken(parentId);
      } catch (_) {
        // Non-blocking cleanup.
      }
    }
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

/// Clean settings row: 32×32 icon square + label + optional trailing.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // Icon square
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            // Label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall(
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Trailing
            trailing ??
                (onTap != null
                    ? const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.textMuted,
                      )
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
