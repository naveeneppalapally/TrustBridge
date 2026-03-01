import 'dart:async';
import 'dart:collection';
import 'package:trustbridge_app/core/utils/app_logger.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/blocklist_sources.dart';
import '../models/blocklist_source.dart';
import 'blocklist_db_service.dart';
import 'blocklist_parser.dart';

/// Result payload for a single blocklist sync attempt.
class BlocklistSyncResult {
  /// Creates a blocklist sync result.
  const BlocklistSyncResult({
    required this.sourceId,
    required this.success,
    required this.domainsLoaded,
    required this.syncedAt,
    this.errorMessage,
  });

  /// Source identifier that was synced.
  final String sourceId;

  /// Whether the sync attempt succeeded.
  final bool success;

  /// Number of domains loaded for successful sync attempts.
  final int domainsLoaded;

  /// Optional error message when [success] is false.
  final String? errorMessage;

  /// Attempt timestamp.
  final DateTime syncedAt;
}

/// Status payload used by UI to display blocklist sync health.
class BlocklistSyncStatus {
  /// Creates a blocklist sync status.
  const BlocklistSyncStatus({
    required this.source,
    required this.lastSynced,
    required this.domainCount,
    required this.isStale,
  });

  /// Blocklist source metadata.
  final BlocklistSource source;

  /// Last successful sync timestamp.
  final DateTime? lastSynced;

  /// Number of domains currently stored for this source.
  final int domainCount;

  /// True when status should be highlighted as stale.
  final bool isStale;
}

/// Background-safe service for syncing open-source blocklists into SQLite.
class BlocklistSyncService {
  BlocklistSyncService._internal({
    http.Client? httpClient,
    BlocklistDbService? dbService,
    FirebaseFirestore? firestore,
    String? Function()? parentIdResolver,
    DateTime Function()? nowProvider,
    bool enableRemoteLogging = true,
  })  : _httpClient = httpClient ?? http.Client(),
        _dbService = dbService ?? BlocklistDbService(),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _parentIdResolver = parentIdResolver,
        _nowProvider = nowProvider ?? DateTime.now,
        _enableRemoteLogging = enableRemoteLogging;

  static const Duration _staleAfter = Duration(days: 14);
  static const Duration _minimumRefreshGap = Duration(days: 1);
  static const Duration _requestTimeout = Duration(seconds: 30);

  static BlocklistSyncService _instance = BlocklistSyncService._internal();

  final http.Client _httpClient;
  final BlocklistDbService _dbService;
  final FirebaseFirestore _firestore;
  final String? Function()? _parentIdResolver;
  final DateTime Function() _nowProvider;
  final bool _enableRemoteLogging;

  /// Returns singleton service with default dependencies.
  factory BlocklistSyncService({
    http.Client? httpClient,
    BlocklistDbService? dbService,
    FirebaseFirestore? firestore,
    String? Function()? parentIdResolver,
    DateTime Function()? nowProvider,
    bool enableRemoteLogging = true,
  }) {
    if (httpClient == null &&
        dbService == null &&
        firestore == null &&
        parentIdResolver == null &&
        nowProvider == null &&
        enableRemoteLogging) {
      return _instance;
    }

    return BlocklistSyncService._internal(
      httpClient: httpClient,
      dbService: dbService,
      firestore: firestore,
      parentIdResolver: parentIdResolver,
      nowProvider: nowProvider,
      enableRemoteLogging: enableRemoteLogging,
    );
  }

  /// Resets singleton for tests with custom dependencies.
  static Future<void> configureForTesting({
    required http.Client httpClient,
    required BlocklistDbService dbService,
    required FirebaseFirestore firestore,
    String? Function()? parentIdResolver,
    DateTime Function()? nowProvider,
    bool enableRemoteLogging = false,
  }) async {
    _instance = BlocklistSyncService._internal(
      httpClient: httpClient,
      dbService: dbService,
      firestore: firestore,
      parentIdResolver: parentIdResolver,
      nowProvider: nowProvider,
      enableRemoteLogging: enableRemoteLogging,
    );
  }

  /// Downloads and syncs a single source into local SQLite.
  ///
  /// Safety rule: existing data is never cleared on HTTP failures.
  Future<BlocklistSyncResult> syncSource(
    BlocklistSource source, {
    bool forceRefresh = false,
  }) async {
    await _dbService.init();
    final now = _nowProvider();

    final lastSynced = await _dbService.getLastSynced(source.id);
    if (!forceRefresh &&
        lastSynced != null &&
        now.difference(lastSynced) < _minimumRefreshGap) {
      final loadedCount = await _readDisplayDomainCount(source.id);
      final skippedResult = BlocklistSyncResult(
        sourceId: source.id,
        success: true,
        domainsLoaded: loadedCount,
        syncedAt: now,
      );
      await _safeLogResult(source, skippedResult, forceRefresh: forceRefresh);
      return skippedResult;
    }

    BlocklistSyncResult result;
    try {
      final uri = Uri.parse(source.url);
      final response = await _httpClient.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        result = BlocklistSyncResult(
          sourceId: source.id,
          success: false,
          domainsLoaded: 0,
          errorMessage: 'HTTP ${response.statusCode}',
          syncedAt: now,
        );
        await _safeLogResult(source, result, forceRefresh: forceRefresh);
        return result;
      }

      final domains = BlocklistParser.parse(response.body);

      // Only clear/replace after a successful download+parse.
      await _dbService.clearBySource(source.id);
      await _dbService.insertDomains(domains, source.category, source.id);
      await _dbService.updateMeta(
        source.id,
        domains.length,
        syncedAt: now,
      );

      result = BlocklistSyncResult(
        sourceId: source.id,
        success: true,
        domainsLoaded: domains.length,
        syncedAt: now,
      );
      await _safeLogResult(source, result, forceRefresh: forceRefresh);
      return result;
    } on TimeoutException {
      result = BlocklistSyncResult(
        sourceId: source.id,
        success: false,
        domainsLoaded: 0,
        errorMessage: 'Request timed out after ${_requestTimeout.inSeconds}s',
        syncedAt: now,
      );
      await _safeLogResult(source, result, forceRefresh: forceRefresh);
      return result;
    } catch (error) {
      result = BlocklistSyncResult(
        sourceId: source.id,
        success: false,
        domainsLoaded: 0,
        errorMessage: error.toString(),
        syncedAt: now,
      );
      await _safeLogResult(source, result, forceRefresh: forceRefresh);
      return result;
    }
  }

  /// Syncs all provided categories and returns individual source results.
  Future<List<BlocklistSyncResult>> syncAll(
    List<BlocklistCategory> categories, {
    bool forceRefresh = false,
  }) async {
    final orderedUnique = LinkedHashSet<BlocklistCategory>.from(categories);
    final results = <BlocklistSyncResult>[];

    for (final category in orderedUnique) {
      final source = BlocklistSources.forCategory(category);
      if (source == null) {
        results.add(
          BlocklistSyncResult(
            sourceId: category.name,
            success: false,
            domainsLoaded: 0,
            errorMessage: 'No source configured for category ${category.name}',
            syncedAt: _nowProvider(),
          ),
        );
        continue;
      }

      results.add(
        await syncSource(source, forceRefresh: forceRefresh),
      );
    }

    return results;
  }

  /// Returns sync status for all known blocklist sources.
  Future<List<BlocklistSyncStatus>> getStatus() async {
    await _dbService.init();
    final now = _nowProvider();
    final statuses = <BlocklistSyncStatus>[];

    for (final source in BlocklistSources.all) {
      final lastSynced = await _dbService.getLastSynced(source.id);
      final count = await _readDisplayDomainCount(source.id);
      final isStale =
          lastSynced == null || now.difference(lastSynced) > _staleAfter;

      statuses.add(
        BlocklistSyncStatus(
          source: source.copyWith(
            lastSynced: lastSynced,
            domainCount: count,
          ),
          lastSynced: lastSynced,
          domainCount: count,
          isStale: isStale,
        ),
      );
    }

    return statuses;
  }

  Future<int> _readDisplayDomainCount(String sourceId) async {
    final fromMeta = await _dbService.getMetaDomainCount(sourceId);
    if (fromMeta != null) {
      return fromMeta;
    }
    return _dbService.domainCountForSource(sourceId);
  }

  /// Clears local domains for a disabled category source.
  Future<void> onCategoryDisabled(BlocklistCategory category) async {
    final source = BlocklistSources.forCategory(category);
    if (source == null) {
      return;
    }
    await _dbService.init();
    await _dbService.clearBySource(source.id);
  }

  Future<void> _safeLogResult(
    BlocklistSource source,
    BlocklistSyncResult result, {
    required bool forceRefresh,
  }) async {
    if (!_enableRemoteLogging) {
      return;
    }

    final parentId = _resolveParentId();
    if (parentId == null || parentId.trim().isEmpty) {
      return;
    }

    try {
      final timestampKey = result.syncedAt.millisecondsSinceEpoch.toString();
      await _firestore
          .collection('sync_logs')
          .doc(parentId)
          .collection('blocklist_syncs')
          .doc(timestampKey)
          .set(<String, dynamic>{
        'sourceId': source.id,
        'category': source.category.name,
        'success': result.success,
        'domainsLoaded': result.domainsLoaded,
        'errorMessage': result.errorMessage,
        'forceRefresh': forceRefresh,
        'syncedAt': Timestamp.fromDate(result.syncedAt),
      });
    } catch (error) {
      AppLogger.debug('[BlocklistSync] Failed to write sync log: $error');
    }
  }

  String? _resolveParentId() {
    final overrideParentId = _parentIdResolver?.call();
    if (overrideParentId != null && overrideParentId.trim().isNotEmpty) {
      return overrideParentId.trim();
    }
    return FirebaseAuth.instance.currentUser?.uid;
  }
}
