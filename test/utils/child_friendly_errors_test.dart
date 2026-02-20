import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/utils/child_friendly_errors.dart';

void main() {
  group('ChildFriendlyErrors', () {
    test('NXDOMAIN is sanitized', () {
      final message = ChildFriendlyErrors.sanitise('NXDOMAIN lookup failed');
      expect(message.toLowerCase(), isNot(contains('nxdomain')));
    });

    test('VPN tunnel error is sanitized', () {
      final message = ChildFriendlyErrors.sanitise('VPN tunnel error');
      expect(message.toLowerCase(), isNot(contains('vpn')));
      expect(message.toLowerCase(), isNot(contains('tunnel')));
    });

    test('DNS resolution failed is sanitized', () {
      final message = ChildFriendlyErrors.sanitise('DNS resolution failed');
      expect(message.toLowerCase(), isNot(contains('dns')));
    });

    test('connection timeout returns friendly timeout message', () {
      final message = ChildFriendlyErrors.sanitise('Connection timeout');
      expect(message, equals('No internet connection.'));
    });

    test('unknown errors return default message', () {
      final message = ChildFriendlyErrors.sanitise('Random unknown error xyz');
      expect(
        message,
        equals('Something went wrong. Try again or ask your parent.'),
      );
    });

    test('all messages stay short', () {
      final outputs = <String>[
        ChildFriendlyErrors.sanitise('NXDOMAIN'),
        ChildFriendlyErrors.sanitise('VPN tunnel error'),
        ChildFriendlyErrors.sanitise('DNS resolution failed'),
        ChildFriendlyErrors.sanitise('Connection timeout'),
        ChildFriendlyErrors.sanitise('permission denied'),
        ChildFriendlyErrors.sanitise('Random unknown error xyz'),
      ];

      for (final output in outputs) {
        expect(output.length, lessThan(80));
      }
    });
  });
}
