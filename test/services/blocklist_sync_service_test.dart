import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trustbridge_app/config/blocklist_sources.dart';
import 'package:trustbridge_app/models/blocklist_source.dart';
import 'package:trustbridge_app/services/blocklist_db_service.dart';
import 'package:trustbridge_app/services/blocklist_sync_service.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  group('BlocklistSyncService', () {
    late _MockHttpClient mockClient;
    late FakeFirebaseFirestore fakeFirestore;
    late BlocklistDbService dbService;
    late DateTime now;
    late BlocklistSyncService service;
    late BlocklistSource socialSource;
    late BlocklistSource malwareSource;

    setUp(() async {
      mockClient = _MockHttpClient();
      fakeFirestore = FakeFirebaseFirestore();
      now = DateTime(2026, 3, 1, 10, 0, 0);

      await BlocklistDbService.configureForTesting(
        databasePath: inMemoryDatabasePath,
      );
      dbService = BlocklistDbService();
      await dbService.init();

      socialSource = BlocklistSources.forCategory(BlocklistCategory.social)!;
      malwareSource = BlocklistSources.forCategory(BlocklistCategory.malware)!;

      service = BlocklistSyncService(
        httpClient: mockClient,
        dbService: dbService,
        firestore: fakeFirestore,
        parentIdResolver: () => 'parent-test',
        nowProvider: () => now,
      );
    });

    tearDown(() async {
      await dbService.close();
    });

    test('HTTP 200 with valid hosts syncs and blocks domain', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(
          '0.0.0.0 instagram.com\n0.0.0.0 tiktok.com',
          200,
        ),
      );

      final result = await service.syncSource(
        socialSource,
        forceRefresh: true,
      );

      expect(result.success, isTrue);
      expect(result.domainsLoaded, 2);
      expect(await dbService.isDomainBlocked('instagram.com'), isTrue);
      expect(await dbService.isDomainBlocked('tiktok.com'), isTrue);
    });

    test('HTTP 404 preserves existing data and returns failure', () async {
      await dbService.insertDomains(
        const <String>['instagram.com'],
        BlocklistCategory.social,
        socialSource.id,
      );

      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('not found', 404),
      );

      final result = await service.syncSource(
        socialSource,
        forceRefresh: true,
      );

      expect(result.success, isFalse);
      expect(await dbService.isDomainBlocked('instagram.com'), isTrue);
    });

    test('timeout preserves existing data and returns failure', () async {
      await dbService.insertDomains(
        const <String>['instagram.com'],
        BlocklistCategory.social,
        socialSource.id,
      );

      when(() => mockClient.get(any())).thenThrow(
        TimeoutException('timeout'),
      );

      final result = await service.syncSource(
        socialSource,
        forceRefresh: true,
      );

      expect(result.success, isFalse);
      expect(
        result.errorMessage,
        contains('timed out'),
      );
      expect(await dbService.isDomainBlocked('instagram.com'), isTrue);
    });

    test('recent sync skips HTTP call without forceRefresh', () async {
      await dbService.insertDomains(
        const <String>['instagram.com'],
        BlocklistCategory.social,
        socialSource.id,
      );
      await dbService.updateMeta(
        socialSource.id,
        1,
        syncedAt: now.subtract(const Duration(days: 1)),
      );

      final result = await service.syncSource(socialSource);

      expect(result.success, isTrue);
      verifyNever(() => mockClient.get(any()));
    });

    test('forceRefresh true calls HTTP even when recently synced', () async {
      await dbService.insertDomains(
        const <String>['instagram.com'],
        BlocklistCategory.social,
        socialSource.id,
      );
      await dbService.updateMeta(
        socialSource.id,
        1,
        syncedAt: now.subtract(const Duration(days: 1)),
      );
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('0.0.0.0 instagram.com', 200),
      );

      final result = await service.syncSource(
        socialSource,
        forceRefresh: true,
      );

      expect(result.success, isTrue);
      verify(() => mockClient.get(any())).called(1);
    });

    test('onCategoryDisabled clears only matching source', () async {
      await dbService.insertDomains(
        const <String>['instagram.com'],
        BlocklistCategory.social,
        socialSource.id,
      );
      await dbService.insertDomains(
        const <String>['malware.test'],
        BlocklistCategory.malware,
        malwareSource.id,
      );

      await service.onCategoryDisabled(BlocklistCategory.social);

      expect(await dbService.isDomainBlocked('instagram.com'), isFalse);
      expect(await dbService.isDomainBlocked('malware.test'), isTrue);
    });

    test('syncAll for two categories makes two HTTP calls', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('0.0.0.0 sample.test', 200),
      );

      final results = await service.syncAll(
        const <BlocklistCategory>[
          BlocklistCategory.social,
          BlocklistCategory.malware,
        ],
        forceRefresh: true,
      );

      expect(results.length, 2);
      verify(() => mockClient.get(any())).called(2);
    });

    test('getStatus marks stale when last synced is older than 14 days',
        () async {
      await dbService.insertDomains(
        const <String>['instagram.com'],
        BlocklistCategory.social,
        socialSource.id,
      );
      await dbService.updateMeta(
        socialSource.id,
        1,
        syncedAt: now.subtract(const Duration(days: 20)),
      );

      final statuses = await service.getStatus();
      final socialStatus = statuses.firstWhere(
        (status) => status.source.id == socialSource.id,
      );

      expect(socialStatus.isStale, isTrue);
    });

    test('getStatus marks fresh when last synced is within 14 days', () async {
      await dbService.insertDomains(
        const <String>['instagram.com'],
        BlocklistCategory.social,
        socialSource.id,
      );
      await dbService.updateMeta(
        socialSource.id,
        1,
        syncedAt: now.subtract(const Duration(days: 3)),
      );

      final statuses = await service.getStatus();
      final socialStatus = statuses.firstWhere(
        (status) => status.source.id == socialSource.id,
      );

      expect(socialStatus.isStale, isFalse);
    });
  });
}
