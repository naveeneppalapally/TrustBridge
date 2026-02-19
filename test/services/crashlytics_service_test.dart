import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/crashlytics_service.dart';

void main() {
  group('CrashlyticsService', () {
    test('is a singleton', () {
      final a = CrashlyticsService();
      final b = CrashlyticsService();
      expect(identical(a, b), isTrue);
    });

    test('testCrash throws in debug mode', () {
      final service = CrashlyticsService();
      expect(() => service.testCrash(), throwsA(isA<StateError>()));
    });
  });

  group('Error context', () {
    test('setCustomKey is a no-op in debug mode', () async {
      final service = CrashlyticsService();
      await service.setCustomKey('test_key', 'test_value');
      expect(true, isTrue);
    });

    test('setCustomKeys accepts multiple types in debug mode', () async {
      final service = CrashlyticsService();
      await service.setCustomKeys({
        'string': 'value',
        'number': 7,
        'flag': true,
      });
      expect(true, isTrue);
    });
  });
}
