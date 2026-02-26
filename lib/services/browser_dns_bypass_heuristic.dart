import 'package:trustbridge_app/services/vpn_service.dart';

class BrowserDnsBypassAssessment {
  const BrowserDnsBypassAssessment({
    required this.shouldWarn,
    required this.browserForeground,
    required this.protectionActive,
    required this.vpnRunning,
    required this.privateDnsActive,
    required this.foregroundPackage,
    required this.recentVpnDnsQueriesInWindow,
    required this.lastVpnDnsQueryAt,
    required this.reasonCode,
    required this.lastBlockedDnsQuery,
  });

  final bool shouldWarn;
  final bool browserForeground;
  final bool protectionActive;
  final bool vpnRunning;
  final bool privateDnsActive;
  final String? foregroundPackage;
  final int recentVpnDnsQueriesInWindow;
  final DateTime? lastVpnDnsQueryAt;
  final String reasonCode;
  final DnsQueryLogEntry? lastBlockedDnsQuery;
}

class BrowserDnsBypassHeuristic {
  const BrowserDnsBypassHeuristic._();

  static const Duration recentDnsWindow = Duration(seconds: 20);
  static const Duration minVpnWarmup = Duration(seconds: 8);

  static const Set<String> browserPackages = <String>{
    'com.android.chrome',
    'org.chromium.chrome',
    'com.chrome.beta',
    'com.chrome.dev',
    'com.microsoft.emmx',
    'org.mozilla.firefox',
    'org.mozilla.firefox_beta',
    'org.mozilla.fenix',
    'com.opera.browser',
    'com.opera.mini.native',
    'com.brave.browser',
    'com.sec.android.app.sbrowser',
    'com.vivo.browser',
    'com.heytap.browser',
    'com.mi.globalbrowser',
    'com.kiwibrowser.browser',
  };

  static bool isLikelyBrowserPackage(String? packageName) {
    final normalized = packageName?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    if (browserPackages.contains(normalized)) {
      return true;
    }
    return normalized.contains('browser') ||
        normalized.contains('chrome') ||
        normalized.contains('firefox');
  }

  static BrowserDnsBypassAssessment evaluate({
    required VpnStatus status,
    required List<DnsQueryLogEntry> recentDnsQueries,
    required String? foregroundPackage,
    DateTime? now,
  }) {
    final timestampNow = now ?? DateTime.now();
    final normalizedPackage = foregroundPackage?.trim().toLowerCase();
    final browserForeground = isLikelyBrowserPackage(normalizedPackage);
    final protectionActive =
        (status.blockedCategoryCount > 0) || (status.blockedDomainCount > 0);

    final lastQueryAt =
        recentDnsQueries.isEmpty ? null : recentDnsQueries.first.timestamp;
    DnsQueryLogEntry? lastBlockedDnsQuery;
    for (final entry in recentDnsQueries) {
      if (entry.blocked) {
        lastBlockedDnsQuery = entry;
        break;
      }
    }
    final cutoff = timestampNow.subtract(recentDnsWindow);
    final recentCount = recentDnsQueries
        .where((entry) => !entry.timestamp.isBefore(cutoff))
        .length;

    if (!status.isRunning) {
      return BrowserDnsBypassAssessment(
        shouldWarn: false,
        browserForeground: browserForeground,
        protectionActive: protectionActive,
        vpnRunning: false,
        privateDnsActive: status.privateDnsActive,
        foregroundPackage: normalizedPackage,
        recentVpnDnsQueriesInWindow: recentCount,
        lastVpnDnsQueryAt: lastQueryAt,
        reasonCode: 'vpn_not_running',
        lastBlockedDnsQuery: lastBlockedDnsQuery,
      );
    }
    if (status.privateDnsActive) {
      return BrowserDnsBypassAssessment(
        shouldWarn: false,
        browserForeground: browserForeground,
        protectionActive: protectionActive,
        vpnRunning: true,
        privateDnsActive: true,
        foregroundPackage: normalizedPackage,
        recentVpnDnsQueriesInWindow: recentCount,
        lastVpnDnsQueryAt: lastQueryAt,
        reasonCode: 'private_dns_active',
        lastBlockedDnsQuery: lastBlockedDnsQuery,
      );
    }
    if (!browserForeground) {
      return BrowserDnsBypassAssessment(
        shouldWarn: false,
        browserForeground: false,
        protectionActive: protectionActive,
        vpnRunning: true,
        privateDnsActive: false,
        foregroundPackage: normalizedPackage,
        recentVpnDnsQueriesInWindow: recentCount,
        lastVpnDnsQueryAt: lastQueryAt,
        reasonCode: 'browser_not_foreground',
        lastBlockedDnsQuery: lastBlockedDnsQuery,
      );
    }

    final startedAt = status.startedAt;
    if (startedAt != null &&
        timestampNow.difference(startedAt) < minVpnWarmup) {
      return BrowserDnsBypassAssessment(
        shouldWarn: false,
        browserForeground: true,
        protectionActive: protectionActive,
        vpnRunning: true,
        privateDnsActive: false,
        foregroundPackage: normalizedPackage,
        recentVpnDnsQueriesInWindow: recentCount,
        lastVpnDnsQueryAt: lastQueryAt,
        reasonCode: 'vpn_warmup',
        lastBlockedDnsQuery: lastBlockedDnsQuery,
      );
    }

    final shouldWarn = recentCount == 0;
    return BrowserDnsBypassAssessment(
      shouldWarn: shouldWarn,
      browserForeground: true,
      protectionActive: protectionActive,
      vpnRunning: true,
      privateDnsActive: false,
      foregroundPackage: normalizedPackage,
      recentVpnDnsQueriesInWindow: recentCount,
      lastVpnDnsQueryAt: lastQueryAt,
      reasonCode:
          shouldWarn ? 'no_recent_vpn_dns_while_browser_foreground' : 'ok',
      lastBlockedDnsQuery: lastBlockedDnsQuery,
    );
  }
}
