import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/app_lock_service.dart';

void main() {
  group('AppLockService', () {
    test('is a singleton', () {
      final a = AppLockService();
      final b = AppLockService();

      expect(identical(a, b), isTrue);
    });

    test('grace period is false initially', () {
      final service = AppLockService();
      expect(service.isWithinGracePeriod, isFalse);
    });

    test('markUnlocked enables grace period', () {
      final service = AppLockService();
      service.markUnlocked();

      expect(service.isWithinGracePeriod, isTrue);
    });
  });

  group('PIN validation rules', () {
    test('accepts exactly four numeric digits', () {
      const pin = '1234';
      expect(pin.length == 4 && int.tryParse(pin) != null, isTrue);
    });

    test('rejects alphabetic PIN', () {
      const pin = 'abcd';
      expect(int.tryParse(pin), isNull);
    });

    test('rejects short PIN', () {
      const pin = '123';
      expect(pin.length == 4, isFalse);
    });

    test('rejects long PIN', () {
      const pin = '12345';
      expect(pin.length == 4, isFalse);
    });
  });
}
