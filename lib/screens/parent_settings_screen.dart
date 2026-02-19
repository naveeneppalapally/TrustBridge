import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:trustbridge_app/screens/beta_feedback_history_screen.dart';
import 'package:trustbridge_app/screens/beta_feedback_screen.dart';
import 'package:trustbridge_app/screens/help_support_screen.dart';
import 'package:trustbridge_app/screens/onboarding_screen.dart';
import 'package:trustbridge_app/screens/privacy_center_screen.dart';
import 'package:trustbridge_app/screens/security_controls_screen.dart';
import 'package:trustbridge_app/services/app_lock_service.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/notification_service.dart';
import 'package:trustbridge_app/widgets/pin_entry_dialog.dart';

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
  NotificationService? _notificationService;
  AppLockService? _appLockService;
  CrashlyticsService? _crashlyticsService;

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

  NotificationService get _resolvedNotificationService {
    _notificationService ??= NotificationService();
    return _notificationService!;
  }

  AppLockService get _resolvedAppLockService {
    _appLockService ??= AppLockService();
    return _appLockService!;
  }

  CrashlyticsService get _resolvedCrashlyticsService {
    _crashlyticsService ??= CrashlyticsService();
    return _crashlyticsService!;
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
              const SizedBox(height: 10),
              _buildRequestAlertPermissionCard(context),
              const SizedBox(height: 16),
              _buildSectionHeader('Security & Privacy'),
              _buildSecurityCard(context),
              const SizedBox(height: 16),
              _buildAppLockCard(context),
              const SizedBox(height: 16),
              _buildSectionHeader('Analytics'),
              _buildAnalyticsCard(context),
              const SizedBox(height: 24),
              _buildSectionHeader('Support'),
              _buildSupportCard(context),
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

  Widget _buildRequestAlertPermissionCard(BuildContext context) {
    return FutureBuilder<AuthorizationStatus>(
      future: _resolvedNotificationService.getAuthorizationStatus(),
      builder:
          (BuildContext context, AsyncSnapshot<AuthorizationStatus> snapshot) {
        final status = snapshot.data ?? AuthorizationStatus.notDetermined;
        final granted = status == AuthorizationStatus.authorized ||
            status == AuthorizationStatus.provisional;
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return Card(
          key: const Key('settings_request_alert_permission_card'),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.notifications_active_outlined,
                      color: granted ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('Access request alerts'),
                          const SizedBox(height: 2),
                          Text(
                            loading
                                ? 'Checking status...'
                                : granted
                                    ? 'Enabled'
                                    : 'Tap to enable',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: granted ? Colors.green : Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (granted)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      )
                    else
                      TextButton(
                        key: const Key('settings_enable_request_alerts_button'),
                        onPressed: () async {
                          await _resolvedNotificationService
                              .requestPermission();
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        child: const Text('Enable'),
                      ),
                  ],
                ),
                if (kDebugMode) ...<Widget>[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('settings_send_test_notification_button'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final shown = await _resolvedNotificationService
                          .showLocalTestNotification();
                      if (!mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            shown
                                ? 'Test notification sent.'
                                : 'Unable to send test notification on this device.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Send test notification (Dev)'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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

  Widget _buildAppLockCard(BuildContext context) {
    return FutureBuilder<bool>(
      future: _resolvedAppLockService.isEnabled(),
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        final enabled = snapshot.data ?? false;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'App Lock',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Require PIN before opening parent controls.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  key: const Key('settings_app_lock_switch'),
                  value: enabled,
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(enabled ? 'PIN lock enabled' : 'PIN lock disabled'),
                  subtitle:
                      const Text('Supports fingerprint unlock when available'),
                  onChanged: (bool value) async {
                    if (value) {
                      await _enablePinLock();
                    } else {
                      await _disablePinLock();
                    }
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
                if (enabled) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('settings_change_pin_tile'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.pin_outlined, size: 20),
                    title: const Text('Change PIN'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () async {
                      await _changePinFlow();
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSupportCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.help_outline, color: Colors.blueGrey.shade700),
            title: const Text('Setup Guide'),
            subtitle: const Text('Revisit the onboarding walkthrough'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => _openSetupGuide(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_beta_feedback_tile'),
            leading: Icon(Icons.science_outlined, color: Colors.teal.shade700),
            title: const Text('Beta Feedback'),
            subtitle: const Text('Report alpha issues and suggestions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => _openBetaFeedback(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('settings_feedback_history_tile'),
            leading: Icon(Icons.history, color: Colors.teal.shade700),
            title: const Text('Feedback History'),
            subtitle: const Text('Track submitted reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => _openBetaFeedbackHistory(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.support_agent, color: Colors.indigo.shade700),
            title: const Text('Help & Support'),
            subtitle: const Text('FAQs, troubleshooting, and contact support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => _openHelpSupport(context),
          ),
          if (kDebugMode) ...<Widget>[
            const Divider(height: 1),
            ListTile(
              key: const Key('settings_test_crashlytics_tile'),
              leading: const Icon(Icons.bug_report, color: Colors.red),
              title: const Text('Test Crashlytics'),
              subtitle: const Text('Trigger a test crash (debug only)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _testCrashlytics,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(Icons.bar_chart_outlined, color: Colors.teal.shade700),
        title: const Text('Protection Analytics'),
        subtitle: const Text('Blocked queries and policy summary'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/dns-analytics'),
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
      _showInfo('Not logged in');
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

  Future<void> _testCrashlytics() async {
    final shouldCrash = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Test Crash'),
          content: const Text(
            'This triggers a test crash for Crashlytics verification.\n\n'
            'The app will close immediately.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Crash Now'),
            ),
          ],
        );
      },
    );

    if (shouldCrash == true) {
      _resolvedCrashlyticsService.testCrash();
    }
  }

  Future<void> _enablePinLock() async {
    try {
      final hasPin = await _resolvedAppLockService.hasPin();
      if (hasPin) {
        await _resolvedAppLockService.enableLock();
      } else {
        final pin = await _showSetPinDialog();
        if (pin == null) {
          return;
        }
        await _resolvedAppLockService.setPin(pin);
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN lock enabled')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to enable app lock: $error')),
      );
    }
  }

  Future<void> _disablePinLock() async {
    final unlocked = await showPinEntryDialog(context);
    if (!unlocked) {
      return;
    }

    try {
      await _resolvedAppLockService.disableLock();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN lock disabled')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to disable app lock: $error')),
      );
    }
  }

  Future<void> _changePinFlow() async {
    final unlocked = await showPinEntryDialog(context);
    if (!unlocked) {
      return;
    }

    final newPin = await _showSetPinDialog();
    if (newPin == null) {
      return;
    }

    try {
      await _resolvedAppLockService.setPin(newPin);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN changed')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to change PIN: $error')),
      );
    }
  }

  Future<String?> _showSetPinDialog() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _SetPinDialog(),
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

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog();

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (pin.length != 4 || int.tryParse(pin) == null) {
      setState(() {
        _errorText = 'PIN must be exactly 4 digits.';
      });
      return;
    }

    if (pin != confirmPin) {
      setState(() {
        _errorText = 'PINs do not match.';
      });
      return;
    }

    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text('Set Parent PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'New 4-digit PIN',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'Confirm PIN',
              counterText: '',
            ),
          ),
          if (_errorText != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Set PIN'),
        ),
      ],
    );
  }
}
