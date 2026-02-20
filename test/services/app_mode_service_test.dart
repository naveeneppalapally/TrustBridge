import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/app_mode.dart';
import 'package:trustbridge_app/services/app_mode_service.dart';

void main() {
  group('AppModeService', () {
    late AppModeService service;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      service = AppModeService(
        secureStorage: const FlutterSecureStorage(),
      );
    });

    test('getMode returns unset when nothing stored', () async {
      final mode = await service.getMode();
      expect(mode, AppMode.unset);
    });

    test('setMode(parent) then getMode returns parent', () async {
      await service.setMode(AppMode.parent);
      final mode = await service.getMode();
      expect(mode, AppMode.parent);
    });

    test('setMode(child) then getMode returns child', () async {
      await service.setMode(AppMode.child);
      final mode = await service.getMode();
      expect(mode, AppMode.child);
    });

    test('clearMode resets to unset', () async {
      await service.setMode(AppMode.parent);
      await service.clearMode();
      final mode = await service.getMode();
      expect(mode, AppMode.unset);
    });
  });
}
