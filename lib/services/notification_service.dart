import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/core/utils/app_logger.dart';
import 'package:trustbridge_app/services/child_effective_policy_sync_service.dart';

const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

/// Background message handler - must be top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.debug(
    '[FCM_ARRIVAL] background messageId=${message.messageId} data=${message.data}',
  );
  AppLogger.debug('[FCM] Background message: ${message.messageId}');
  if (message.data['type'] == 'policy_update') {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await ChildEffectivePolicySyncService.instance.handlePolicyUpdatePush(
        payload: message.data,
        source: 'fcm_background',
      );
    } catch (error) {
      AppLogger.debug('[FCM] Background policy_update handling failed: $error');
    }
  }
}

class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  static GlobalKey<NavigatorState>? navigatorKey;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;

    if (!_isFlutterTest) {
      try {
        FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler);
      } on MissingPluginException catch (error) {
        AppLogger.debug('[FCM] Background handler unavailable: $error');
      } catch (error) {
        AppLogger.debug('[FCM] Background handler registration failed: $error');
      }
    }

    try {
      const channel = AndroidNotificationChannel(
        'trustbridge_requests',
        'Access Requests',
        description: 'Notifications when your child requests access',
        importance: Importance.high,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
    } on MissingPluginException catch (error) {
      AppLogger.debug('[FCM] Local notifications unavailable: $error');
    } catch (error) {
      AppLogger.debug('[FCM] Local notification init failed: $error');
    }

    try {
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpenedApp);
    } on MissingPluginException catch (error) {
      AppLogger.debug('[FCM] Foreground listeners unavailable: $error');
    } catch (error) {
      AppLogger.debug('[FCM] Foreground listener setup failed: $error');
    }

    try {
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationNavigation(initialMessage.data);
      }
    } catch (error) {
      AppLogger.debug('[FCM] Initial message read failed: $error');
    }
  }

  Future<bool> requestPermission() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      AppLogger.debug('[FCM] Permission: ${settings.authorizationStatus}');
      return granted;
    } catch (error) {
      AppLogger.debug('[FCM] Permission request failed: $error');
      return false;
    }
  }

  Future<AuthorizationStatus> getAuthorizationStatus() async {
    try {
      final settings = await _fcm.getNotificationSettings();
      return settings.authorizationStatus;
    } catch (_) {
      return AuthorizationStatus.notDetermined;
    }
  }

  Future<bool> areNotificationsAuthorized() async {
    final status = await getAuthorizationStatus();
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  Future<String?> getToken() async {
    try {
      final token = await _fcm.getToken();
      return token;
    } catch (error) {
      AppLogger.debug('[FCM] Token error: $error');
      return null;
    }
  }

  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  Future<bool> showLocalNotification({
    required String title,
    required String body,
    required String route,
  }) async {
    if (title.trim().isEmpty) {
      return false;
    }
    if (body.trim().isEmpty) {
      return false;
    }
    if (route.trim().isEmpty) {
      return false;
    }

    try {
      if (!_isInitialized) {
        await initialize();
      }

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title.trim(),
        body.trim(),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'trustbridge_requests',
            'Access Requests',
            channelDescription: 'Notifications when your child requests access',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: route.trim(),
      );
      return true;
    } on MissingPluginException catch (error) {
      AppLogger.debug('[FCM] Local notification unavailable: $error');
      return false;
    } catch (error) {
      AppLogger.debug('[FCM] Local notification failed: $error');
      return false;
    }
  }

  Future<bool> showLocalTestNotification({
    String title = 'TrustBridge Test Notification',
    String body = 'Tap to open Access Requests.',
    String route = '/parent-requests',
  }) async {
    return showLocalNotification(
      title: title,
      body: body,
      route: route,
    );
  }

  void _onForegroundMessage(RemoteMessage message) {
    AppLogger.debug(
      '[FCM_ARRIVAL] foreground messageId=${message.messageId} data=${message.data}',
    );
    AppLogger.debug('[FCM] Foreground message: ${message.messageId}');
    if (message.data['type'] == 'policy_update') {
      unawaited(
        ChildEffectivePolicySyncService.instance.handlePolicyUpdatePush(
          payload: message.data,
          source: 'fcm_foreground',
        ),
      );
      return;
    }

    final notification = message.notification;
    if (notification == null) {
      return;
    }

    final route = _extractRoute(message.data);
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'trustbridge_requests',
          'Access Requests',
          channelDescription: 'Notifications when your child requests access',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: route,
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    final route = response.payload;
    if (route != null && route.trim().isNotEmpty) {
      _navigateToRoute(route);
    }
  }

  void _onNotificationOpenedApp(RemoteMessage message) {
    _handleNotificationNavigation(message.data);
  }

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final route = _extractRoute(data);
    if (route == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToRoute(route);
    });
  }

  String? _extractRoute(Map<String, dynamic> data) {
    final routeValue = data['route'];
    if (routeValue is String && routeValue.trim().isNotEmpty) {
      return routeValue.trim();
    }
    final typeValue = data['type'];
    if (typeValue == 'access_request') {
      return '/parent-requests';
    }
    if (typeValue == 'access_request_response') {
      return '/child/status';
    }
    return null;
  }

  void _navigateToRoute(String route) {
    final navigationState = navigatorKey?.currentState;
    if (navigationState == null) {
      AppLogger.debug('[FCM] Navigator not ready for route $route');
      return;
    }
    navigationState.pushNamed(route);
  }
}
