import 'dart:async';

import 'package:flutter/material.dart';

import '../models/access_request.dart';
import '../screens/children_home_screen.dart';
import '../screens/parent_settings_screen.dart';
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

class _ParentShellState extends State<ParentShell> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  Stream<List<AccessRequest>>? _pendingRequestsStream;
  Stream<int>? _unreadBypassAlertCountStream;
  String? _pendingStreamParentId;
  late int _currentIndex;

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
    final rawIndex = widget.initialIndex;
    _currentIndex = rawIndex < 0
        ? 0
        : rawIndex > 1
            ? 1
            : rawIndex;
  }

  void _ensureStreams(String parentId) {
    if (_pendingRequestsStream != null &&
        _unreadBypassAlertCountStream != null &&
        _pendingStreamParentId == parentId) {
      return;
    }

    _pendingStreamParentId = parentId;
    _pendingRequestsStream =
        _resolvedFirestoreService.getPendingRequestsStream(parentId);
    _unreadBypassAlertCountStream =
        _resolvedFirestoreService.getUnreadBypassAlertCountStream(parentId);
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

    final pages = <Widget>[
      ChildrenHomeScreen(
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
      ),
      ParentSettingsScreen(
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
      ),
    ];

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>('parent_shell_pending_$parentId'),
      stream: _pendingRequestsStream,
      builder: (context, pendingSnapshot) {
        final pendingCount = pendingSnapshot.data?.length ?? 0;

        return StreamBuilder<int>(
          key: ValueKey<String>('parent_shell_unread_alerts_$parentId'),
          stream: _unreadBypassAlertCountStream,
          builder: (context, alertSnapshot) {
            final unreadAlertCount = alertSnapshot.data ?? 0;
            final totalBadgeCount = pendingCount + unreadAlertCount;

            return Scaffold(
              body: IndexedStack(
                index: _currentIndex,
                children: pages,
              ),
              bottomNavigationBar: BottomNavigationBar(
                key: const Key('parent_shell_bottom_nav'),
                currentIndex: _currentIndex,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.navUnselected,
                backgroundColor:
                    Theme.of(context).bottomNavigationBarTheme.backgroundColor,
                elevation: 8,
                onTap: _handleTabTap,
                items: <BottomNavigationBarItem>[
                  BottomNavigationBarItem(
                    icon: _ChildrenNavIcon(badgeCount: totalBadgeCount),
                    label: 'Children',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.settings_outlined),
                    label: 'Settings',
                  ),
                ],
              ),
            );
          },
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

class _ChildrenNavIcon extends StatelessWidget {
  const _ChildrenNavIcon({required this.badgeCount});

  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        const Icon(Icons.family_restroom_rounded),
        if (badgeCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              key: const Key('parent_shell_dashboard_badge'),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
