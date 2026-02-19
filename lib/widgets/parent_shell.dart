import 'package:flutter/material.dart';

import '../models/access_request.dart';
import '../models/child_profile.dart';
import '../screens/dashboard_screen.dart';
import '../screens/schedule_creator_screen.dart';
import '../screens/usage_reports_screen.dart';
import '../screens/vpn_protection_screen.dart';
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
        : rawIndex > 3
            ? 3
            : rawIndex;
  }

  void _ensurePendingRequestsStream(String parentId) {
    if (_pendingRequestsStream != null && _pendingStreamParentId == parentId) {
      return;
    }
    _pendingStreamParentId = parentId;
    _pendingRequestsStream =
        _resolvedFirestoreService.getPendingRequestsStream(parentId);
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

    _ensurePendingRequestsStream(parentId);

    final pages = <Widget>[
      DashboardScreen(
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
        onShellTabRequested: (int index) {
          if (_currentIndex == index) {
            return;
          }
          setState(() {
            _currentIndex = index;
          });
        },
      ),
      _ParentScheduleTab(
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
      ),
      const UsageReportsScreen(),
      VpnProtectionScreen(
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
      ),
    ];

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>('parent_shell_pending_$parentId'),
      stream: _pendingRequestsStream,
      builder: (context, snapshot) {
        final pendingCount = snapshot.data?.length ?? 0;

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
            onTap: (index) {
              if (index == _currentIndex) {
                return;
              }
              setState(() {
                _currentIndex = index;
              });
            },
            items: <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: _DashboardNavIcon(pendingCount: pendingCount),
                label: 'Dashboard',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.schedule_rounded),
                label: 'Schedule',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart_rounded),
                label: 'Reports',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.security_rounded),
                label: 'Security',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardNavIcon extends StatelessWidget {
  const _DashboardNavIcon({required this.pendingCount});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        const Icon(Icons.dashboard_rounded),
        if (pendingCount > 0)
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

class _ParentScheduleTab extends StatefulWidget {
  const _ParentScheduleTab({
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<_ParentScheduleTab> createState() => _ParentScheduleTabState();
}

class _ParentScheduleTabState extends State<_ParentScheduleTab> {
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
    final override = widget.parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return _resolvedAuthService.currentUser?.uid;
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in to configure schedules.'),
        ),
      );
    }

    return StreamBuilder<List<ChildProfile>>(
      key: ValueKey<String>('parent_shell_schedule_children_$parentId'),
      stream: _resolvedFirestoreService.getChildrenStream(parentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Schedule')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load children for schedules.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final children = snapshot.data ?? const <ChildProfile>[];
        if (children.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Schedule')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.family_restroom, size: 56),
                    SizedBox(height: 12),
                    Text(
                      'Add a child profile first to configure schedules.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ScheduleCreatorScreen(
          child: children.first,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        );
      },
    );
  }
}
