import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/blocklist_source.dart';

/// Local SQLite persistence for open-source blocklist domains.
///
/// This service is optimized for fast domain membership checks during DNS
/// resolution and for large bulk inserts during blocklist updates.
class BlocklistDbService {
  BlocklistDbService._({
    String? databasePathOverride,
  }) : _databasePathOverride = databasePathOverride;

  static const String _databaseName = 'trustbridge_blocklist.db';
  static const int _databaseVersion = 1;
  static const int _insertChunkSize = 500;

  static BlocklistDbService _instance = BlocklistDbService._();

  Database? _db;
  final String? _databasePathOverride;

  /// Returns the singleton instance.
  factory BlocklistDbService() => _instance;

  /// Overrides the singleton with a test-specific database path.
  ///
  /// Intended for tests only.
  static Future<void> configureForTesting({
    required String databasePath,
  }) async {
    await _instance.close();
    _instance = BlocklistDbService._(databasePathOverride: databasePath);
  }

  /// Closes the current database if open.
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) {
      await db.close();
    }
  }

  /// Initializes and opens the blocklist database.
  Future<void> init() async {
    try {
      await _openIfNeeded();
    } catch (error) {
      throw StateError('Failed to initialize blocklist database: $error');
    }
  }

  /// Inserts a batch of domains for a source/category.
  ///
  /// Existing domains from the same source are replaced in the same
  /// transaction. Domains are inserted in chunks for memory safety.
  Future<void> insertDomains(
    List<String> domains,
    BlocklistCategory category,
    String sourceId,
  ) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Source ID is required.',
      );
    }

    final normalizedDomains = domains
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    try {
      final db = await _openIfNeeded();
      await db.transaction((txn) async {
        await txn.delete(
          'blocked_domains',
          where: 'source_id = ?',
          whereArgs: <Object>[normalizedSourceId],
        );

        for (var start = 0;
            start < normalizedDomains.length;
            start += _insertChunkSize) {
          final end =
              math.min(start + _insertChunkSize, normalizedDomains.length);
          final batch = txn.batch();
          for (var i = start; i < end; i++) {
            batch.insert(
              'blocked_domains',
              <String, Object>{
                'domain': normalizedDomains[i],
                'category': category.name,
                'source_id': normalizedSourceId,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true, continueOnError: false);
        }
      });
    } catch (error) {
      throw StateError(
        'Failed to insert domains for source "$normalizedSourceId": $error',
      );
    }
  }

  /// Returns true when a domain exists in the blocked domain table.
  Future<bool> isDomainBlocked(String domain) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    try {
      final db = await _openIfNeeded();
      final rows = await db.query(
        'blocked_domains',
        columns: const <String>['domain'],
        where: 'domain = ?',
        whereArgs: <Object>[normalized],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (error) {
      throw StateError('Failed domain lookup for "$normalized": $error');
    }
  }

  /// Returns the category for a blocked domain, or null when not blocked.
  Future<BlocklistCategory?> getCategory(String domain) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    try {
      final db = await _openIfNeeded();
      final rows = await db.query(
        'blocked_domains',
        columns: const <String>['category'],
        where: 'domain = ?',
        whereArgs: <Object>[normalized],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final rawCategory = rows.first['category']?.toString().trim() ?? '';
      for (final value in BlocklistCategory.values) {
        if (value.name == rawCategory) {
          return value;
        }
      }
      return null;
    } catch (error) {
      throw StateError('Failed category lookup for "$normalized": $error');
    }
  }

  /// Clears all blocked domains originating from a source.
  Future<void> clearBySource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Source ID is required.',
      );
    }

    try {
      final db = await _openIfNeeded();
      await db.delete(
        'blocked_domains',
        where: 'source_id = ?',
        whereArgs: <Object>[normalizedSourceId],
      );
    } catch (error) {
      throw StateError(
        'Failed clearing source "$normalizedSourceId": $error',
      );
    }
  }

  /// Returns total blocked domain count across all sources.
  Future<int> domainCount() async {
    try {
      final db = await _openIfNeeded();
      return Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) AS count FROM blocked_domains',
            ),
          ) ??
          0;
    } catch (error) {
      throw StateError('Failed counting blocked domains: $error');
    }
  }

  /// Returns blocked domain count for a source.
  Future<int> domainCountForSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Source ID is required.',
      );
    }

    try {
      final db = await _openIfNeeded();
      return Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) AS count FROM blocked_domains WHERE source_id = ?',
              <Object>[normalizedSourceId],
            ),
          ) ??
          0;
    } catch (error) {
      throw StateError(
        'Failed counting domains for source "$normalizedSourceId": $error',
      );
    }
  }

  /// Writes sync metadata for a source.
  Future<void> updateMeta(
    String sourceId,
    int domainCount, {
    DateTime? syncedAt,
  }) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Source ID is required.',
      );
    }
    if (domainCount < 0) {
      throw ArgumentError.value(
        domainCount,
        'domainCount',
        'Domain count must be >= 0.',
      );
    }

    try {
      final db = await _openIfNeeded();
      await db.insert(
        'blocklist_meta',
        <String, Object>{
          'source_id': normalizedSourceId,
          'last_synced': (syncedAt ?? DateTime.now()).millisecondsSinceEpoch,
          'domain_count': domainCount,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (error) {
      throw StateError(
        'Failed updating metadata for source "$normalizedSourceId": $error',
      );
    }
  }

  /// Returns last synced timestamp for a source, or null when unavailable.
  Future<DateTime?> getLastSynced(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Source ID is required.',
      );
    }

    try {
      final db = await _openIfNeeded();
      final rows = await db.query(
        'blocklist_meta',
        columns: const <String>['last_synced'],
        where: 'source_id = ?',
        whereArgs: <Object>[normalizedSourceId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final rawValue = rows.first['last_synced'];
      final millis = rawValue is int
          ? rawValue
          : rawValue is num
              ? rawValue.toInt()
              : null;
      if (millis == null || millis <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (error) {
      throw StateError(
        'Failed reading last synced for source "$normalizedSourceId": $error',
      );
    }
  }

  Future<Database> _openIfNeeded() async {
    if (_db != null) {
      return _db!;
    }

    final path = _databasePathOverride ?? await _resolveDatabasePath();
    _db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE blocked_domains (
  domain TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  source_id TEXT NOT NULL
)
''');
        await db.execute('''
CREATE TABLE blocklist_meta (
  source_id TEXT PRIMARY KEY,
  last_synced INTEGER NOT NULL,
  domain_count INTEGER NOT NULL DEFAULT 0
)
''');
      },
    );
    return _db!;
  }

  Future<String> _resolveDatabasePath() async {
    final basePath = await getDatabasesPath();
    return p.join(basePath, _databaseName);
  }
}
