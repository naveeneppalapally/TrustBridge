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

    test('requestPermission/start/stop map bool responses', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestPermission') {
          return true;
        }
        if (call.method == 'startVpn') {
          return true;
        }
        if (call.method == 'stopVpn') {
          return true;
        }
        return null;
      });

      expect(await service.requestPermission(), isTrue);
      expect(await service.startVpn(), isTrue);
      expect(await service.stopVpn(), isTrue);
    });
  });
}
