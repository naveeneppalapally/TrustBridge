import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/screens/child_requests_screen.dart';
import 'package:trustbridge_app/screens/child_status_screen.dart';
import 'package:trustbridge_app/screens/dashboard_screen.dart';
import 'package:trustbridge_app/screens/dns_analytics_screen.dart';
import 'package:trustbridge_app/screens/login_screen.dart';
import 'package:trustbridge_app/screens/onboarding_screen.dart';
import 'package:trustbridge_app/screens/parent_requests_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/notification_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  NotificationService.navigatorKey = GlobalKey<NavigatorState>();
  runApp(const MyApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(NotificationService().initialize());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF2094F3);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PolicyVpnSyncService>(
          create: (_) => PolicyVpnSyncService(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        showPerformanceOverlay: kDebugMode &&
            const bool.fromEnvironment(
              'SHOW_PERF_OVERLAY',
              defaultValue: false,
            ),
        title: 'TrustBridge',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F7F8),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF101A22),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const AuthWrapper(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/add-child': (context) => const AddChildScreen(),
          '/parent-requests': (context) => const ParentRequestsScreen(),
          '/dns-analytics': (context) => const DnsAnalyticsScreen(),
          '/onboarding': (context) {
            final parentId = ModalRoute.of(context)?.settings.arguments;
            if (parentId is! String || parentId.trim().isEmpty) {
              return const LoginScreen();
            }
            return OnboardingScreen(parentId: parentId);
          },
          '/child-status': (context) {
            final child =
                ModalRoute.of(context)!.settings.arguments as ChildProfile;
            return ChildStatusScreen(child: child);
          },
          '/child-requests': (context) {
            final child =
                ModalRoute.of(context)!.settings.arguments as ChildProfile;
            return ChildRequestsScreen(child: child);
          },
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();
  String? _lastSyncUserId;
  String? _lastNotificationUserId;
  StreamSubscription<String>? _tokenRefreshSubscription;

  void _schedulePolicySyncUpdate(User? user) {
    final nextUserId = user?.uid;
    if (_lastSyncUserId == nextUserId) {
      return;
    }
    _lastSyncUserId = nextUserId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final syncService = context.read<PolicyVpnSyncService?>();
      if (syncService == null) {
        return;
      }
      if (nextUserId == null) {
        syncService.stopListening();
      } else {
        syncService.startListening();
      }
    });
  }

  void _scheduleNotificationSyncUpdate(User? user) {
    final nextUserId = user?.uid;
    if (_lastNotificationUserId == nextUserId) {
      return;
    }

    final previousUserId = _lastNotificationUserId;
    _lastNotificationUserId = nextUserId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      if (previousUserId != null && previousUserId != nextUserId) {
        try {
          await _firestoreService.removeFcmToken(previousUserId);
        } catch (error) {
          debugPrint('[FCM] Failed removing token: $error');
        }
      }

      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;

      if (nextUserId == null) {
        return;
      }

      await _notificationService.requestPermission();

      final token = await _notificationService.getToken();
      if (token != null && token.trim().isNotEmpty) {
        try {
          await _firestoreService.saveFcmToken(nextUserId, token);
        } catch (error) {
          debugPrint('[FCM] Failed saving token: $error');
        }
      }

      _tokenRefreshSubscription =
          _notificationService.onTokenRefresh.listen((String refreshedToken) {
        final trimmedToken = refreshedToken.trim();
        if (trimmedToken.isEmpty) {
          return;
        }
        unawaited(_firestoreService.saveFcmToken(nextUserId, trimmedToken));
      });
    });
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        _schedulePolicySyncUpdate(snapshot.data);
        _scheduleNotificationSyncUpdate(snapshot.data);

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData) {
          return FutureBuilder<bool>(
            key: ValueKey<String>('onboarding-${snapshot.data!.uid}'),
            future: _firestoreService.isOnboardingComplete(snapshot.data!.uid),
            builder: (context, onboardingSnapshot) {
              if (onboardingSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (onboardingSnapshot.hasError) {
                return const DashboardScreen();
              }

              final onboardingComplete = onboardingSnapshot.data ?? false;
              if (!onboardingComplete) {
                return OnboardingScreen(parentId: snapshot.data!.uid);
              }

              return const DashboardScreen();
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}
