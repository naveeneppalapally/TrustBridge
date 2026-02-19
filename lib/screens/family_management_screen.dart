import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

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
    final resolvedFirestoreService = firestoreService ?? FirestoreService();
    final parentId = _resolveParentId();

    if (parentId == null || parentId.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in to manage your family group.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Management'),
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: resolvedFirestoreService.watchParentProfile(parentId),
        builder: (context, profileSnapshot) {
          final profile = profileSnapshot.data;
          return StreamBuilder<List<ChildProfile>>(
            stream: resolvedFirestoreService.getChildrenStream(parentId),
            builder: (context, childSnapshot) {
              if ((profileSnapshot.connectionState == ConnectionState.waiting &&
                      !profileSnapshot.hasData) ||
                  (childSnapshot.connectionState == ConnectionState.waiting &&
                      !childSnapshot.hasData)) {
                return const Center(child: CircularProgressIndicator());
              }

              final children = childSnapshot.data ?? const <ChildProfile>[];
              final adminRows = _buildAdminRows(profile);

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildSubscriptionCard(context),
                  const SizedBox(height: 14),
                  Text(
                    'LOCKED END-TO-END ENCRYPTED MANAGEMENT',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 14),
                  _buildAdminsCard(context, adminRows),
                  const SizedBox(height: 14),
                  _buildChildrenCard(
                    context,
                    children: children,
                    authService: authService,
                    firestoreService: firestoreService,
                    parentIdOverride: parentIdOverride,
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    key: const Key('family_leave_group_button'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Leave group flow will be available in billing settings.',
                          ),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Leave Family Group'),
                  ),
                ],
              );
            },
          );
        },
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE5F3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Color(0xFF2E86FF),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Premium Family',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Renews Oct 24, 2024',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDFBE8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: Color(0xFF0F9D58),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {},
            child: const Row(
              children: [
                Text(
                  'Manage Billing',
                  style: TextStyle(
                    color: Color(0xFF2E86FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward_ios,
                    size: 13, color: Color(0xFF2E86FF)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminsCard(BuildContext context, List<_FamilyAdmin> admins) {
    return Card(
      key: const Key('family_admins_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'ADMINS (PARENTS)',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Text(
                  '${admins.length} / 4 Seats',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...admins.map((admin) => _buildAdminRow(admin)),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('family_invite_parent_button'),
              onPressed: () {},
              child: const Text('+ Invite another parent'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminRow(_FamilyAdmin admin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE8F2FF),
            child: Text(
              admin.name.isEmpty ? '?' : admin.name[0].toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF2E86FF),
                fontWeight: FontWeight.w700,
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
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  admin.email,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          if (admin.owner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE0ECFF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'OWNER',
                style: TextStyle(
                  color: Color(0xFF2E86FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            const Icon(Icons.more_horiz),
        ],
      ),
    );
  }

  Widget _buildChildrenCard(
    BuildContext context, {
    required List<ChildProfile> children,
    required AuthService? authService,
    required FirestoreService? firestoreService,
    required String? parentIdOverride,
  }) {
    return Card(
      key: const Key('family_children_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'CHILDREN',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Text(
                  '${children.length} / Unlimited',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (children.isEmpty)
              const Text(
                'No child profiles yet.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ...children.map((child) => _buildChildRow(child)),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('family_add_child_button'),
              onPressed: () {
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
              child: const Text('+ Add child profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildRow(ChildProfile child) {
    final deviceLabel =
        child.deviceIds.isEmpty ? 'No device linked' : child.deviceIds.first;
    final statusText = child.deviceIds.isEmpty ? '2h ago' : 'Active Now';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFF1F5F9),
            child: Text(
              child.nickname.isEmpty ? '?' : child.nickname[0].toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
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
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  deviceLabel,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            statusText,
            style: TextStyle(
              color: statusText == 'Active Now'
                  ? const Color(0xFF0F9D58)
                  : Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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
