import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

void main() {
  group('DnsQueryLogEntry.fromMap', () {
    test('parses optional reason and matched rule fields', () {
      final entry = DnsQueryLogEntry.fromMap(<String, dynamic>{
        'domain': 'instagram.com',
        'blocked': true,
        'reasonCode': 'block_instant_social_category',
        'matchedRule': 'social-networks',
        'timestampEpochMs': 1700000000000,
      });

      expect(entry.domain, 'instagram.com');
      expect(entry.blocked, isTrue);
      expect(entry.reasonCode, 'block_instant_social_category');
      expect(entry.matchedRule, 'social-networks');
      expect(entry.timestamp.millisecondsSinceEpoch, 1700000000000);
    });

    test('gracefully handles missing optional fields', () {
      final entry = DnsQueryLogEntry.fromMap(<String, dynamic>{
        'domain': 'reddit.com',
        'blocked': false,
        'timestampEpochMs': 1700000000001,
      });

      expect(entry.reasonCode, isNull);
      expect(entry.matchedRule, isNull);
    });
  });
}
