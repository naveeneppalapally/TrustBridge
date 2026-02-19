import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VpnService', () {
    const channelName = 'trustbridge/vpn_test';
    const channel = MethodChannel(channelName);
    late VpnService service;

    setUp(() {
      service = VpnService(
        channel: channel,
        forceSupported: true,
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getStatus maps channel response', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStatus') {
          return {
            'supported': true,
            'permissionGranted': true,
            'isRunning': true,
            'queriesProcessed': 12,
            'queriesBlocked': 5,
            'queriesAllowed': 7,
            'upstreamFailureCount': 2,
            'fallbackQueryCount': 2,
            'blockedCategoryCount': 3,
            'blockedDomainCount': 42,
            'startedAtEpochMs': 1708147200000,
            'lastRuleUpdateEpochMs': 1708147205000,
            'upstreamDns': 'abc123.dns.nextdns.io',
          };
        }
        return null;
      });

      final status = await service.getStatus();
      expect(status.supported, isTrue);
      expect(status.permissionGranted, isTrue);
      expect(status.isRunning, isTrue);
      expect(status.queriesProcessed, 12);
      expect(status.queriesBlocked, 5);
      expect(status.queriesAllowed, 7);
      expect(status.upstreamFailureCount, 2);
      expect(status.fallbackQueryCount, 2);
      expect(status.blockedCategoryCount, 3);
      expect(status.blockedDomainCount, 42);
      expect(status.startedAt, isNotNull);
      expect(status.lastRuleUpdateAt, isNotNull);
      expect(status.upstreamDns, 'abc123.dns.nextdns.io');
    });

    test('permission/start/stop lifecycle methods map bool responses',
        () async {
      Map<dynamic, dynamic>? startArguments;
      Map<dynamic, dynamic>? restartArguments;
      Map<dynamic, dynamic>? updateArguments;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasVpnPermission') {
          return true;
        }
        if (call.method == 'requestVpnPermission') {
          return true;
        }
        if (call.method == 'startVpn') {
          startArguments = call.arguments as Map<dynamic, dynamic>?;
          return true;
        }
        if (call.method == 'restartVpn') {
          restartArguments = call.arguments as Map<dynamic, dynamic>?;
          return true;
        }
        if (call.method == 'isVpnRunning') {
          return true;
        }
        if (call.method == 'stopVpn') {
          return true;
        }
        if (call.method == 'updateFilterRules') {
          updateArguments = call.arguments as Map<dynamic, dynamic>?;
          return true;
        }
        if (call.method == 'setUpstreamDns') {
          return true;
        }
        if (call.method == 'isIgnoringBatteryOptimizations') {
          return true;
        }
        if (call.method == 'openBatteryOptimizationSettings') {
          return true;
        }
        if (call.method == 'openVpnSettings') {
          return true;
        }
        if (call.method == 'openPrivateDnsSettings') {
          return true;
        }
        if (call.method == 'getRecentDnsQueries') {
          return [
            {
              'domain': 'reddit.com',
              'blocked': true,
              'timestampEpochMs': 1708147210000,
            },
          ];
        }
        if (call.method == 'clearDnsQueryLogs') {
          return true;
        }
        if (call.method == 'getRuleCacheSnapshot') {
          return {
            'categoryCount': 4,
            'domainCount': 120,
            'lastUpdatedAtEpochMs': 1708147220000,
            'sampleCategories': ['adult-content', 'social-networks'],
            'sampleDomains': ['facebook.com', 'instagram.com'],
          };
        }
        if (call.method == 'clearRuleCache') {
          return true;
        }
        if (call.method == 'evaluateDomainPolicy') {
          return {
            'inputDomain': 'm.facebook.com',
            'normalizedDomain': 'm.facebook.com',
            'blocked': true,
            'matchedRule': 'facebook.com',
          };
        }
        return null;
      });

      expect(await service.hasVpnPermission(), isTrue);
      expect(await service.requestPermission(), isTrue);
      expect(
        await service.startVpn(
          blockedCategories: const ['social-networks'],
          blockedDomains: const ['facebook.com'],
          upstreamDns: 'abc123.dns.nextdns.io',
        ),
        isTrue,
      );
      expect(
        await service.restartVpn(
          blockedCategories: const ['social-networks'],
          blockedDomains: const ['facebook.com'],
          upstreamDns: 'abc123.dns.nextdns.io',
        ),
        isTrue,
      );
      expect(await service.isVpnRunning(), isTrue);
      expect(
        await service.updateFilterRules(
          blockedCategories: const ['adult-content'],
          blockedDomains: const ['example.com'],
          temporaryAllowedDomains: const ['instagram.com'],
        ),
        isTrue,
      );
      expect(
        await service.setUpstreamDns(
          upstreamDns: 'abc123.dns.nextdns.io',
        ),
        isTrue,
      );
      expect(await service.isIgnoringBatteryOptimizations(), isTrue);
      expect(await service.openBatteryOptimizationSettings(), isTrue);
      expect(await service.openVpnSettings(), isTrue);
      expect(await service.openPrivateDnsSettings(), isTrue);
      final queryLogs = await service.getRecentDnsQueries(limit: 10);
      expect(queryLogs, hasLength(1));
      expect(queryLogs.first.domain, 'reddit.com');
      expect(queryLogs.first.blocked, isTrue);
      expect(await service.clearDnsQueryLogs(), isTrue);
      final cache = await service.getRuleCacheSnapshot(sampleLimit: 2);
      expect(cache.categoryCount, 4);
      expect(cache.domainCount, 120);
      expect(cache.sampleCategories, isNotEmpty);
      expect(cache.sampleDomains, isNotEmpty);
      expect(await service.clearRuleCache(), isTrue);
      final evaluation = await service.evaluateDomainPolicy('m.facebook.com');
      expect(evaluation.blocked, isTrue);
      expect(evaluation.matchedRule, 'facebook.com');
      expect(await service.stopVpn(), isTrue);
      expect(startArguments?['upstreamDns'], 'abc123.dns.nextdns.io');
      expect(restartArguments?['upstreamDns'], 'abc123.dns.nextdns.io');
      expect(
        updateArguments?['temporaryAllowedDomains'],
        const ['instagram.com'],
      );
    });
  });
}
