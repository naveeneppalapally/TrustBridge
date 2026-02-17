import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/nextdns_service.dart';

void main() {
  group('NextDnsService', () {
    const service = NextDnsService();

    test('validates and normalizes profile ids', () {
      expect(service.isValidProfileId('abc123'), isTrue);
      expect(service.isValidProfileId('ABC123'), isTrue);
      expect(service.isValidProfileId('ab12'), isFalse);
      expect(service.normalizeProfileId('  AbC123  '), 'abc123');
    });

    test('builds endpoint strings from profile id', () {
      expect(service.dohEndpoint('ABC123'), 'https://dns.nextdns.io/abc123');
      expect(service.dotEndpoint('ABC123'), 'abc123.dns.nextdns.io');
      expect(service.upstreamDnsHost('ABC123'), 'abc123.dns.nextdns.io');
    });

    test('sanitizedProfileIdOrNull handles empty values', () {
      expect(service.sanitizedProfileIdOrNull(null), isNull);
      expect(service.sanitizedProfileIdOrNull('   '), isNull);
      expect(service.sanitizedProfileIdOrNull('  abC123 '), 'abc123');
    });
  });
}
