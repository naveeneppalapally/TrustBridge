import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trustbridge_app/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/models/app_mode.dart';
import 'package:trustbridge_app/models/blocklist_source.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/config/feature_gates.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/screens/add_child_device_screen.dart';
import 'package:trustbridge_app/screens/beta_feedback_history_screen.dart';
import 'package:trustbridge_app/screens/beta_feedback_screen.dart';
import 'package:trustbridge_app/screens/child_protection_permission_screen.dart';
import 'package:trustbridge_app/screens/child_setup_screen.dart';
import 'package:trustbridge_app/screens/child_requests_screen.dart';
import 'package:trustbridge_app/screens/dns_analytics_screen.dart';
import 'package:trustbridge_app/screens/login_screen.dart';
import 'package:trustbridge_app/screens/onboarding_screen.dart';
import 'package:trustbridge_app/screens/open_source_licenses_screen.dart';
import 'package:trustbridge_app/screens/parent/bypass_alerts_screen.dart';
import 'package:trustbridge_app/screens/parent/alert_preferences_screen.dart';
import 'package:trustbridge_app/screens/parent_requests_screen.dart';
import 'package:trustbridge_app/screens/upgrade_screen.dart';
import 'package:trustbridge_app/screens/welcome_screen.dart';
import 'package:trustbridge_app/routing/router_guard.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/app_mode_service.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/notification_service.dart';
import 'package:trustbridge_app/services/blocklist_workmanager_service.dart';
import 'package:trustbridge_app/services/onboarding_state_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';
import 'package:trustbridge_app/services/policy_vpn_sync_service.dart';
import 'package:trustbridge_app/theme/app_theme.dart';
import 'package:trustbridge_app/widgets/child_shell.dart';
import 'package:trustbridge_app/widgets/parent_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 12));
  } catch (error) {
    debugPrint('[Startup] Firebase initialization timed out/skipped: $error');
  }
  try {
    await AppModeService()
        .primeCache()
        .timeout(const Duration(seconds: 3));
  } catch (error) {
    debugPrint('[Startup] App mode cache prime timed out/skipped: $error');
  }
  if (!kDebugMode) {
    try {
      await _initCrashlytics().timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('[Startup] Crashlytics initialization skipped: $error');
    }
  }
  try {
    await _initPerformance().timeout(const Duration(seconds: 4));
  } catch (error) {
    debugPrint('[Startup] Performance initialization skipped: $error');
  }
  NotificationService.navigatorKey = GlobalKey<NavigatorState>();
  runApp(const MyApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(NotificationService().initialize());
    // Defer background scheduler registration until after first frame to
    // minimize startup jank and reduce ANR risk on lower-memory devices.
    unawaited(_initBlocklistWorkmanager());
  });
}

Future<void> _initBlocklistWorkmanager() async {
  try {
    await BlocklistWorkmanagerService.initialize();
    await BlocklistWorkmanagerService.registerWeeklySync(
      List<BlocklistCategory>.from(BlocklistCategory.values),
    );
  } catch (error) {
    debugPrint('[BlocklistWork] Initialization skipped: $error');
  }
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
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final shortestSide = media.size.shortestSide;
          final baseScale = shortestSide >= 720
              ? 1.10
              : shortestSide >= 600
                  ? 1.06
                  : shortestSide <= 360
                      ? 0.93
                      : 1.0;
          final userScale = media.textScaler.scale(14) / 14;
          final normalizedUserScale = userScale.clamp(0.90, 1.10);
          final clampedScale =
              (baseScale * normalizedUserScale).clamp(0.90, 1.12);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(clampedScale),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const _ModeRootScreen(),
        onGenerateRoute: _onGenerateRoute,
      ),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final requested = settings.name ?? '/welcome';
    final redirect = resolveModeRedirect(
      mode: AppModeService().cachedMode,
      location: requested,
    );
    final resolvedName = _canonicalRouteName(redirect ?? requested);

    return MaterialPageRoute<void>(
      settings: RouteSettings(
        name: resolvedName,
        arguments: settings.arguments,
      ),
      builder: (_) => _buildRouteScreen(
        routeName: resolvedName,
        arguments: settings.arguments,
      ),
    );
  }

  String _canonicalRouteName(String routeName) {
    switch (routeName) {
      case '/login':
        return '/parent/login';
      case '/dashboard':
        return '/parent/dashboard';
      case '/child-status':
        return '/child/status';
      default:
        return routeName;
    }
  }

  Widget _buildRouteScreen({
    required String routeName,
    required Object? arguments,
  }) {
    switch (routeName) {
      case '/welcome':
        return const WelcomeScreen();
      case '/parent/login':
        return const LoginScreen();
      case '/parent/dashboard':
        return const _DashboardEntryScreen();
      case '/add-child':
        return const AddChildScreen();
      case '/parent-requests':
        return const ParentRequestsScreen();
      case '/parent/bypass-alerts':
        return const BypassAlertsScreen();
      case '/parent/alert-preferences':
        return const AlertPreferencesScreen();
      case '/dns-analytics':
        return const DnsAnalyticsScreen();
      case '/upgrade':
        if (arguments is AppFeature) {
          return UpgradeScreen(triggeredBy: arguments);
        }
        return const UpgradeScreen(triggeredBy: AppFeature.schedules);
      case '/open-source-licenses':
        return const OpenSourceLicensesScreen();
      case '/beta-feedback':
        return const BetaFeedbackScreen();
      case '/beta-feedback-history':
        return const BetaFeedbackHistoryScreen();
      case '/child/status':
        return const _ChildModeEntryScreen();
      case '/child/setup':
        return const ChildSetupScreen();
      case '/child/protection-permission':
        return const ChildProtectionPermissionScreen();
      case '/add-child-device':
        if (arguments is ChildProfile) {
          return AddChildDeviceScreen(child: arguments);
        }
        return const ParentShell();
      case '/child-shell':
        if (arguments is ChildProfile) {
          return ChildShell(child: arguments);
        }
        return const _ChildModeEntryScreen();
      case '/onboarding':
        if (arguments is! String || arguments.trim().isEmpty) {
          return const LoginScreen();
        }
        return OnboardingScreen(parentId: arguments);
      case '/child-requests':
        if (arguments is ChildProfile) {
          return ChildRequestsScreen(child: arguments);
        }
        return const _ChildModeEntryScreen();
      default:
        return const WelcomeScreen();
    }
  }
}

class _ModeRootScreen extends StatefulWidget {
  const _ModeRootScreen();

  @override
  State<_ModeRootScreen> createState() => _ModeRootScreenState();
}

class _ModeRootScreenState extends State<_ModeRootScreen> {
  final AppModeService _appModeService = AppModeService();
  Future<void>? _modePrimeFuture;

  @override
  void initState() {
    super.initState();
    _modePrimeFuture = _appModeService.primeCache();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _modePrimeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        switch (_appModeService.cachedMode) {
          case AppMode.parent:
            return const AuthWrapper();
          case AppMode.child:
            return const _ChildModeEntryScreen();
          case AppMode.unset:
            return const WelcomeScreen();
        }
      },
    );
  }
}

class _ChildModeEntryScreen extends StatefulWidget {
  const _ChildModeEntryScreen();

  @override
  State<_ChildModeEntryScreen> createState() => _ChildModeEntryScreenState();
}

class _ChildModeEntryScreenState extends State<_ChildModeEntryScreen> {
  final PairingService _pairingService = PairingService();
  Future<bool>? _pairedFuture;

  @override
  void initState() {
    super.initState();
    _pairedFuture = _isPairingComplete();
  }

  Future<bool> _isPairingComplete() async {
    final childId = await _pairingService.getPairedChildId();
    final parentId = await _pairingService.getPairedParentId();
    return (childId?.trim().isNotEmpty ?? false) &&
        (parentId?.trim().isNotEmpty ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _pairedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final paired = snapshot.data ?? false;
        if (!paired) {
          return const ChildSetupScreen();
        }

        return const ChildModeShell();
      },
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
  Future<_LaunchRoute>? _launchRouteFuture;
  String? _launchRouteUserId;
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

  void _clearLaunchRouteCache() {
    _launchRouteFuture = null;
    _launchRouteUserId = null;
  }

  void _ensureLaunchRouteFuture(User user) {
    if (_launchRouteFuture != null && _launchRouteUserId == user.uid) {
      return;
    }
    _launchRouteUserId = user.uid;
    _launchRouteFuture = _resolveLaunchRoute(user);
  }

  Future<_LaunchRoute> _resolveLaunchRoute(User user) async {
    return _loadLaunchRoute(
      firestoreService: _firestoreService,
      user: user,
    );
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

        final user = snapshot.data;
        if (user == null) {
          _clearLaunchRouteCache();
          return const LoginScreen();
        }

        _ensureLaunchRouteFuture(user);

        return FutureBuilder<_LaunchRoute>(
          key: ValueKey<String>('onboarding-${user.uid}'),
          future: _launchRouteFuture,
          builder: (context, launchSnapshot) {
            if (launchSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final launchRoute = launchSnapshot.data;
            if (launchSnapshot.hasError || launchRoute == null) {
              return OnboardingScreen(parentId: user.uid);
            }

            if (!launchRoute.onboardingComplete) {
              return OnboardingScreen(parentId: launchRoute.parentId);
            }

            return const ParentShell();
          },
        );
      },
    );
  }
}

class _LaunchRoute {
  const _LaunchRoute({
    required this.parentId,
    required this.onboardingComplete,
  });

  final String parentId;
  final bool onboardingComplete;
}

Future<_LaunchRoute> _loadLaunchRoute({
  required FirestoreService firestoreService,
  required User user,
}) async {
  final onboardingStateService = OnboardingStateService();
  var localCompletion = false;
  try {
    localCompletion = await onboardingStateService
        .isCompleteLocally(user.uid)
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    localCompletion = false;
  }

  if (localCompletion) {
    unawaited(
      _reconcileOnboardingStateWithCloud(
        firestoreService: firestoreService,
        onboardingStateService: onboardingStateService,
        user: user,
      ),
    );
    return _LaunchRoute(
      parentId: user.uid,
      onboardingComplete: true,
    );
  }

  try {
    await firestoreService
        .ensureParentProfile(
          parentId: user.uid,
          phoneNumber: user.phoneNumber,
        )
        .timeout(const Duration(seconds: 12));

    final parentPrefs = await firestoreService
        .getParentPreferences(user.uid)
        .timeout(const Duration(seconds: 12));
    final remoteCompletion =
        (parentPrefs?['onboardingComplete'] as bool?) ?? false;
    final onboardingComplete = remoteCompletion || localCompletion;

    if (remoteCompletion && !localCompletion) {
      unawaited(onboardingStateService.markCompleteLocally(user.uid));
    } else if (onboardingComplete && !remoteCompletion) {
      unawaited(firestoreService.completeOnboarding(user.uid));
    }

    return _LaunchRoute(
      parentId: user.uid,
      onboardingComplete: onboardingComplete,
    );
  } catch (error) {
    debugPrint('[AuthWrapper] Launch route fallback: $error');
    return _LaunchRoute(
      parentId: user.uid,
      onboardingComplete: localCompletion,
    );
  }
}

Future<void> _reconcileOnboardingStateWithCloud({
  required FirestoreService firestoreService,
  required OnboardingStateService onboardingStateService,
  required User user,
}) async {
  try {
    await firestoreService
        .ensureParentProfile(
          parentId: user.uid,
          phoneNumber: user.phoneNumber,
        )
        .timeout(const Duration(seconds: 12));
    final parentPrefs = await firestoreService
        .getParentPreferences(user.uid)
        .timeout(const Duration(seconds: 12));
    final remoteCompletion =
        (parentPrefs?['onboardingComplete'] as bool?) ?? false;
    if (!remoteCompletion) {
      await firestoreService.completeOnboarding(user.uid).timeout(
            const Duration(seconds: 12),
          );
    } else {
      await onboardingStateService.markCompleteLocally(user.uid).timeout(
            const Duration(seconds: 2),
          );
    }
  } catch (error) {
    debugPrint('[AuthWrapper] Cloud reconciliation skipped: $error');
  }
}

class _DashboardEntryScreen extends StatefulWidget {
  const _DashboardEntryScreen();

  @override
  State<_DashboardEntryScreen> createState() => _DashboardEntryScreenState();
}

class _DashboardEntryScreenState extends State<_DashboardEntryScreen> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  Future<_LaunchRoute>? _launchRouteFuture;
  String? _launchRouteUserId;

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    if (user == null) {
      return const LoginScreen();
    }

    if (_launchRouteFuture == null || _launchRouteUserId != user.uid) {
      _launchRouteUserId = user.uid;
      _launchRouteFuture = _loadLaunchRoute(
        firestoreService: _firestoreService,
        user: user,
      );
    }

    return FutureBuilder<_LaunchRoute>(
      future: _launchRouteFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final launchRoute = snapshot.data;
        if (snapshot.hasError || launchRoute == null) {
          return OnboardingScreen(parentId: user.uid);
        }

        if (!launchRoute.onboardingComplete) {
          return OnboardingScreen(parentId: launchRoute.parentId);
        }

        return const ParentShell();
      },
    );
  }
}
