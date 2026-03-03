import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/app_mode.dart';
import 'package:trustbridge_app/services/app_mode_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';

void main() {
  group('PairingService', () {
    late FakeFirebaseFirestore firestore;
    late FlutterSecureStorage storage;
    late AppModeService appModeService;
    late PairingService service;

    const parentId = 'parent-uid-1';
    const childId = 'child-uid-1';
    final now = DateTime(2026, 2, 20, 10, 0, 0);

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      firestore = FakeFirebaseFirestore();
      storage = const FlutterSecureStorage();
      appModeService = AppModeService(secureStorage: storage);
      service = PairingService(
        firestore: firestore,
        secureStorage: storage,
        appModeService: appModeService,
        currentUserIdResolver: () => parentId,
        fcmTokenProvider: () async => 'fcm-token-test',
        nowProvider: () => now,
      );

      await firestore.collection('children').doc(childId).set({
        'id': childId,
        'parentId': parentId,
        'nickname': 'Test Child',
        'ageBand': '10-13',
        'policy': {
          'blockedCategories': <String>[],
          'blockedDomains': <String>[],
          'schedules': <Map<String, dynamic>>[],
          'safeSearchEnabled': true,
        },
        'deviceIds': <String>[],
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });

    test('generatePairingCode writes Firestore doc and returns secure code',
        () async {
      final code = await service.generatePairingCode(childId);

      expect(code, matches(r'^[2-9A-HJ-NP-Z]{8}$'));
      final doc = await firestore.collection('pairing_codes').doc(code).get();
      expect(doc.exists, true);
      expect(doc.data()!['childId'], childId);
      expect(doc.data()!['parentId'], parentId);
      expect(doc.data()!['used'], false);
      expect(doc.data()!['lookupAttempts'], 0);
      expect(doc.data()!['firstAttemptAt'], isNull);
    });

    test('validateAndPair success marks used and switches mode to child',
        () async {
      await firestore.collection('pairing_codes').doc('ABCD2345').set({
        'code': 'ABCD2345',
        'childId': childId,
        'parentId': parentId,
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(minutes: 15))),
        'used': false,
        'lookupAttempts': 0,
        'firstAttemptAt': null,
        'lookupDeviceId': null,
      });

      final result = await service.validateAndPair('ABCD2345', 'device-1');

      expect(result.success, true);
      expect(result.childId, childId);
      expect(result.parentId, parentId);

      final codeDoc =
          await firestore.collection('pairing_codes').doc('ABCD2345').get();
      expect(codeDoc.data()!['used'], true);

      final childDoc =
          await firestore.collection('children').doc(childId).get();
      final deviceIds = (childDoc.data()!['deviceIds'] as List).cast<String>();
      expect(deviceIds.contains('device-1'), true);

      final deviceDoc = await firestore
          .collection('children')
          .doc(childId)
          .collection('devices')
          .doc('device-1')
          .get();
      expect(deviceDoc.exists, true);
      expect(deviceDoc.data()!['fcmToken'], 'fcm-token-test');

      expect(await appModeService.getMode(), AppMode.child);
    });

    test('validateAndPair returns expiredCode for expired code', () async {
      await firestore.collection('pairing_codes').doc('BCDE2346').set({
        'code': 'BCDE2346',
        'childId': childId,
        'parentId': parentId,
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
        'expiresAt':
            Timestamp.fromDate(now.subtract(const Duration(minutes: 1))),
        'used': false,
        'lookupAttempts': 0,
        'firstAttemptAt': null,
        'lookupDeviceId': null,
      });

      final result = await service.validateAndPair('BCDE2346', 'device-1');
      expect(result.success, false);
      expect(result.error, PairingError.expiredCode);

      final codeDoc =
          await firestore.collection('pairing_codes').doc('BCDE2346').get();
      expect(codeDoc.data()!['lookupAttempts'], 1);
    });

    test('validateAndPair returns alreadyUsed for used code', () async {
      await firestore.collection('pairing_codes').doc('CDEF2347').set({
        'code': 'CDEF2347',
        'childId': childId,
        'parentId': parentId,
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(minutes: 5))),
        'used': true,
        'lookupAttempts': 0,
        'firstAttemptAt': null,
        'lookupDeviceId': null,
      });

      final result = await service.validateAndPair('CDEF2347', 'device-1');
      expect(result.success, false);
      expect(result.error, PairingError.alreadyUsed);
    });

    test('validateAndPair returns invalidCode for unknown code', () async {
      final result = await service.validateAndPair('ZZZZ9999', 'device-1');
      expect(result.success, false);
      expect(result.error, PairingError.invalidCode);
    });

    test('generated pairing code uses secure alphabet and length 8', () async {
      for (var index = 0; index < 20; index++) {
        final loopChildId = 'child-$index';
        await firestore.collection('children').doc(loopChildId).set({
          'id': loopChildId,
          'parentId': parentId,
          'nickname': 'Child $index',
          'ageBand': '10-13',
          'policy': {
            'blockedCategories': <String>[],
            'blockedDomains': <String>[],
            'schedules': <Map<String, dynamic>>[],
            'safeSearchEnabled': true,
          },
          'deviceIds': <String>[],
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
        final code = await service.generatePairingCode(loopChildId);
        expect(code.length, PairingService.pairingCodeLength);
        expect(RegExp(r'^[2-9A-HJ-NP-Z]{8}$').hasMatch(code), true);
      }
    });

    test('validateAndPair throttles after 5 failed lookups in 10 minutes',
        () async {
      await firestore.collection('pairing_codes').doc('DEFG2348').set({
        'code': 'DEFG2348',
        'childId': childId,
        'parentId': parentId,
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(minutes: 5))),
        'used': true,
        'lookupAttempts': 0,
        'firstAttemptAt': null,
        'lookupDeviceId': null,
      });

      for (var attempt = 0; attempt < 5; attempt++) {
        final result = await service.validateAndPair('DEFG2348', 'device-1');
        expect(result.success, false);
        expect(result.error, PairingError.alreadyUsed);
      }

      final throttled = await service.validateAndPair('DEFG2348', 'device-1');
      expect(throttled.success, false);
      expect(throttled.error, PairingError.tooManyAttempts);

      final codeDoc =
          await firestore.collection('pairing_codes').doc('DEFG2348').get();
      expect(codeDoc.data()!['lookupAttempts'], 5);
    });

    test('recoverPairingFromCloud ignores orphaned child devices subcollection',
        () async {
      const deviceId = 'orphan-device-1';
      await storage.write(key: 'pairing_device_id', value: deviceId);
      await firestore
          .collection('children')
          .doc('deleted-child')
          .collection('devices')
          .doc(deviceId)
          .set(<String, dynamic>{
        'parentId': parentId,
        'pairedAt': Timestamp.fromDate(now),
      });

      final recovered = await service.recoverPairingFromCloud();

      expect(recovered, isNull);
      expect(await service.getPairedChildId(), isNull);
      expect(await service.getPairedParentId(), isNull);
    });
  });
}
