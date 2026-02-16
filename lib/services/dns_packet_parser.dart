import 'dart:typed_data';

class DnsPacketParser {
  static String? extractQueryDomain(Uint8List packet) {
    if (packet.length < 17) {
      return null;
    }

    final qdCount = _readUint16(packet, 4);
    if (qdCount < 1) {
      return null;
    }

    var offset = 12;
    final labels = <String>[];

    while (true) {
      if (offset >= packet.length) {
        return null;
      }
      final labelLength = packet[offset];
      offset += 1;

      if (labelLength == 0) {
        break;
      }

      // Compression pointers are not expected in standard query QNAME sections.
      if ((labelLength & 0xC0) != 0) {
        return null;
      }

      if (labelLength > 63 || offset + labelLength > packet.length) {
        return null;
      }

      final labelBytes = packet.sublist(offset, offset + labelLength);
      labels.add(String.fromCharCodes(labelBytes));
      offset += labelLength;
    }

    // QTYPE + QCLASS must exist.
    if (labels.isEmpty || offset + 4 > packet.length) {
      return null;
    }

    return labels.join('.').toLowerCase();
  }

  static Uint8List buildQueryPacket(
    String domain, {
    int id = 0x1337,
    int qType = 1,
    int qClass = 1,
  }) {
    final normalizedDomain = domain.trim().toLowerCase();
    final labels =
        normalizedDomain.split('.').where((label) => label.isNotEmpty).toList();

    final bytes = <int>[
      (id >> 8) & 0xFF,
      id & 0xFF,
      0x01, // RD=1
      0x00,
      0x00,
      0x01, // QDCOUNT
      0x00,
      0x00, // ANCOUNT
      0x00,
      0x00, // NSCOUNT
      0x00,
      0x00, // ARCOUNT
    ];

    for (final label in labels) {
      final labelBytes = label.codeUnits;
      bytes.add(labelBytes.length);
      bytes.addAll(labelBytes);
    }
    bytes.add(0x00); // QNAME terminator
    bytes.add((qType >> 8) & 0xFF);
    bytes.add(qType & 0xFF);
    bytes.add((qClass >> 8) & 0xFF);
    bytes.add(qClass & 0xFF);

    return Uint8List.fromList(bytes);
  }

  static Uint8List buildNxDomainResponse(Uint8List queryPacket) {
    final questionEndOffset = _findQuestionEndOffset(queryPacket);
    if (queryPacket.length < 12 || questionEndOffset == null) {
      return Uint8List(0);
    }

    final response = <int>[
      queryPacket[0],
      queryPacket[1], // Transaction ID
      0x81 | (queryPacket[2] & 0x01),
      0x83, // QR=1, RA=1, RCODE=3 (NXDOMAIN)
      0x00,
      0x01, // QDCOUNT
      0x00,
      0x00, // ANCOUNT
      0x00,
      0x00, // NSCOUNT
      0x00,
      0x00, // ARCOUNT
      ...queryPacket.sublist(12, questionEndOffset),
    ];

    return Uint8List.fromList(response);
  }

  static int _readUint16(Uint8List bytes, int offset) {
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  static int? _findQuestionEndOffset(Uint8List packet) {
    if (packet.length < 17) {
      return null;
    }

    var offset = 12;
    while (true) {
      if (offset >= packet.length) {
        return null;
      }
      final labelLength = packet[offset];
      offset += 1;

      if (labelLength == 0) {
        break;
      }

      if ((labelLength & 0xC0) != 0) {
        return null;
      }

      if (labelLength > 63 || offset + labelLength > packet.length) {
        return null;
      }

      offset += labelLength;
    }

    if (offset + 4 > packet.length) {
      return null;
    }

    return offset + 4;
  }
}
