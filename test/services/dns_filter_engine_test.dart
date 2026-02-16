import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/dns_filter_engine.dart';
import 'package:trustbridge_app/services/dns_packet_parser.dart';

void main() {
  group('DnsFilterEngine', () {
    final engine = DnsFilterEngine(
      blockedDomains: {'facebook.com', 'instagram.com'},
    );

    test('blocks exact domain', () {
      expect(engine.shouldBlockDomain('facebook.com'), isTrue);
    });

    test('blocks subdomain when parent domain is blocked', () {
      expect(engine.shouldBlockDomain('m.facebook.com'), isTrue);
    });

    test('allows domain not in blocklist', () {
      expect(engine.shouldBlockDomain('wikipedia.org'), isFalse);
    });

    test('evaluatePacket returns blocked decision for blocked packet', () {
      final query = DnsPacketParser.buildQueryPacket('m.facebook.com');

      final decision = engine.evaluatePacket(query);

      expect(decision.parseError, isFalse);
      expect(decision.blocked, isTrue);
      expect(decision.domain, 'm.facebook.com');
    });

    test('evaluatePacket returns parseError for invalid packet', () {
      final decision = engine.evaluatePacket(Uint8List.fromList([0x01, 0x02]));

      expect(decision.parseError, isTrue);
      expect(decision.blocked, isFalse);
      expect(decision.domain, isNull);
    });
  });
}
