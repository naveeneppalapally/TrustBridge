import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/dns_packet_parser.dart';

void main() {
  group('DnsPacketParser', () {
    test('extractQueryDomain parses a valid query packet', () {
      final packet = DnsPacketParser.buildQueryPacket('Example.com');

      final domain = DnsPacketParser.extractQueryDomain(packet);

      expect(domain, 'example.com');
    });

    test('extractQueryDomain returns null for invalid packet', () {
      final invalidPacket = Uint8List.fromList([0x00, 0x01, 0x02]);

      final domain = DnsPacketParser.extractQueryDomain(invalidPacket);

      expect(domain, isNull);
    });

    test('buildNxDomainResponse returns response with NXDOMAIN code', () {
      final query = DnsPacketParser.buildQueryPacket(
        'm.facebook.com',
        id: 0xABCD,
      );

      final response = DnsPacketParser.buildNxDomainResponse(query);

      expect(response.isNotEmpty, isTrue);
      expect(response[0], 0xAB);
      expect(response[1], 0xCD);
      expect((response[2] & 0x80) != 0, isTrue); // QR = response
      expect(response[3] & 0x0F, 0x03); // RCODE = NXDOMAIN
      expect(response[5], 0x01); // QDCOUNT low byte = 1
    });
  });
}
