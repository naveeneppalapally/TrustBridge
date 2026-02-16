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
          };
        }
        return null;
      });

      final status = await service.getStatus();
      expect(status.supported, isTrue);
      expect(status.permissionGranted, isTrue);
      expect(status.isRunning, isTrue);
    });

    test('permission/start/stop lifecycle methods map bool responses',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasVpnPermission') {
          return true;
        }
        if (call.method == 'requestVpnPermission') {
          return true;
        }
        if (call.method == 'startVpn') {
          return true;
        }
        if (call.method == 'isVpnRunning') {
          return true;
        }
        if (call.method == 'stopVpn') {
          return true;
        }
        if (call.method == 'updateFilterRules') {
          return true;
        }
        return null;
      });

      expect(await service.hasVpnPermission(), isTrue);
      expect(await service.requestPermission(), isTrue);
      expect(
        await service.startVpn(
          blockedCategories: const ['social-networks'],
          blockedDomains: const ['facebook.com'],
        ),
        isTrue,
      );
      expect(await service.isVpnRunning(), isTrue);
      expect(
        await service.updateFilterRules(
          blockedCategories: const ['adult-content'],
          blockedDomains: const ['example.com'],
        ),
        isTrue,
      );
      expect(await service.stopVpn(), isTrue);
    });
  });
}
