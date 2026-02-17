import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background message handler - must be top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
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

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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
      debugPrint('[FCM] Local notifications unavailable: $error');
    } catch (error) {
      debugPrint('[FCM] Local notification init failed: $error');
    }

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpenedApp);

    try {
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationNavigation(initialMessage.data);
      }
    } catch (error) {
      debugPrint('[FCM] Initial message read failed: $error');
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
      debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
      return granted;
    } catch (error) {
      debugPrint('[FCM] Permission request failed: $error');
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
      debugPrint('[FCM] Token error: $error');
      return null;
    }
  }

  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  Future<bool> showLocalTestNotification({
    String title = 'TrustBridge Test Notification',
    String body = 'Tap to open Access Requests.',
    String route = '/parent-requests',
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
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
      return true;
    } on MissingPluginException catch (error) {
      debugPrint('[FCM] Local test notification unavailable: $error');
      return false;
    } catch (error) {
      debugPrint('[FCM] Local test notification failed: $error');
      return false;
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] Foreground message: ${message.messageId}');

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
    return null;
  }

  void _navigateToRoute(String route) {
    final navigationState = navigatorKey?.currentState;
    if (navigationState == null) {
      debugPrint('[FCM] Navigator not ready for route $route');
      return;
    }
    navigationState.pushNamed(route);
  }
}
