import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_theme.dart';

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
  bool _isPremium = false;

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
    final profile = await _resolvedFirestoreService.getParentProfile(parentId);
    final subscription = _asMap(profile?['subscription']);
    final tier = (subscription['tier'] as String?)?.trim().toLowerCase();
    final isPremium = tier == 'premium';
    if (!mounted) {
      return;
    }
    setState(() {
      _isPremium = isPremium;
      _vpnDisabled = true;
      _uninstallAttempt = true;
      _privateDnsChanged = prefs['privateDnsChanged'] != false;
      _deviceOffline30m = prefs['deviceOffline30m'] != false;
      _deviceOffline24h = isPremium && prefs['deviceOffline24h'] != false;
      _emailSerious = isPremium && prefs['emailSeriousAlerts'] == true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please sign in first.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(R.sp(8), R.sp(8), R.sp(8), 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(R.sp(20), R.sp(4), R.sp(20), 0),
              child: Text(
                'Alert Preferences',
                style: AppTextStyles.displayMedium(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        R.sp(20), 0, R.sp(20), R.sp(24),
                      ),
                      children: [
                        Text(
                          'SAFETY ALERTS',
                          style: AppTextStyles.labelCaps(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildToggle(
                          title: 'Protection turned off',
                          value: _vpnDisabled,
                          alwaysOn: true,
                          onChanged: (value) =>
                              _update(parentId, vpnDisabled: value),
                        ),
                        _buildToggle(
                          title: 'Uninstall attempt',
                          value: _uninstallAttempt,
                          alwaysOn: true,
                          onChanged: (value) =>
                              _update(parentId, uninstallAttempt: value),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'CONFIGURABLE',
                          style: AppTextStyles.labelCaps(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildToggle(
                          title: 'Network settings changed',
                          value: _privateDnsChanged,
                          alwaysOn: false,
                          onChanged: (value) =>
                              _update(parentId, privateDnsChanged: value),
                        ),
                        _buildToggle(
                          title: 'Device offline (30 min)',
                          value: _deviceOffline30m,
                          alwaysOn: false,
                          onChanged: (value) =>
                              _update(parentId, deviceOffline30m: value),
                        ),
                        _buildToggle(
                          title: 'Device offline (24 hours)',
                          value: _deviceOffline24h,
                          alwaysOn: false,
                          premiumLocked: !_isPremium,
                          onChanged: (value) =>
                              _update(parentId, deviceOffline24h: value),
                        ),
                        if (!_isPremium) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primaryDim,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.primary
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              '24-hour offline and email alerts are available on Premium.',
                              style: AppTextStyles.bodySmall(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'EMAIL',
                          style: AppTextStyles.labelCaps(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildToggle(
                          title: 'Email for serious alerts',
                          value: _emailSerious,
                          alwaysOn: false,
                          premiumLocked: !_isPremium,
                          onChanged: (value) => _update(
                            parentId,
                            emailSeriousAlerts: value,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Safety alerts stay on by default to protect your child.',
                          style: AppTextStyles.bodySmall(
                            color: AppColors.textMuted,
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

  Widget _buildToggle({
    required String title,
    required bool value,
    required bool alwaysOn,
    bool premiumLocked = false,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (alwaysOn)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                size: 14,
                color: AppColors.primary,
              ),
            )
          else if (premiumLocked)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.warningDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 14,
                color: AppColors.gold,
              ),
            ),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.body(
                color: alwaysOn || premiumLocked
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged:
                alwaysOn || premiumLocked || _saving ? null : onChanged,
          ),
        ],
      ),
    );
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
