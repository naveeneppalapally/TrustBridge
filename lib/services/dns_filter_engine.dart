import 'dart:typed_data';

import 'package:trustbridge_app/services/dns_packet_parser.dart';

class DnsFilterDecision {
  const DnsFilterDecision({
    required this.domain,
    required this.blocked,
    required this.parseError,
    required this.reason,
  });

  final String? domain;
  final bool blocked;
  final bool parseError;
  final String reason;
}

class DnsFilterEngine {
  DnsFilterEngine({
    required Iterable<String> blockedDomains,
  }) : _blockedDomains = blockedDomains
            .map(normalizeDomain)
            .where((domain) => domain.isNotEmpty)
            .toSet();

  final Set<String> _blockedDomains;

  static const Set<String> defaultSeedDomains = {
    'facebook.com',
    'instagram.com',
    'tiktok.com',
    'snapchat.com',
    'discord.com',
    'x.com',
  };

  static String normalizeDomain(String domain) {
    var value = domain.trim().toLowerCase();
    while (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  bool shouldBlockDomain(String domain) {
    final normalized = normalizeDomain(domain);
    if (normalized.isEmpty) {
      return false;
    }

    for (final blockedDomain in _blockedDomains) {
      if (normalized == blockedDomain ||
          normalized.endsWith('.$blockedDomain')) {
        return true;
      }
    }
    return false;
  }

  DnsFilterDecision evaluatePacket(Uint8List queryPacket) {
    final domain = DnsPacketParser.extractQueryDomain(queryPacket);
    if (domain == null) {
      return const DnsFilterDecision(
        domain: null,
        blocked: false,
        parseError: true,
        reason: 'Failed to parse DNS query domain.',
      );
    }

    final blocked = shouldBlockDomain(domain);
    return DnsFilterDecision(
      domain: domain,
      blocked: blocked,
      parseError: false,
      reason: blocked
          ? 'Domain matched blocklist policy.'
          : 'Domain allowed by current blocklist.',
    );
  }
}
