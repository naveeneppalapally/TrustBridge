import 'package:flutter/material.dart';

import '../models/dashboard_state.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import 'add_child_screen.dart';
import 'child_control_screen.dart';

class ChildrenHomeScreen extends StatefulWidget {
  const ChildrenHomeScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
    this.dashboardState,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;
  final DashboardStateSnapshot? dashboardState;

  @override
  State<ChildrenHomeScreen> createState() => _ChildrenHomeScreenState();
}

class _ChildrenHomeScreenState extends State<ChildrenHomeScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  bool _updatingPause = false;

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
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please sign in to view your children.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final dashboardState = widget.dashboardState;
    final children =
        dashboardState?.children ?? const <DashboardChildSummary>[];
    final isLoading = dashboardState == null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greetingLabel(),
                          style: AppTextStyles.labelCaps(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your Family',
                          style: AppTextStyles.displayMedium(),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('children_home_add_child_button'),
                    tooltip: 'Add Child',
                    icon: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: _openAddChild,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (isLoading) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        24,
                      ),
                      children: const <Widget>[
                        _StaticPlaceholderCard(),
                        SizedBox(height: 12),
                        _StaticPlaceholderCard(),
                      ],
                    );
                  }

                  if (children.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.family_restroom,
                              size: 56,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No children added yet.',
                              style: AppTextStyles.headingMedium(),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add a child to start protection controls.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _CalmButton(
                              label: 'Add Child',
                              icon: Icons.add,
                              onTap: _openAddChild,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      24,
                    ),
                    itemBuilder: (context, index) {
                      final child = children[index];
                      return _ChildOverviewCard(
                        child: child,
                        pauseBusy: _updatingPause,
                        onPausePressed: () => _togglePause(child, parentId),
                        onTap: () => _openChildControl(child, parentId),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: children.length,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greetingLabel() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  Future<void> _openChildControl(
    DashboardChildSummary summary,
    String parentId,
  ) async {
    final child = await _resolvedFirestoreService.getChild(
      parentId: parentId,
      childId: summary.childId,
    );
    if (!mounted) {
      return;
    }
    if (child == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Child profile is unavailable right now.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChildControlScreen(
          childId: summary.childId,
          initialChild: child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _togglePause(
    DashboardChildSummary child,
    String parentId,
  ) async {
    if (_updatingPause) {
      return;
    }

    final paused = child.isPaused;
    setState(() {
      _updatingPause = true;
    });
    try {
      await _resolvedFirestoreService.setChildPause(
        parentId: parentId,
        childId: child.childId,
        pausedUntil:
            paused ? null : DateTime.now().add(const Duration(hours: 8)),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paused
                ? 'Internet resumed for ${child.name}.'
                : 'Internet paused for ${child.name}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update internet pause right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingPause = false;
        });
      }
    }
  }

  void _openAddChild() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddChildScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }
}

class _ChildOverviewCard extends StatelessWidget {
  const _ChildOverviewCard({
    required this.child,
    required this.pauseBusy,
    required this.onPausePressed,
    required this.onTap,
  });

  final DashboardChildSummary child;
  final bool pauseBusy;
  final VoidCallback onPausePressed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paused = child.isPaused;
    final initial = child.name.isNotEmpty ? child.name[0].toUpperCase() : '?';
    final status = child.protectionStatus.trim().toLowerCase();
    final isOffline = status == 'offline';
    final protectedNow = status == 'protected';
    final statusDotColor = protectedNow ? AppColors.success : AppColors.danger;

    final modeLabel = () {
      switch (child.activeMode.trim().toLowerCase()) {
        case 'paused':
          return 'Lockdown';
        case 'bedtime':
          return 'Bedtime';
        case 'homework':
          return 'Homework';
        case 'off':
          return 'Protection Off';
        case 'free_play':
        case 'free':
        case '':
          return 'Free Play';
        default:
          return 'Focus';
      }
    }();

    final statusLabel = () {
      switch (status) {
        case 'protected':
          return 'Protected';
        case 'offline':
          return 'Offline';
        case 'disabled':
          return 'Disabled';
        default:
          return 'Unprotected';
      }
    }();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryDim,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: AppTextStyles.headingLarge(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.headingMedium(),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        modeLabel,
                        style: AppTextStyles.bodySmall(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isOffline
                        ? AppColors.surfaceBorder.withValues(alpha: 0.5)
                        : (protectedNow
                            ? AppColors.primaryDim
                            : AppColors.dangerDim),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isOffline)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: statusDotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        statusLabel,
                        style: AppTextStyles.label(
                          color: isOffline
                              ? AppColors.textMuted
                              : (protectedNow
                                  ? AppColors.primary
                                  : AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CalmButton(
                    label: 'Manage',
                    icon: Icons.tune_rounded,
                    onTap: onTap,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CalmButton(
                    label: paused ? 'Resume' : 'Pause',
                    icon:
                        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    onTap: pauseBusy ? null : onPausePressed,
                    isSecondary: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalmButton extends StatelessWidget {
  const _CalmButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isSecondary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isSecondary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isSecondary ? AppColors.surface : AppColors.primaryDim,
          borderRadius: BorderRadius.circular(12),
          border: isSecondary
              ? Border.all(color: AppColors.surfaceBorder, width: 0.5)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSecondary ? AppColors.textSecondary : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.label(
                color:
                    isSecondary ? AppColors.textSecondary : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticPlaceholderCard extends StatelessWidget {
  const _StaticPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
      ),
    );
  }
}
