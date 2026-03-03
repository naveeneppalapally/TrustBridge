import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dashboard_state.dart';
import '../screens/children_home_screen.dart';
import '../screens/parent_settings_screen.dart';
import '../services/app_lock_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class ParentShell extends StatefulWidget {
  const ParentShell({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
    this.initialIndex = 0,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;
  final int initialIndex;

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> with WidgetsBindingObserver {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  Stream<DashboardStateSnapshot?>? _dashboardStateStream;
  String? _dashboardStateParentId;
  late int _currentIndex;
  bool _lockPromptVisible = false;

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
    WidgetsBinding.instance.addObserver(this);
    final rawIndex = widget.initialIndex;
    _currentIndex = rawIndex < 0
        ? 0
        : rawIndex > 1
            ? 1
            : rawIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_enforceParentAppLock());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_enforceParentAppLock());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_enforceParentAppLock());
    });
  }

  Future<void> _enforceParentAppLock() async {
    if (!mounted || _lockPromptVisible) {
      return;
    }
    final appLockService = AppLockService();
    var biometricPreferenceEnabled = false;
    final parentId = _parentId;
    if (parentId != null && parentId.trim().isNotEmpty) {
      try {
        final profile =
            await _resolvedFirestoreService.getParentProfile(parentId);
        final preferences = profile?['preferences'];
        if (preferences is Map<String, dynamic>) {
          biometricPreferenceEnabled =
              preferences['biometricLoginEnabled'] == true;
        } else if (preferences is Map) {
          biometricPreferenceEnabled =
              preferences['biometricLoginEnabled'] == true;
        }
      } catch (_) {
        biometricPreferenceEnabled = false;
      }
    }

    if (!biometricPreferenceEnabled) {
      return;
    }
    if (appLockService.isWithinGracePeriod) {
      return;
    }
    if (!mounted) {
      return;
    }

    _lockPromptVisible = true;
    final unlocked = await appLockService.authenticateWithBiometric();
    if (unlocked) {
      appLockService.markUnlocked();
    }
    _lockPromptVisible = false;
    if (!mounted) {
      return;
    }
    if (!unlocked) {
      await _resolvedAuthService.signOut();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacementNamed('/welcome');
    }
  }

  void _ensureStreams(String parentId) {
    if (_dashboardStateStream != null && _dashboardStateParentId == parentId) {
      return;
    }

    _dashboardStateParentId = parentId;
    _dashboardStateStream = _resolvedFirestoreService.watchDashboardState(
      parentId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('TrustBridge')),
        body: const Center(
          child: Text('Please sign in to access the parent dashboard.'),
        ),
      );
    }

    _ensureStreams(parentId);

    return StreamBuilder<DashboardStateSnapshot?>(
      key: ValueKey<String>('parent_shell_dashboard_state_$parentId'),
      stream: _dashboardStateStream,
      builder: (context, snapshot) {
        final dashboardState = snapshot.data;
        final activePage = _currentIndex == 0
            ? ChildrenHomeScreen(
                authService: widget.authService,
                firestoreService: widget.firestoreService,
                parentIdOverride: widget.parentIdOverride,
                dashboardState: dashboardState,
              )
            : ParentSettingsScreen(
                authService: widget.authService,
                firestoreService: widget.firestoreService,
                parentIdOverride: widget.parentIdOverride,
              );

        return Scaffold(
          body: activePage,
          bottomNavigationBar: _CalmBottomNav(
            key: const Key('parent_shell_bottom_nav'),
            currentIndex: _currentIndex,
            badgeCount: dashboardState?.totalPendingRequests ?? 0,
            onTap: _handleTabTap,
          ),
        );
      },
    );
  }

  void _handleTabTap(int index) {
    if (index == _currentIndex) {
      return;
    }

    setState(() {
      _currentIndex = index;
    });
  }
}

/// Redesigned bottom navigation: 64px, icon-only, pill indicator, no labels.
class _CalmBottomNav extends StatelessWidget {
  const _CalmBottomNav({
    super.key,
    required this.currentIndex,
    required this.badgeCount,
    required this.onTap,
  });

  final int currentIndex;
  final int badgeCount;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64 + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.family_restroom_rounded,
            isSelected: currentIndex == 0,
            badgeCount: badgeCount,
            onTap: () => onTap(0),
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            isSelected: currentIndex == 1,
            badgeCount: 0,
            onTap: () => onTap(1),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.isSelected,
    required this.badgeCount,
    required this.onTap,
  });

  final IconData icon;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.primary : AppColors.textMuted,
                  size: 24,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      key: const Key('parent_shell_dashboard_badge'),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Pill indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 16 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
