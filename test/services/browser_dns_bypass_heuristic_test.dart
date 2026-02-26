import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/browser_dns_bypass_heuristic.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

void main() {
  group('BrowserDnsBypassHeuristic', () {
    final now = DateTime(2026, 2, 26, 10, 30);

    VpnStatus buildStatus({
      bool isRunning = true,
      bool privateDnsActive = false,
      int blockedCategoryCount = 1,
      int blockedDomainCount = 0,
      DateTime? startedAt,
    }) {
      return VpnStatus(
        supported: true,
        permissionGranted: true,
        isRunning: isRunning,
        blockedCategoryCount: blockedCategoryCount,
        blockedDomainCount: blockedDomainCount,
        privateDnsActive: privateDnsActive,
        startedAt: startedAt ?? now.subtract(const Duration(minutes: 1)),
      );
    }

    DnsQueryLogEntry queryAt(DateTime timestamp) {
      return DnsQueryLogEntry(
        domain: 'instagram.com',
        blocked: true,
        timestamp: timestamp,
        reasonCode: 'block_instant_social_category',
        matchedRule: 'social-networks',
      );
    }

    test('warns when browser is foreground and no recent VPN DNS queries', () {
      final assessment = BrowserDnsBypassHeuristic.evaluate(
        status: buildStatus(),
        recentDnsQueries: const <DnsQueryLogEntry>[],
        foregroundPackage: 'com.android.chrome',
        now: now,
      );

      expect(assessment.shouldWarn, isTrue);
      expect(
          assessment.reasonCode, 'no_recent_vpn_dns_while_browser_foreground');
    });

    test('does not warn when private dns is active', () {
      final assessment = BrowserDnsBypassHeuristic.evaluate(
        status: buildStatus(privateDnsActive: true),
        recentDnsQueries: const <DnsQueryLogEntry>[],
        foregroundPackage: 'com.android.chrome',
        now: now,
      );

      expect(assessment.shouldWarn, isFalse);
      expect(assessment.reasonCode, 'private_dns_active');
    });

    test('does not warn when browser is not foreground', () {
      final assessment = BrowserDnsBypassHeuristic.evaluate(
        status: buildStatus(),
        recentDnsQueries: const <DnsQueryLogEntry>[],
        foregroundPackage: 'com.instagram.android',
        now: now,
      );

      expect(assessment.shouldWarn, isFalse);
      expect(assessment.reasonCode, 'browser_not_foreground');
    });

    test('does not warn when recent dns queries are visible to vpn', () {
      final assessment = BrowserDnsBypassHeuristic.evaluate(
        status: buildStatus(),
        recentDnsQueries: <DnsQueryLogEntry>[
          queryAt(now.subtract(const Duration(seconds: 5))),
          queryAt(now.subtract(const Duration(seconds: 12))),
        ],
        foregroundPackage: 'com.android.chrome',
        now: now,
      );

      expect(assessment.shouldWarn, isFalse);
      expect(assessment.recentVpnDnsQueriesInWindow, 2);
      expect(assessment.reasonCode, 'ok');
      expect(assessment.lastBlockedDnsQuery?.reasonCode,
          'block_instant_social_category');
      expect(assessment.lastBlockedDnsQuery?.matchedRule, 'social-networks');
    });

    test('does not warn during vpn warmup', () {
      final assessment = BrowserDnsBypassHeuristic.evaluate(
        status:
            buildStatus(startedAt: now.subtract(const Duration(seconds: 3))),
        recentDnsQueries: const <DnsQueryLogEntry>[],
        foregroundPackage: 'com.android.chrome',
        now: now,
      );

      expect(assessment.shouldWarn, isFalse);
      expect(assessment.reasonCode, 'vpn_warmup');
    });

    test('recognizes common browser packages', () {
      expect(
        BrowserDnsBypassHeuristic.isLikelyBrowserPackage('com.vivo.browser'),
        isTrue,
      );
      expect(
        BrowserDnsBypassHeuristic.isLikelyBrowserPackage('org.mozilla.fenix'),
        isTrue,
      );
      expect(
        BrowserDnsBypassHeuristic.isLikelyBrowserPackage(
            'com.instagram.android'),
        isFalse,
      );
    });
  });
}
