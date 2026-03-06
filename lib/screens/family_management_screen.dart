import 'package:flutter/material.dart';
import 'package:trustbridge_app/core/utils/responsive.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/theme/app_text_styles.dart';
import 'package:trustbridge_app/theme/app_theme.dart';

class FamilyManagementScreen extends StatelessWidget {
  const FamilyManagementScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final resolvedFirestoreService = firestoreService ?? FirestoreService();
    final parentId = _resolveParentId();

    if (parentId == null || parentId.trim().isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please sign in to manage your family group.',
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
                'Family Management',
                style: AppTextStyles.displayMedium(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: resolvedFirestoreService.watchParentProfile(parentId),
                builder: (context, profileSnapshot) {
                  final profile = profileSnapshot.data;
                  return StreamBuilder<List<ChildProfile>>(
                    stream:
                        resolvedFirestoreService.getChildrenStream(parentId),
                    builder: (context, childSnapshot) {
                      if ((profileSnapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !profileSnapshot.hasData) ||
                          (childSnapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !childSnapshot.hasData)) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      final children =
                          childSnapshot.data ?? const <ChildProfile>[];
                      final adminRows = _buildAdminRows(profile);

                      return ListView(
                        padding: EdgeInsets.fromLTRB(
                          R.sp(20), 0, R.sp(20), R.sp(24),
                        ),
                        children: [
                          _buildSubscriptionCard(context),
                          const SizedBox(height: 20),
                          _buildAdminsSection(context, adminRows),
                          const SizedBox(height: 20),
                          _buildChildrenSection(
                            context,
                            children: children,
                            authService: authService,
                            firestoreService: firestoreService,
                            parentIdOverride: parentIdOverride,
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            key: const Key('family_leave_group_button'),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Leave group flow will be available in billing settings.',
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.dangerDim,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  'Leave Family Group',
                                  style: AppTextStyles.headingMedium(
                                    color: AppColors.danger,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _resolveParentId() {
    final override = parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    if (authService != null) {
      return authService!.currentUser?.uid;
    }

    try {
      return AuthService().currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Widget _buildSubscriptionCard(BuildContext context) {
    return Container(
      key: const Key('family_subscription_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDim,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Premium Family',
                      style: AppTextStyles.headingMedium(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Active subscription',
                      style: AppTextStyles.bodySmall(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successDim,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'ACTIVE',
                  style: AppTextStyles.labelCaps(
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {},
            child: Row(
              children: [
                Text(
                  'Manage Billing',
                  style: AppTextStyles.label(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminsSection(BuildContext context, List<_FamilyAdmin> admins) {
    return Column(
      key: const Key('family_admins_card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'ADMINS (PARENTS)',
              style: AppTextStyles.labelCaps(color: AppColors.textMuted),
            ),
            const Spacer(),
            Text(
              '${admins.length} / 4 Seats',
              style: AppTextStyles.bodySmall(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...admins.map((admin) => _buildAdminRow(admin)),
        const SizedBox(height: 4),
        GestureDetector(
          key: const Key('family_invite_parent_button'),
          onTap: () {},
          child: Text(
            '+ Invite another parent',
            style: AppTextStyles.label(color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminRow(_FamilyAdmin admin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                admin.name.isEmpty ? '?' : admin.name[0].toUpperCase(),
                style: AppTextStyles.headingMedium(
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  admin.name,
                  style: AppTextStyles.body(),
                ),
                Text(
                  admin.email,
                  style: AppTextStyles.bodySmall(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (admin.owner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryDim,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'OWNER',
                style: AppTextStyles.labelCaps(
                  color: AppColors.primary,
                ),
              ),
            )
          else
            const Icon(
              Icons.more_horiz,
              color: AppColors.textMuted,
              size: 18,
            ),
        ],
      ),
    );
  }

  Widget _buildChildrenSection(
    BuildContext context, {
    required List<ChildProfile> children,
    required AuthService? authService,
    required FirestoreService? firestoreService,
    required String? parentIdOverride,
  }) {
    return Column(
      key: const Key('family_children_card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CHILDREN',
              style: AppTextStyles.labelCaps(color: AppColors.textMuted),
            ),
            const Spacer(),
            Text(
              '${children.length} / Unlimited',
              style: AppTextStyles.bodySmall(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (children.isEmpty)
          Text(
            'No child profiles yet.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          )
        else
          ...children.map((child) => _buildChildRow(child)),
        const SizedBox(height: 4),
        GestureDetector(
          key: const Key('family_add_child_button'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddChildScreen(
                  authService: authService,
                  firestoreService: firestoreService,
                  parentIdOverride: parentIdOverride,
                ),
              ),
            );
          },
          child: Text(
            '+ Add child profile',
            style: AppTextStyles.label(color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildChildRow(ChildProfile child) {
    final deviceLabel = _childDeviceLabel(child);
    final isActive = child.deviceIds.isNotEmpty;
    final statusText = isActive ? 'Active Now' : '2h ago';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                child.nickname.isEmpty
                    ? '?'
                    : child.nickname[0].toUpperCase(),
                style: AppTextStyles.headingMedium(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child.nickname,
                  style: AppTextStyles.body(),
                ),
                Text(
                  deviceLabel,
                  style: AppTextStyles.bodySmall(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                statusText,
                style: AppTextStyles.label(
                  color: isActive
                      ? AppColors.success
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _childDeviceLabel(ChildProfile child) {
    if (child.deviceIds.isEmpty) {
      return 'No device linked';
    }

    for (final rawDeviceId in child.deviceIds) {
      final deviceId = rawDeviceId.trim();
      if (deviceId.isEmpty) {
        continue;
      }
      final metadata = child.deviceMetadata[deviceId];
      final alias = (metadata?.alias ?? '').trim();
      if (alias.isNotEmpty && alias != deviceId) {
        return alias;
      }
    }

    return 'Linked device';
  }

  List<_FamilyAdmin> _buildAdminRows(Map<String, dynamic>? profile) {
    final primaryEmail = _extractString(profile, 'email') ?? 'owner@family.com';
    final primaryName =
        _extractString(profile, 'displayName') ?? _nameFromEmail(primaryEmail);

    return [
      _FamilyAdmin(name: primaryName, email: primaryEmail, owner: true),
      const _FamilyAdmin(
        name: 'Co-Parent',
        email: 'coparent@family.com',
        owner: false,
      ),
    ];
  }

  String? _extractString(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  String _nameFromEmail(String email) {
    if (!email.contains('@')) {
      return 'Parent Account';
    }
    final prefix = email.split('@').first.trim();
    if (prefix.isEmpty) {
      return 'Parent Account';
    }
    return prefix[0].toUpperCase() + prefix.substring(1);
  }
}

class _FamilyAdmin {
  const _FamilyAdmin({
    required this.name,
    required this.email,
    required this.owner,
  });

  final String name;
  final String email;
  final bool owner;
}
