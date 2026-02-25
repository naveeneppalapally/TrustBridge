import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/device_admin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.navee.trustbridge/device_admin');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isDeviceAdminActive returns false when platform reports false',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'isDeviceAdminActive') {
        return false;
      }
      return null;
    });

    final service = DeviceAdminService(channel: channel);
    final result = await service.isDeviceAdminActive();
    expect(result, isFalse);
  });

  test('isDeviceAdminActive returns true when platform reports true', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'isDeviceAdminActive') {
        return true;
      }
      return null;
    });

    final service = DeviceAdminService(channel: channel);
    final result = await service.isDeviceAdminActive();
    expect(result, isTrue);
  });
}
