import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../screens/child_requests_screen.dart';
import '../screens/child_status_screen.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class ChildShell extends StatefulWidget {
  const ChildShell({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
    this.initialIndex = 0,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;
  final int initialIndex;

  @override
  State<ChildShell> createState() => _ChildShellState();
}

class _ChildShellState extends State<ChildShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final rawIndex = widget.initialIndex;
    _currentIndex = rawIndex < 0
        ? 0
        : rawIndex > 2
            ? 2
            : rawIndex;
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChildStatusScreen(
        child: widget.child,
        authService: widget.authService,
        firestoreService: widget.firestoreService,
        parentIdOverride: widget.parentIdOverride,
      ),
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
