import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Error wrapper for NextDNS API failures.
class NextDnsApiException implements Exception {
  const NextDnsApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() {
    if (statusCode == null) {
      return 'NextDnsApiException($code): $message';
    }
    return 'NextDnsApiException($code, status=$statusCode): $message';
  }
}

class NextDnsProfileSummary {
  const NextDnsProfileSummary({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  factory NextDnsProfileSummary.fromMap(Map<String, dynamic> map) {
    return NextDnsProfileSummary(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
    );
  }
}

class NextDnsAnalyticsStatus {
  const NextDnsAnalyticsStatus({
    required this.status,
    required this.queries,
  });

  final String status;
  final int queries;

  factory NextDnsAnalyticsStatus.fromMap(Map<String, dynamic> map) {
    return NextDnsAnalyticsStatus(
      status: (map['status'] as String? ?? '').trim(),
      queries: _intOrZero(map['queries']),
    );
  }
}

class NextDnsDomainStat {
  const NextDnsDomainStat({
    required this.domain,
    required this.queries,
  });

  final String domain;
  final int queries;

  factory NextDnsDomainStat.fromMap(Map<String, dynamic> map) {
    return NextDnsDomainStat(
      domain: (map['domain'] as String? ?? '').trim(),
      queries: _intOrZero(map['queries']),
    );
  }
}

/// Secret storage abstraction to keep API key testable.
abstract class NextDnsSecretStore {
  Future<void> saveApiKey(String apiKey);
  Future<String?> readApiKey();
  Future<void> clearApiKey();
}

class SecureNextDnsSecretStore implements NextDnsSecretStore {
  SecureNextDnsSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String apiKeyStorageKey = 'trustbridge_nextdns_api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<void> saveApiKey(String apiKey) {
    return _storage.write(key: apiKeyStorageKey, value: apiKey);
  }

  @override
  Future<String?> readApiKey() {
    return _storage.read(key: apiKeyStorageKey);
  }

  @override
  Future<void> clearApiKey() {
    return _storage.delete(key: apiKeyStorageKey);
  }
}

/// In-memory store used by tests.
class InMemoryNextDnsSecretStore implements NextDnsSecretStore {
  String? _apiKey;

  @override
  Future<void> clearApiKey() async {
    _apiKey = null;
  }

  @override
  Future<String?> readApiKey() async {
    return _apiKey;
  }

  @override
  Future<void> saveApiKey(String apiKey) async {
    _apiKey = apiKey;
  }
}

class NextDnsApiService {
  NextDnsApiService({
    http.Client? httpClient,
    NextDnsSecretStore? secretStore,
    Uri? baseUri,
    Duration timeout = const Duration(seconds: 12),
  })  : _httpClient = httpClient ?? http.Client(),
        _secretStore = secretStore ?? SecureNextDnsSecretStore(),
        _baseUri = baseUri ?? Uri.parse('https://api.nextdns.io'),
        _timeout = timeout;

  final http.Client _httpClient;
  final NextDnsSecretStore _secretStore;
  final Uri _baseUri;
  final Duration _timeout;

  Future<void> setNextDnsApiKey(String apiKey) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw const NextDnsApiException(
        code: 'invalid_api_key',
        message: 'API key cannot be empty.',
      );
    }
    await _secretStore.saveApiKey(normalized);
  }

  Future<String?> getNextDnsApiKey() async {
    final raw = await _secretStore.readApiKey();
    final normalized = raw?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> clearNextDnsApiKey() {
    return _secretStore.clearApiKey();
  }

  Future<bool> validateApiKey({String? apiKey}) async {
    try {
      await fetchProfiles(apiKey: apiKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<NextDnsProfileSummary>> fetchProfiles({String? apiKey}) async {
    final response = await _requestJson(
      method: 'GET',
      pathSegments: const <String>['profiles'],
      apiKey: apiKey,
    );
    final data = response['data'];
    if (data is! List) {
      return const <NextDnsProfileSummary>[];
    }

    return data
        .whereType<Map>()
        .map(
          (item) => NextDnsProfileSummary.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((profile) => profile.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<NextDnsProfileSummary> createProfile({
    required String name,
    String? apiKey,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const NextDnsApiException(
        code: 'invalid_name',
        message: 'Profile name is required.',
      );
    }

    final response = await _requestJson(
      method: 'POST',
      pathSegments: const <String>['profiles'],
      apiKey: apiKey,
      body: <String, dynamic>{'name': normalizedName},
    );

    final data = _asStringKeyedMap(response['data']);
    final profileId = (data['id'] as String? ?? '').trim();
    if (profileId.isEmpty) {
      throw const NextDnsApiException(
        code: 'invalid_response',
        message: 'NextDNS did not return a profile ID.',
      );
    }

    return NextDnsProfileSummary(id: profileId, name: normalizedName);
  }

  Future<void> setServiceBlocked({
    required String profileId,
    required String serviceId,
    required bool blocked,
    String? apiKey,
  }) {
    return _upsertParentalControlArrayItem(
      profileId: profileId,
      endpoint: 'services',
      itemId: serviceId,
      active: blocked,
      apiKey: apiKey,
    );
  }

  Future<void> setCategoryBlocked({
    required String profileId,
    required String categoryId,
    required bool blocked,
    String? apiKey,
  }) {
    return _upsertParentalControlArrayItem(
      profileId: profileId,
      endpoint: 'categories',
      itemId: categoryId,
      active: blocked,
      apiKey: apiKey,
    );
  }

  Future<void> setParentalControlToggles({
    required String profileId,
    String? apiKey,
    bool? safeSearchEnabled,
    bool? youtubeRestrictedModeEnabled,
    bool? blockBypassEnabled,
  }) async {
    final body = <String, dynamic>{};
    if (safeSearchEnabled != null) {
      body['safeSearch'] = safeSearchEnabled;
    }
    if (youtubeRestrictedModeEnabled != null) {
      body['youtubeRestrictedMode'] = youtubeRestrictedModeEnabled;
    }
    if (blockBypassEnabled != null) {
      body['blockBypass'] = blockBypassEnabled;
    }

    if (body.isEmpty) {
      return;
    }

    await _requestJson(
      method: 'PATCH',
      pathSegments: <String>['profiles', profileId, 'parentalControl'],
      apiKey: apiKey,
      body: body,
    );
  }

  Future<void> addToDenylist({
    required String profileId,
    required String domain,
    String? apiKey,
  }) {
    return _upsertDomainList(
      profileId: profileId,
      endpoint: 'denylist',
      domain: domain,
      active: true,
      apiKey: apiKey,
    );
  }

  Future<void> removeFromDenylist({
    required String profileId,
    required String domain,
    String? apiKey,
  }) {
    return _upsertDomainList(
      profileId: profileId,
      endpoint: 'denylist',
      domain: domain,
      active: false,
      apiKey: apiKey,
    );
  }

  Future<void> addToAllowlist({
    required String profileId,
    required String domain,
    String? apiKey,
  }) {
    return _upsertDomainList(
      profileId: profileId,
      endpoint: 'allowlist',
      domain: domain,
      active: true,
      apiKey: apiKey,
    );
  }

  Future<void> removeFromAllowlist({
    required String profileId,
    required String domain,
    String? apiKey,
  }) {
    return _upsertDomainList(
      profileId: profileId,
      endpoint: 'allowlist',
      domain: domain,
      active: false,
      apiKey: apiKey,
    );
  }

  Future<List<NextDnsAnalyticsStatus>> getAnalyticsStatus({
    required String profileId,
    String? apiKey,
    int limit = 10,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      pathSegments: <String>['profiles', profileId, 'analytics', 'status'],
      apiKey: apiKey,
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 500).toString(),
      },
    );
    final data = response['data'];
    if (data is! List) {
      return const <NextDnsAnalyticsStatus>[];
    }
    return data
        .whereType<Map>()
        .map(
          (item) => NextDnsAnalyticsStatus.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Future<List<NextDnsDomainStat>> getTopDomains({
    required String profileId,
    String? apiKey,
    String status = 'blocked',
    int limit = 10,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      pathSegments: <String>['profiles', profileId, 'analytics', 'domains'],
      apiKey: apiKey,
      queryParameters: <String, String>{
        'status': status,
        'limit': limit.clamp(1, 500).toString(),
      },
    );
    final data = response['data'];
    if (data is! List) {
      return const <NextDnsDomainStat>[];
    }
    return data
        .whereType<Map>()
        .map(
          (item) => NextDnsDomainStat.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((domain) => domain.domain.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _upsertParentalControlArrayItem({
    required String profileId,
    required String endpoint,
    required String itemId,
    required bool active,
    String? apiKey,
  }) async {
    final normalizedItem = itemId.trim().toLowerCase();
    if (normalizedItem.isEmpty) {
      throw const NextDnsApiException(
        code: 'invalid_item_id',
        message: 'Control item ID is required.',
      );
    }
    await _requestJson(
      method: 'POST',
      pathSegments: <String>[
        'profiles',
        profileId,
        'parentalControl',
        endpoint,
      ],
      apiKey: apiKey,
      body: <String, dynamic>{
        'id': normalizedItem,
        'active': active,
      },
    );
  }

  Future<void> _upsertDomainList({
    required String profileId,
    required String endpoint,
    required String domain,
    required bool active,
    String? apiKey,
  }) async {
    final normalizedDomain = _normalizeDomain(domain);
    if (normalizedDomain == null) {
      throw const NextDnsApiException(
        code: 'invalid_domain',
        message: 'A valid domain is required.',
      );
    }

    await _requestJson(
      method: 'POST',
      pathSegments: <String>['profiles', profileId, endpoint],
      apiKey: apiKey,
      body: <String, dynamic>{
        'id': normalizedDomain,
        'active': active,
      },
    );
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required List<String> pathSegments,
    String? apiKey,
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
  }) async {
    final effectiveApiKey = (apiKey?.trim().isNotEmpty == true)
        ? apiKey!.trim()
        : await getNextDnsApiKey();
    if (effectiveApiKey == null || effectiveApiKey.isEmpty) {
      throw const NextDnsApiException(
        code: 'missing_api_key',
        message: 'Connect your NextDNS API key first.',
      );
    }

    final sanitizedSegments = pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .toList(growable: false);
    final uri = _baseUri.replace(
      pathSegments: <String>[
        ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        ...sanitizedSegments,
      ],
      queryParameters: queryParameters,
    );

    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'X-Api-Key': effectiveApiKey,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      });

    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await _httpClient.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const NextDnsApiException(
        code: 'timeout',
        message: 'NextDNS request timed out. Please retry.',
      );
    } on SocketException {
      throw const NextDnsApiException(
        code: 'network_error',
        message: 'No internet connection.',
      );
    } on HttpException {
      throw const NextDnsApiException(
        code: 'network_error',
        message: 'Unable to reach NextDNS right now.',
      );
    }

    final decoded = _decodeJsonObject(response.body);
    final errors = _readErrorList(decoded['errors']);
    if (errors.isNotEmpty) {
      final firstError = errors.first;
      throw NextDnsApiException(
        code: (firstError['code'] as String? ?? 'nextdns_error').trim(),
        message: (firstError['detail'] as String? ?? 'NextDNS request failed.')
            .trim(),
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 400) {
      throw NextDnsApiException(
        code: 'http_${response.statusCode}',
        message: 'NextDNS request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    return decoded;
  }

  Map<String, dynamic> _decodeJsonObject(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return <String, dynamic>{};
    } catch (error) {
      debugPrint('[NextDNS] Failed to decode response JSON: $error');
      return <String, dynamic>{};
    }
  }

  List<Map<String, dynamic>> _readErrorList(Object? rawErrors) {
    if (rawErrors is! List) {
      return const <Map<String, dynamic>>[];
    }
    return rawErrors
        .whereType<Map>()
        .map(
          (raw) => raw.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> _asStringKeyedMap(Object? rawMap) {
    if (rawMap is Map<String, dynamic>) {
      return rawMap;
    }
    if (rawMap is Map) {
      return rawMap.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  String? _normalizeDomain(String rawDomain) {
    var value = rawDomain.trim().toLowerCase();
    if (value.isEmpty || value.contains(' ')) {
      return null;
    }
    if (value.startsWith('http://')) {
      value = value.substring('http://'.length);
    } else if (value.startsWith('https://')) {
      value = value.substring('https://'.length);
    }
    final slashIndex = value.indexOf('/');
    if (slashIndex >= 0) {
      value = value.substring(0, slashIndex);
    }
    if (value.startsWith('www.')) {
      value = value.substring(4);
    }
    while (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    final domainPattern = RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$');
    if (!domainPattern.hasMatch(value)) {
      return null;
    }
    return value;
  }
}

int _intOrZero(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}
