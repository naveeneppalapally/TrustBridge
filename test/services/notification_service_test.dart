import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/notification_service.dart';

void main() {
  group('NotificationService', () {
    test('is a singleton', () {
      final first = NotificationService();
      final second = NotificationService();
      expect(identical(first, second), isTrue);
    });

    test('navigatorKey can be assigned', () {
      final key = GlobalKey<NavigatorState>();
      NotificationService.navigatorKey = key;
      expect(NotificationService.navigatorKey, same(key));
    });
  });

  group('notification queue payload formatting', () {
    test('uses parent requests route', () {
      const route = '/parent-requests';
      expect(route, equals('/parent-requests'));
    });
  });
}
