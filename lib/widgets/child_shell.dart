import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/social_media_domains.dart';
import '../models/child_profile.dart';
import '../screens/child/child_status_screen.dart' as child_mode;
import '../screens/child/blocked_overlay_screen.dart';
import '../screens/child_requests_screen.dart';
import '../screens/child_status_screen.dart';
import '../screens/child_tutorial_screen.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/vpn_service.dart';
import '../theme/app_theme.dart';

class ChildShell extends StatefulWidget {
  const ChildShell({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
    this.initialIndex = 0,
    this.enableTutorialGate = true,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;
  final int initialIndex;
  final bool enableTutorialGate;

  @override
  State<ChildShell> createState() => _ChildShellState();
}

class _ChildShellState extends State<ChildShell> {
  late int _currentIndex;
  VpnService? _vpnService;
  bool _overlayVisible = false;

  @override
  void initState() {
    super.initState();
    final rawIndex = widget.initialIndex;
    _currentIndex = rawIndex < 0
        ? 0
        : rawIndex > 2
            ? 2
            : rawIndex;
    _scheduleTutorialGateCheck();
    _registerBlockedDomainListener();
  }

  @override
  void dispose() {
    _vpnService?.setBlockedDomainListener(null);
    super.dispose();
  }

  void _registerBlockedDomainListener() {
    final service = VpnService();
    _vpnService = service;
    service.setBlockedDomainListener((event) {
      if (!mounted || _overlayVisible) {
        return;
      }
      _overlayVisible = true;
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _overlayVisible = false;
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => BlockedOverlayScreen(
              appName: _friendlyAppName(event.domain),
              modeName: event.modeName,
              untilLabel: event.remainingLabel ?? 'later',
            ),
          ),
        );
        _overlayVisible = false;
      });
    });
  }

  String _friendlyAppName(String domain) {
    final normalized = domain.trim().toLowerCase();
    final appKey = SocialMediaDomains.appForDomain(normalized);
    if (appKey == null) {
      return 'This app';
    }
    switch (appKey) {
      case 'instagram':
        return 'Instagram';
      case 'tiktok':
        return 'TikTok';
      case 'twitter':
        return 'Twitter / X';
      case 'snapchat':
        return 'Snapchat';
      case 'facebook':
        return 'Facebook';
      case 'youtube':
        return 'YouTube';
      case 'reddit':
        return 'Reddit';
      case 'roblox':
        return 'Roblox';
      default:
        return 'This app';
    }
  }

  void _scheduleTutorialGateCheck() {
    if (!widget.enableTutorialGate) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _showTutorialIfNeeded();
    });
  }

  Future<void> _showTutorialIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'child_tutorial_seen_${widget.child.id}';
      final seen = prefs.getBool(key) ?? false;
      if (seen || !mounted) {
        return;
      }
      await prefs.setBool(key, true);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ChildTutorialScreen(),
        ),
      );
    } catch (_) {
      // If local prefs are unavailable, skip tutorial gate gracefully.
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusPage = _buildStatusPage();
    final pages = <Widget>[
      statusPage,
      ChildRequestsScreen(
        child: widget.child,
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
      ),
      const _ChildHelpScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        key: const Key('child_shell_bottom_nav'),
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.navUnselected,
        backgroundColor:
            Theme.of(context).bottomNavigationBarTheme.backgroundColor,
        onTap: (index) {
          if (index == _currentIndex) {
            return;
          }
          setState(() {
            _currentIndex = index;
          });
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.help_outline_rounded),
            label: 'Help',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPage() {
    final providedFirestore = widget.firestoreService?.firestore;
    if (_hasFirebaseApp()) {
      return child_mode.ChildStatusScreen(
        firestore: providedFirestore,
        parentId: widget.parentIdOverride,
        childId: widget.child.id,
      );
    }

    // Test fallback: some widget tests don't initialize Firebase.
    return ChildStatusScreen(
      child: widget.child,
      authService: widget.authService,
      firestoreService: widget.firestoreService,
      parentIdOverride: widget.parentIdOverride,
    );
  }

  bool _hasFirebaseApp() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

class _ChildHelpScreen extends StatelessWidget {
  const _ChildHelpScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Need help?\n\nOpen Request Access to ask your parent for temporary allowance.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Locked child mode shell shown when device mode is configured as child.
class ChildModeShell extends StatelessWidget {
  const ChildModeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TrustBridge'),
        automaticallyImplyLeading: false,
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: _VpnStatusIndicator(),
          ),
        ],
      ),
      body: const child_mode.ChildStatusScreen(),
    );
  }
}

class _VpnStatusIndicator extends StatefulWidget {
  const _VpnStatusIndicator();

  @override
  State<_VpnStatusIndicator> createState() => _VpnStatusIndicatorState();
}

class _VpnStatusIndicatorState extends State<_VpnStatusIndicator> {
  final VpnService _vpnService = VpnService();
  late Future<VpnStatus> _statusFuture;

  @override
  void initState() {
    super.initState();
    _statusFuture = _vpnService.getStatus();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VpnStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        final running = snapshot.data?.isRunning == true;
        return Tooltip(
          message: running ? 'Protection active' : 'Protection needs attention',
          child: Icon(
            Icons.circle,
            size: 12,
            color: running ? Colors.green : Colors.red,
          ),
        );
      },
    );
  }
}
