import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;

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

  Future<void> _handleSignOut() async {
    await _resolvedAuthService.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _showComingSoon(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1F2937) : Colors.white;
    final backgroundColor =
        isDark ? const Color(0xFF101A22) : const Color(0xFFF5F7F8);

    if (parentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('TrustBridge')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('TrustBridge'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              _showComingSoon('Settings screen coming in Day 10!');
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleSignOut,
          ),
        ],
      ),
      body: StreamBuilder<List<ChildProfile>>(
        stream: _resolvedFirestoreService.getChildrenStream(parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 52,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Unable to load dashboard',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final children = snapshot.data ?? const <ChildProfile>[];
          final totalBlockedCategories = children.fold<int>(
            0,
            (sum, child) => sum + child.policy.blockedCategories.length,
          );
          final totalSchedules = children.fold<int>(
            0,
            (sum, child) => sum + child.policy.schedules.length,
          );

          if (children.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.family_restroom,
                      size: 92,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No children yet',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your first child to get started',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () {
                        _showComingSoon('Add Child screen coming in Day 10!');
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Child'),
                    ),
                  ],
                ),
              ),
            );
          }

          final width = MediaQuery.sizeOf(context).width;
          final isTablet = width >= 600;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isTablet ? 24 : 16,
                    8,
                    isTablet ? 24 : 16,
                    12,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.2)
                              : Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SummaryMetric(
                            label: 'MANAGED PROFILES',
                            value: '${children.length}',
                            icon: Icons.people_alt_outlined,
                            iconColor: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Expanded(
                          child: _SummaryMetric(
                            label: 'BLOCKED CATEGORIES',
                            value: '$totalBlockedCategories',
                            icon: Icons.block_outlined,
                            iconColor: Colors.redAccent,
                          ),
                        ),
                        Expanded(
                          child: _SummaryMetric(
                            label: 'SCHEDULES',
                            value: '$totalSchedules',
                            icon: Icons.schedule_outlined,
                            iconColor: Colors.orangeAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  isTablet ? 24 : 16,
                  0,
                  isTablet ? 24 : 16,
                  100,
                ),
                sliver: isTablet
                    ? SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.5,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final child = children[index];
                            return ChildCard(
                              child: child,
                              onTap: () {
                                _showComingSoon(
                                  'Child Detail for ${child.nickname} coming in Week 3!',
                                );
                              },
                            );
                          },
                          childCount: children.length,
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final child = children[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: ChildCard(
                                child: child,
                                onTap: () {
                                  _showComingSoon(
                                    'Child Detail for ${child.nickname} coming in Week 3!',
                                  );
                                },
                              ),
                            );
                          },
                          childCount: children.length,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showComingSoon('Add Child screen coming in Day 10!');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

/// Widget for displaying a child profile card
class ChildCard extends StatelessWidget {
  const ChildCard({
    super.key,
    required this.child,
    required this.onTap,
  });

  final ChildProfile child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1F2937) : Colors.white;

    return Card(
      margin: EdgeInsets.zero,
      color: surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _getAvatarColor(child.ageBand),
                child: Text(
                  child.nickname.isNotEmpty
                      ? child.nickname[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Age: ${child.ageBand.value}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 10),
                    _buildPolicyChips(child),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPolicyChips(ChildProfile child) {
    final blockedCount = child.policy.blockedCategories.length;
    final scheduleCount = child.policy.schedules.length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (blockedCount > 0)
          Chip(
            label: Text('$blockedCount categories blocked'),
            avatar: const Icon(Icons.block, size: 15),
            visualDensity: VisualDensity.compact,
          ),
        if (scheduleCount > 0)
          Chip(
            label: Text('$scheduleCount schedules'),
            avatar: const Icon(Icons.schedule, size: 15),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Color _getAvatarColor(AgeBand ageBand) {
    switch (ageBand) {
      case AgeBand.young:
        return Colors.blue;
      case AgeBand.middle:
        return Colors.green;
      case AgeBand.teen:
        return Colors.orange;
    }
  }
}
