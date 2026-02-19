import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/utils/expiry_label_utils.dart';

void main() {
  group('buildExpiryRelativeLabel', () {
    test('returns future label for active expiry', () {
      final now = DateTime(2026, 2, 19, 14, 0, 0);
      final label = buildExpiryRelativeLabel(
        now.add(const Duration(minutes: 25)),
        now: now,
      );
      expect(label, equals('Ends in 25m'));
    });

    test('returns past label for expired window', () {
      final now = DateTime(2026, 2, 19, 14, 0, 0);
      final label = buildExpiryRelativeLabel(
        now.subtract(const Duration(minutes: 3)),
        now: now,
      );
      expect(label, equals('Expired 3m ago'));
    });

    test('formats multi-unit hour/minute duration compactly', () {
      final now = DateTime(2026, 2, 19, 14, 0, 0);
      final label = buildExpiryRelativeLabel(
        now.add(const Duration(hours: 2, minutes: 15)),
        now: now,
      );
      expect(label, equals('Ends in 2h 15m'));
    });
  });
}
