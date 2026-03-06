import 'package:flutter/material.dart';
import 'package:trustbridge_app/core/utils/responsive.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/theme/app_text_styles.dart';
import 'package:trustbridge_app/theme/app_theme.dart';

class PrivacyCenterScreen extends StatefulWidget {
  const PrivacyCenterScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<PrivacyCenterScreen> createState() => _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends State<PrivacyCenterScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;

  bool _activityHistoryEnabled = true;
  bool _crashReportsEnabled = true;
  bool _personalizedTipsEnabled = true;

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
    R.init(context);
    final parentId = _parentId;
    if (parentId == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Not logged in',
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
                  const Spacer(),
                  if (_hasChanges)
                    GestureDetector(
                      onTap: _isSaving ? null : _saveChanges,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryDim,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : Text(
                                'SAVE',
                                style: AppTextStyles.label(
                                  color: AppColors.primary,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(R.sp(20), R.sp(4), R.sp(20), 0),
              child: Text(
                'Privacy Center',
                style: AppTextStyles.displayMedium(),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: R.sp(20)),
              child: Text(
                'Control what data is stored and used.',
                style: AppTextStyles.bodySmall(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<Map<String, dynamic>?>(
                stream:
                    _resolvedFirestoreService.watchParentProfile(parentId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: AppColors.danger),
                            const SizedBox(height: 12),
                            Text(
                              'Unable to load privacy settings',
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
                            const SizedBox(height: 14),
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

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      R.sp(20), 0, R.sp(20), R.sp(28),
                    ),
                    children: [
                      _buildPrivacyToggle(
                        key: const Key('privacy_activity_history_switch'),
                        title: 'Activity History',
                        subtitle:
                            'Store dashboard activity history for reports',
                        value: _activityHistoryEnabled,
                        onChanged: (value) {
                          setState(() {
                            _activityHistoryEnabled = value;
                            _hasChanges = true;
                          });
                        },
                      ),
                      _buildPrivacyToggle(
                        key: const Key('privacy_crash_reports_switch'),
                        title: 'Crash Reports',
                        subtitle:
                            'Share crash diagnostics to improve stability',
                        value: _crashReportsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _crashReportsEnabled = value;
                            _hasChanges = true;
                          });
                        },
                      ),
                      _buildPrivacyToggle(
                        key: const Key(
                            'privacy_personalized_tips_switch'),
                        title: 'Personalized Tips',
                        subtitle:
                            'Use activity patterns for suggestions',
                        value: _personalizedTipsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _personalizedTipsEnabled = value;
                            _hasChanges = true;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'TrustBridge does not sell personal data. These settings control only your in-app experience and diagnostics.',
                                style: AppTextStyles.bodySmall(
                                  color: AppColors.primary,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyToggle({
    required Key key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body()),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: _isSaving ? null : onChanged,
          ),
        ],
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
        activityHistoryEnabled: _activityHistoryEnabled,
        crashReportsEnabled: _crashReportsEnabled,
        personalizedTipsEnabled: _personalizedTipsEnabled,
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
          content: Text('Privacy settings updated successfully'),
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
            content: Text('Unable to update privacy settings: $error'),
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
    _activityHistoryEnabled =
        _boolValue(preferences['activityHistoryEnabled'], true);
    _crashReportsEnabled = _boolValue(preferences['crashReportsEnabled'], true);
    _personalizedTipsEnabled =
        _boolValue(preferences['personalizedTipsEnabled'], true);
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
}
