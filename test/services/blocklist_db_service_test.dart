import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trustbridge_app/models/blocklist_source.dart';
import 'package:trustbridge_app/services/blocklist_db_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('BlocklistDbService', () {
    late BlocklistDbService service;

    setUp(() async {
      await BlocklistDbService.configureForTesting(
        databasePath: inMemoryDatabasePath,
      );
      service = BlocklistDbService();
      await service.init();
    });

    tearDown(() async {
      await service.close();
    });

    test('insert + isDomainBlocked', () async {
      await service.insertDomains(
        const <String>['instagram.com', 'tiktok.com'],
        BlocklistCategory.social,
        'source_social',
      );

      expect(await service.isDomainBlocked('instagram.com'), isTrue);
      expect(await service.isDomainBlocked('tiktok.com'), isTrue);
    });

    test('isDomainBlocked false on empty database', () async {
      expect(await service.isDomainBlocked('google.com'), isFalse);
    });

    test('getCategory returns inserted category', () async {
      await service.insertDomains(
        const <String>['instagram.com'],
        BlocklistCategory.social,
        'source_social',
      );

      expect(
        await service.getCategory('instagram.com'),
        equals(BlocklistCategory.social),
      );
    });

    test('clearBySource does not affect other sources', () async {
      await service.insertDomains(
        const <String>['instagram.com', 'tiktok.com'],
        BlocklistCategory.social,
        'source_social',
      );
      await service.insertDomains(
        const <String>['malware.test'],
        BlocklistCategory.malware,
        'source_malware',
      );

      await service.clearBySource('source_social');

      expect(await service.isDomainBlocked('instagram.com'), isFalse);
      expect(await service.isDomainBlocked('tiktok.com'), isFalse);
      expect(await service.isDomainBlocked('malware.test'), isTrue);
    });

    test('domainCount returns total rows', () async {
      await service.insertDomains(
        const <String>['a.com', 'b.com', 'c.com'],
        BlocklistCategory.ads,
        'source_ads',
      );

      expect(await service.domainCount(), equals(3));
    });

    test('domainCountForSource returns source-specific count', () async {
      await service.insertDomains(
        const <String>['a.com', 'b.com'],
        BlocklistCategory.ads,
        'A',
      );
      await service.insertDomains(
        const <String>['x.com', 'y.com', 'z.com'],
        BlocklistCategory.social,
        'B',
      );

      expect(await service.domainCountForSource('A'), equals(2));
      expect(await service.domainCountForSource('B'), equals(3));
    });

    test('updateMeta + getLastSynced roundtrip', () async {
      await service.updateMeta('source_social', 2);
      final syncedAt = await service.getLastSynced('source_social');

      expect(syncedAt, isNotNull);
      expect(
        DateTime.now().difference(syncedAt!).inSeconds.abs(),
        lessThanOrEqualTo(5),
      );
    });

    test('batch insert is idempotent for same source/domains', () async {
      const domains = <String>['instagram.com', 'tiktok.com'];
      await service.insertDomains(
        domains,
        BlocklistCategory.social,
        'source_social',
      );
      await service.insertDomains(
        domains,
        BlocklistCategory.social,
        'source_social',
      );

      expect(await service.domainCount(), equals(2));
      expect(await service.domainCountForSource('source_social'), equals(2));
    });
  });
}
