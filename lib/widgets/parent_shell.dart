import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trustbridge_app/config/feature_gates.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';

import '../models/access_request.dart';
import '../models/child_profile.dart';
import '../screens/block_categories_screen.dart';
import '../screens/child_detail_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/help_support_screen.dart';
import '../screens/mode_overrides_screen.dart';
import '../screens/parent_settings_screen.dart';
import '../screens/parent/protection_settings_screen.dart';
import '../screens/schedule_creator_screen.dart';
import '../screens/upgrade_screen.dart';
import '../screens/usage_reports_screen.dart';
import '../services/auth_service.dart';
import '../services/feature_gate_service.dart';
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
  final FeatureGateService _featureGateService = FeatureGateService();
  final GlobalKey<ScaffoldState> _shellScaffoldKey = GlobalKey<ScaffoldState>();

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
        : rawIndex > 4
            ? 4
            : rawIndex;
  }

  void _ensurePendingRequestsStream(String parentId) {
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
      _ParentModesTab(
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
      ),
      _ParentBlockAppsTab(
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
      ),
      _ParentReportsTab(
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
              key: _shellScaffoldKey,
              drawer: RolloutFlags.adaptiveParentNav
                  ? _buildAdvancedDrawer(context)
                  : null,
              body: IndexedStack(
                index: _currentIndex,
                children: pages,
              ),
              floatingActionButton: RolloutFlags.adaptiveParentNav
                  ? FloatingActionButton.small(
                      key: const Key('parent_shell_advanced_drawer_button'),
                      heroTag: 'parent_shell_advanced_drawer',
                      tooltip: 'Advanced',
                      onPressed: () {
                        _shellScaffoldKey.currentState?.openDrawer();
                      },
                      child: const Icon(Icons.menu_rounded),
                    )
                  : null,
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
                  unawaited(_handleTabTap(index));
                },
                items: <BottomNavigationBarItem>[
                  BottomNavigationBarItem(
                    icon: _DashboardNavIcon(pendingCount: totalBadgeCount),
                    label: 'Dashboard',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.tune_rounded),
                    label: 'Modes',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.security_rounded),
                    label: 'Block Apps',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.bar_chart_rounded),
                    label: 'Reports',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.settings_rounded),
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

  Widget _buildAdvancedDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const ListTile(
              title: Text(
                'Advanced',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('App Library, diagnostics, permissions, support'),
            ),
            const Divider(height: 12),
            ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: const Text('App Library'),
              subtitle: const Text('Child installed apps and block controls'),
              onTap: () {
                Navigator.of(context).pop();
                setState(() {
                  _currentIndex = 2;
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.monitor_heart_rounded),
              title: const Text('Diagnostics'),
              subtitle: const Text('Protection health and runtime checks'),
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProtectionSettingsScreen(
                      authService: widget.authService,
                      firestoreService: widget.firestoreService,
                      parentIdOverride: widget.parentIdOverride,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_rounded),
              title: const Text('Permissions'),
              subtitle: const Text('Review protection permissions'),
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProtectionSettingsScreen(
                      authService: widget.authService,
                      firestoreService: widget.firestoreService,
                      parentIdOverride: widget.parentIdOverride,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: const Text('Support'),
              subtitle: const Text('Send feedback or support request'),
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HelpSupportScreen(
                      authService: widget.authService,
                      firestoreService: widget.firestoreService,
                      parentIdOverride: widget.parentIdOverride,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTabTap(int index) async {
    if (index == _currentIndex) {
      return;
    }

    if (index == 1) {
      GateResult gate;
      try {
        gate = await _featureGateService.checkGate(AppFeature.schedules);
      } catch (_) {
        // Fail-open in non-Firebase test contexts.
        gate = const GateResult(allowed: true);
      }
      if (!gate.allowed) {
        if (!mounted) {
          return;
        }
        await UpgradeScreen.maybeShow(
          context,
          feature: AppFeature.schedules,
          reason: gate.upgradeReason,
        );
        return;
      }
    }

    setState(() {
      _currentIndex = index;
    });
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

class _ParentModesTab extends StatefulWidget {
  const _ParentModesTab({
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<_ParentModesTab> createState() => _ParentModesTabState();
}

class _ParentModesTabState extends State<_ParentModesTab> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  String? _selectedChildId;

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
    try {
      return _resolvedAuthService.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in to configure modes.'),
        ),
      );
    }

    return StreamBuilder<List<ChildProfile>>(
      key: ValueKey<String>('parent_shell_modes_children_$parentId'),
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
            appBar: AppBar(title: const Text('Modes')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load children for modes.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final children = snapshot.data ?? const <ChildProfile>[];
        final selected = _selectedChild(children, _selectedChildId);

        return Scaffold(
          appBar: AppBar(title: const Text('Modes')),
          body: children.isEmpty
              ? const _NoChildMessage(
                  message:
                      'Add a child profile first to configure mode controls.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _ChildPickerCard(
                      children: children,
                      selectedChildId: _selectedChildId,
                      onChanged: (value) {
                        setState(() {
                          _selectedChildId = value?.trim().isEmpty ?? true
                              ? null
                              : value?.trim();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (selected == null)
                      const _SelectChildPrompt()
                    else ...[
                      _ModeStatusCard(child: selected),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ChildDetailScreen(
                                  child: selected,
                                  authService: widget.authService,
                                  firestoreService: widget.firestoreService,
                                  parentIdOverride: widget.parentIdOverride,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.gamepad_rounded),
                          label: const Text('Open Mode Remote'),
                        ),
                      ),
                      if (RolloutFlags.modeAppOverrides) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ModeOverridesScreen(
                                    child: selected,
                                    authService: widget.authService,
                                    firestoreService: widget.firestoreService,
                                    parentIdOverride: widget.parentIdOverride,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Edit Per-Mode App Overrides'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ScheduleCreatorScreen(
                                  child: selected,
                                  authService: widget.authService,
                                  firestoreService: widget.firestoreService,
                                  parentIdOverride: widget.parentIdOverride,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.schedule_rounded),
                          label: const Text('Open Schedule Editor'),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ParentBlockAppsTab extends StatefulWidget {
  const _ParentBlockAppsTab({
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<_ParentBlockAppsTab> createState() => _ParentBlockAppsTabState();
}

class _ParentBlockAppsTabState extends State<_ParentBlockAppsTab> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  String? _selectedChildId;

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
    try {
      return _resolvedAuthService.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in to manage app blocking rules.'),
        ),
      );
    }

    return StreamBuilder<List<ChildProfile>>(
      key: ValueKey<String>('parent_shell_block_apps_children_$parentId'),
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
            appBar: AppBar(title: const Text('Block Apps')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load child profiles for blocking.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final children = snapshot.data ?? const <ChildProfile>[];
        final selected = _selectedChild(children, _selectedChildId);

        if (children.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Block Apps')),
            body: const _NoChildMessage(
              message:
                  'Add a child profile first to configure app blocking rules.',
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Block Apps')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _ChildPickerCard(
                  children: children,
                  selectedChildId: _selectedChildId,
                  onChanged: (value) {
                    setState(() {
                      _selectedChildId =
                          value?.trim().isEmpty ?? true ? null : value?.trim();
                    });
                  },
                ),
              ),
              Expanded(
                child: selected == null
                    ? const _SelectChildPrompt()
                    : BlockCategoriesScreen(
                        key:
                            ValueKey<String>('block_categories_${selected.id}'),
                        child: selected,
                        authService: widget.authService,
                        firestoreService: widget.firestoreService,
                        parentIdOverride: widget.parentIdOverride,
                        showAppBar: false,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ParentReportsTab extends StatefulWidget {
  const _ParentReportsTab({
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<_ParentReportsTab> createState() => _ParentReportsTabState();
}

class _ParentReportsTabState extends State<_ParentReportsTab> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  String? _selectedChildId;

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
    try {
      return _resolvedAuthService.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in to view reports.'),
        ),
      );
    }
    return StreamBuilder<List<ChildProfile>>(
      key: ValueKey<String>('parent_shell_reports_children_$parentId'),
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
            appBar: AppBar(title: const Text('Reports')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load child profiles for reports.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final children = snapshot.data ?? const <ChildProfile>[];
        final selected = _selectedChild(children, _selectedChildId);

        return Scaffold(
          appBar: AppBar(title: const Text('Reports')),
          body: children.isEmpty
              ? const _NoChildMessage(
                  message: 'Add a child profile first to view usage reports.',
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: _ChildPickerCard(
                        children: children,
                        selectedChildId: _selectedChildId,
                        onChanged: (value) {
                          setState(() {
                            _selectedChildId = value?.trim().isEmpty ?? true
                                ? null
                                : value?.trim();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: selected == null
                          ? const _SelectChildPrompt()
                          : UsageReportsScreen(
                              showAppBar: false,
                              authService: widget.authService,
                              firestoreService: widget.firestoreService,
                              parentIdOverride: widget.parentIdOverride,
                              childIdOverride: selected.id,
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

ChildProfile? _selectedChild(
  List<ChildProfile> children,
  String? selectedChildId,
) {
  final normalizedId = selectedChildId?.trim();
  if (normalizedId == null || normalizedId.isEmpty) {
    if (!RolloutFlags.explicitChildSelection && children.isNotEmpty) {
      return children.first;
    }
    return null;
  }
  for (final child in children) {
    if (child.id.trim() == normalizedId) {
      return child;
    }
  }
  if (!RolloutFlags.explicitChildSelection && children.isNotEmpty) {
    return children.first;
  }
  return null;
}

class _ChildPickerCard extends StatelessWidget {
  const _ChildPickerCard({
    required this.children,
    required this.selectedChildId,
    required this.onChanged,
  });

  final List<ChildProfile> children;
  final String? selectedChildId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selected child',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedChildId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Choose a child',
              ),
              items: children
                  .map(
                    (child) => DropdownMenuItem<String>(
                      value: child.id,
                      child: Text(child.nickname),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectChildPrompt extends StatelessWidget {
  const _SelectChildPrompt();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Choose a child above to continue.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _NoChildMessage extends StatelessWidget {
  const _NoChildMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.family_restroom, size: 56),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ModeStatusCard extends StatelessWidget {
  const _ModeStatusCard({required this.child});

  final ChildProfile child;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final pausedUntil = child.pausedUntil;
    String modeLabel = 'Free Play';
    String detail = 'No active restriction mode.';
    Color color = Colors.green.shade700;

    if (pausedUntil != null && pausedUntil.isAfter(now)) {
      modeLabel = 'Pause All';
      detail = 'Active until ${_timeLabel(pausedUntil)}';
      color = Colors.red.shade700;
    } else {
      final rawManual = child.manualMode ?? const <String, dynamic>{};
      final manualMode = (rawManual['mode'] as String?)?.trim().toLowerCase();
      final expiresAtDate = rawManual['expiresAt'] as DateTime?;
      if (manualMode == 'bedtime') {
        modeLabel = 'Bedtime';
        detail = expiresAtDate is DateTime
            ? 'Manual mode until ${_timeLabel(expiresAtDate)}'
            : 'Manual mode active';
        color = Colors.indigo;
      } else if (manualMode == 'homework') {
        modeLabel = 'Homework';
        detail = expiresAtDate is DateTime
            ? 'Manual mode until ${_timeLabel(expiresAtDate)}'
            : 'Manual mode active';
        color = Colors.orange.shade700;
      } else if (manualMode == 'free') {
        modeLabel = 'Free Play';
        detail = 'Manual free mode active';
        color = Colors.green.shade700;
      } else if (child.policy.schedules.isNotEmpty) {
        modeLabel = 'Scheduled';
        detail = '${child.policy.schedules.length} schedule rules configured';
        color = Colors.blue.shade700;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(Icons.timer_rounded, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Currently Active',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    modeLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(detail),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeLabel(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}
