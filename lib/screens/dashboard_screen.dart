import 'dart:async';

import 'package:trustbridge_app/l10n/app_localizations.dart';
import 'package:trustbridge_app/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/screens/child_detail_screen.dart';
import 'package:trustbridge_app/screens/parent_settings_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/performance_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';
import 'package:trustbridge_app/utils/app_lock_guard.dart';

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

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  Stream<List<ChildProfile>>? _childrenStream;
  Stream<List<AccessRequest>>? _pendingRequestsStream;
  Stream<Map<String, dynamic>?>? _parentProfileStream;
  String? _streamsParentId;
  final PerformanceService _performanceService = PerformanceService();
  PerformanceTrace? _dashboardLoadTrace;
  Stopwatch? _dashboardLoadStopwatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startDashboardLoadTrace());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopDashboardLoadTrace());
    super.dispose();
  }

  Future<void> _startDashboardLoadTrace() async {
    final trace = await _performanceService.startTrace('dashboard_load');
    if (!mounted) {
      await _performanceService.stopTrace(trace);
      return;
    }
    _dashboardLoadTrace = trace;
    _dashboardLoadStopwatch = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_stopDashboardLoadTrace());
    });
  }

  Future<void> _stopDashboardLoadTrace() async {
    final trace = _dashboardLoadTrace;
    if (trace == null) {
      return;
    }
    _dashboardLoadTrace = null;
    final stopwatch = _dashboardLoadStopwatch;
    _dashboardLoadStopwatch = null;
    if (stopwatch != null) {
      stopwatch.stop();
      await _performanceService.setMetric(
        trace,
        'duration_ms',
        stopwatch.elapsedMilliseconds,
      );
      await _performanceService.annotateThreshold(
        trace: trace,
        name: 'dashboard_load_ms',
        actualValue: stopwatch.elapsedMilliseconds,
        warningValue: PerformanceThresholds.dashboardLoadWarningMs,
      );
    }
    await _performanceService.stopTrace(trace);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      context.read<PolicyVpnSyncService?>()?.syncNow();
    }
  }

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

  void _ensureParentStreams(String parentId) {
    if (_streamsParentId == parentId &&
        _childrenStream != null &&
        _pendingRequestsStream != null &&
        _parentProfileStream != null) {
      return;
    }

    _streamsParentId = parentId;
    _childrenStream = _resolvedFirestoreService.getChildrenStream(parentId);
    _pendingRequestsStream =
        _resolvedFirestoreService.getPendingRequestsStream(parentId);
    _parentProfileStream = _resolvedFirestoreService.watchParentProfile(
      parentId,
    );
  }

  Future<void> _handleSignOut() async {
    await _resolvedAuthService.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed('/login');
  }

  Future<void> _openSettings() async {
    await guardedNavigate(
      context,
      () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ParentSettingsScreen(
              authService: widget.authService,
              firestoreService: widget.firestoreService,
              parentIdOverride: widget.parentIdOverride,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestsAction() {
    final l10n = _l10n(context);
    final pendingRequestsStream = _pendingRequestsStream;
    if (pendingRequestsStream == null) {
      return IconButton(
        key: const Key('dashboard_requests_button'),
        icon: const Icon(Icons.notifications_outlined),
        tooltip: l10n.accessRequestsTitle,
        onPressed: () {
          Navigator.of(context).pushNamed('/parent-requests');
        },
      );
    }

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>('dashboard_pending_${_streamsParentId ?? 'none'}'),
      stream: pendingRequestsStream,
      builder:
          (BuildContext context, AsyncSnapshot<List<AccessRequest>> snapshot) {
        final pendingCount = snapshot.data?.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            IconButton(
              key: const Key('dashboard_requests_button'),
              icon: const Icon(Icons.notifications_outlined),
              tooltip: l10n.accessRequestsTitle,
              onPressed: () {
                Navigator.of(context).pushNamed('/parent-requests');
              },
            ),
            if (pendingCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  key: const Key('dashboard_requests_badge'),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      pendingCount > 9 ? '9+' : '$pendingCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderMenu() {
    final l10n = _l10n(context);
    return PopupMenuButton<String>(
      key: const Key('dashboard_header_menu'),
      icon: const Icon(Icons.more_horiz),
      tooltip: 'More actions',
      onSelected: (String value) async {
        switch (value) {
          case 'analytics':
            Navigator.of(context).pushNamed('/dns-analytics');
            break;
          case 'settings':
            await _openSettings();
            break;
          case 'signout':
            await _handleSignOut();
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'analytics',
          child: Text(l10n.analyticsTitle),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Text(l10n.settingsTitle),
        ),
        const PopupMenuItem<String>(
          value: 'signout',
          child: Text('Sign out'),
        ),
      ],
    );
  }

  String _greetingForTime(DateTime now) {
    final hour = now.hour;
    if (hour < 12) {
      return 'Good Morning';
    }
    if (hour < 17) {
      return 'Good Afternoon';
    }
    return 'Good Evening';
  }

  String _resolveParentName(Map<String, dynamic>? parentProfile) {
    final nestedProfile = _asMap(parentProfile?['parentProfile']);
    final nestedName = _stringOrNull(nestedProfile['displayName']);
    if (nestedName != null && nestedName.isNotEmpty) {
      return nestedName;
    }

    final rootName = _stringOrNull(parentProfile?['displayName']);
    if (rootName != null && rootName.isNotEmpty) {
      return rootName;
    }

    final email = _stringOrNull(parentProfile?['email']) ?? '';
    if (email.contains('@')) {
      final prefix = email.split('@').first.trim();
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
    }

    return 'Parent';
  }

  bool _isShieldActive(Map<String, dynamic>? parentProfile) {
    final preferences = _asMap(parentProfile?['preferences']);
    return preferences['vpnProtectionEnabled'] == true;
  }

  String _formatDurationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  double _screenTimeProgress(List<ChildProfile> children) {
    final targetMinutes = children.length * 120;
    if (targetMinutes == 0) {
      return 0;
    }
    final estimatedMinutes = children.length * 65;
    return (estimatedMinutes / targetMinutes).clamp(0.0, 1.0);
  }

  Map<String, dynamic> _asMap(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }
    if (rawValue is Map) {
      return rawValue.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  String? _stringOrNull(Object? rawValue) {
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return rawValue.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final parentId = _parentId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1F2937) : Colors.white;
    final backgroundColor =
        isDark ? const Color(0xFF101A22) : const Color(0xFFF5F7F8);

    if (parentId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.appTitle)),
        body: Center(child: Text(l10n.notLoggedInMessage)),
      );
    }
    _ensureParentStreams(parentId);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _parentProfileStream,
        builder: (
          BuildContext context,
          AsyncSnapshot<Map<String, dynamic>?> parentSnapshot,
        ) {
          final parentProfile = parentSnapshot.data;
          final parentName = _resolveParentName(parentProfile);
          final greeting = _greetingForTime(DateTime.now());
          final shieldActive = _isShieldActive(parentProfile);

          return StreamBuilder<List<ChildProfile>>(
            key: ValueKey<String>(
              'dashboard_children_${_streamsParentId ?? 'none'}',
            ),
            stream: _childrenStream,
            builder: (context, snapshot) {
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: () => setState(() {}),
                          child: Text(l10n.retryButton),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final children = snapshot.data ?? const <ChildProfile>[];
              final width = MediaQuery.sizeOf(context).width;
              final isTablet = width >= 600;
              final screenTimeLabel = children.isEmpty
                  ? '--'
                  : _formatDurationLabel(
                      Duration(minutes: children.length * 65),
                    );

              if (children.isEmpty) {
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isTablet ? 24 : 16,
                          16,
                          isTablet ? 24 : 16,
                          0,
                        ),
                        child: _DashboardHeader(
                          greeting: greeting,
                          parentName: parentName,
                          requestsAction: _buildRequestsAction(),
                          menuAction: _buildHeaderMenu(),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isTablet ? 24 : 16,
                          16,
                          isTablet ? 24 : 16,
                          0,
                        ),
                        child: _TrustSummaryCard(
                          key: const Key('dashboard_trust_summary_card'),
                          surfaceColor: surfaceColor,
                          isDark: isDark,
                          shieldActive: shieldActive,
                          totalScreenTime: screenTimeLabel,
                          activeThreats: 'None',
                          progress: _screenTimeProgress(children),
                        ),
                      ),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 16),
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              Icon(
                                Icons.family_restroom,
                                size: 92,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                l10n.noChildrenMessage,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.noChildrenSubtitle,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                              ),
                              const SizedBox(height: 28),
                              FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const AddChildScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.add),
                                label: Text(l10n.addChildButton),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 24 : 16,
                        16,
                        isTablet ? 24 : 16,
                        0,
                      ),
                      child: _DashboardHeader(
                        greeting: greeting,
                        parentName: parentName,
                        requestsAction: _buildRequestsAction(),
                        menuAction: _buildHeaderMenu(),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 24 : 16,
                        16,
                        isTablet ? 24 : 16,
                        0,
                      ),
                      child: _TrustSummaryCard(
                        key: const Key('dashboard_trust_summary_card'),
                        surfaceColor: surfaceColor,
                        isDark: isDark,
                        shieldActive: shieldActive,
                        totalScreenTime: screenTimeLabel,
                        activeThreats: 'None',
                        progress: _screenTimeProgress(children),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      isTablet ? 24 : 16,
                      20,
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
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChildDetailScreen(
                                          child: child,
                                        ),
                                      ),
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
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ChildDetailScreen(
                                            child: child,
                                          ),
                                        ),
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
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AddChildScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.greeting,
    required this.parentName,
    required this.requestsAction,
    required this.menuAction,
  });

  final String greeting;
  final String parentName;
  final Widget requestsAction;
  final Widget menuAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade500,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                parentName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
        requestsAction,
        menuAction,
      ],
    );
  }
}

class _TrustSummaryCard extends StatelessWidget {
  const _TrustSummaryCard({
    super.key,
    required this.surfaceColor,
    required this.isDark,
    required this.shieldActive,
    required this.totalScreenTime,
    required this.activeThreats,
    required this.progress,
  });

  final Color surfaceColor;
  final bool isDark;
  final bool shieldActive;
  final String totalScreenTime;
  final String activeThreats;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Trust Summary',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: shieldActive
                      ? const Color(0xFF1E88E5).withValues(alpha: 0.14)
                      : Colors.grey.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  shieldActive ? 'SHIELD ACTIVE' : 'SHIELD OFF',
                  style: TextStyle(
                    color: shieldActive
                        ? const Color(0xFF1E88E5)
                        : Colors.grey.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TrustMetricTile(
                  label: 'TOTAL SCREEN TIME',
                  value: totalScreenTime,
                  trailingLabel: 'Today',
                  valueColor: Theme.of(context).textTheme.titleLarge?.color ??
                      Colors.black87,
                  progress: progress,
                  progressColor: Theme.of(context).colorScheme.primary,
                  progressTrackColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TrustMetricTile(
                  label: 'ACTIVE THREATS',
                  value: activeThreats,
                  trailingLabel: 'Privacy scan complete',
                  valueColor: activeThreats == 'None'
                      ? const Color(0xFF00A86B)
                      : Theme.of(context).colorScheme.error,
                  progress: 0,
                  progressColor: Colors.transparent,
                  progressTrackColor: Colors.transparent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustMetricTile extends StatelessWidget {
  const _TrustMetricTile({
    required this.label,
    required this.value,
    required this.trailingLabel,
    required this.valueColor,
    required this.progress,
    required this.progressColor,
    required this.progressTrackColor,
  });

  final String label;
  final String value;
  final String trailingLabel;
  final Color valueColor;
  final double progress;
  final Color progressColor;
  final Color progressTrackColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade500,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
          ),
          const SizedBox(height: 10),
          if (progress > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: progress,
                backgroundColor: progressTrackColor,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
          if (progress > 0) const SizedBox(height: 8),
          Text(
            trailingLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                ),
          ),
        ],
      ),
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
    final l10n = _l10n(context);
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
                      l10n.ageLabel(child.ageBand.value),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 10),
                    _buildPolicyChips(context, child),
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

  Widget _buildPolicyChips(BuildContext context, ChildProfile child) {
    final l10n = _l10n(context);
    final blockedCount = child.policy.blockedCategories.length;
    final scheduleCount = child.policy.schedules.length;
    final paused =
        child.pausedUntil != null && child.pausedUntil!.isAfter(DateTime.now());

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (paused)
          Chip(
            label: Text(l10n.pausedLabel),
            avatar: const Icon(Icons.pause_circle_outline, size: 15),
            visualDensity: VisualDensity.compact,
            backgroundColor: Colors.red.shade50,
            side: BorderSide(color: Colors.red.shade200),
            labelStyle: TextStyle(color: Colors.red.shade900),
          ),
        if (blockedCount > 0)
          Chip(
            label: Text(l10n.categoriesBlockedCount(blockedCount)),
            avatar: const Icon(Icons.block, size: 15),
            visualDensity: VisualDensity.compact,
          ),
        if (scheduleCount > 0)
          Chip(
            label: Text(l10n.schedulesCount(scheduleCount)),
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

AppLocalizations _l10n(BuildContext context) {
  return AppLocalizations.of(context) ?? AppLocalizationsEn();
}
