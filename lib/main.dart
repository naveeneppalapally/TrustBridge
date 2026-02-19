import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/screens/beta_feedback_history_screen.dart';
import 'package:trustbridge_app/screens/beta_feedback_screen.dart';
import 'package:trustbridge_app/screens/child_requests_screen.dart';
import 'package:trustbridge_app/screens/child_status_screen.dart';
import 'package:trustbridge_app/screens/dashboard_screen.dart';
import 'package:trustbridge_app/screens/dns_analytics_screen.dart';
import 'package:trustbridge_app/screens/login_screen.dart';
import 'package:trustbridge_app/screens/onboarding_screen.dart';
import 'package:trustbridge_app/screens/parent_requests_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/notification_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (!kDebugMode) {
    await _initCrashlytics();
  }
  await _initPerformance();
  NotificationService.navigatorKey = GlobalKey<NavigatorState>();
  runApp(const MyApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(NotificationService().initialize());
  });
}

Future<void> _initCrashlytics() async {
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  await CrashlyticsService().setCustomKeys({
    'build_mode': kReleaseMode ? 'release' : 'profile',
    'build_name': const String.fromEnvironment(
      'FLUTTER_BUILD_NAME',
      defaultValue: 'unknown',
    ),
    'build_number': const String.fromEnvironment(
      'FLUTTER_BUILD_NUMBER',
      defaultValue: 'unknown',
    ),
  });

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        fatal: true,
      ),
    );
    return true;
  };
}

Future<void> _initPerformance() async {
  try {
    await FirebasePerformance.instance
        .setPerformanceCollectionEnabled(!kDebugMode);
  } catch (error) {
    debugPrint('[Performance] Initialization skipped: $error');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static Future<void> setLocale(
    BuildContext context,
    Locale locale,
  ) async {
    final state = context.findAncestorStateOfType<_MyAppState>();
    if (state == null) {
      return;
    }
    await state._updateLocale(locale, persist: true);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedLocale());
  }

  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('language_code');
    if (!mounted || languageCode == null || languageCode.trim().isEmpty) {
      return;
    }
    final locale = Locale(languageCode.trim());
    await _updateLocale(locale, persist: false);
  }

  Future<void> _updateLocale(
    Locale locale, {
    required bool persist,
  }) async {
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language_code', locale.languageCode);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _locale = locale;
    });
  }

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
        locale: _locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
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
          '/beta-feedback': (context) => const BetaFeedbackScreen(),
          '/beta-feedback-history': (context) =>
              const BetaFeedbackHistoryScreen(),
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
  final CrashlyticsService _crashlyticsService = CrashlyticsService();
  String? _lastSyncUserId;
  String? _lastNotificationUserId;
  String? _lastCrashlyticsUserId;
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

  void _scheduleCrashlyticsUserContext(User? user) {
    final nextUserId = user?.uid;
    if (_lastCrashlyticsUserId == nextUserId) {
      return;
    }
    _lastCrashlyticsUserId = nextUserId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      if (nextUserId == null) {
        await _crashlyticsService.clearUserId();
        await _crashlyticsService.setCustomKeys({
          'auth_state': 'signed_out',
          'user_id': 'none',
        });
        return;
      }
      await _crashlyticsService.setUserId(nextUserId);
      await _crashlyticsService.setCustomKeys({
        'auth_state': 'signed_in',
        'user_id': nextUserId,
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
        _scheduleCrashlyticsUserContext(snapshot.data);

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
