import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';

void main() {
  group('NextDnsApiService', () {
    test('stores, reads, and clears api key securely', () async {
      final secretStore = InMemoryNextDnsSecretStore();
      final service = NextDnsApiService(
        secretStore: secretStore,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      await service.setNextDnsApiKey(' api-key-123 ');
      expect(await service.getNextDnsApiKey(), 'api-key-123');

      await service.clearNextDnsApiKey();
      expect(await service.getNextDnsApiKey(), isNull);
    });

    test('fetchProfiles parses data list', () async {
      final service = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'abc123', 'name': 'Child A'},
                {'id': 'def456', 'name': 'Child B'},
              ],
            }),
            200,
          );
        }),
      );

      final profiles = await service.fetchProfiles(apiKey: 'k');
      expect(profiles.length, 2);
      expect(profiles.first.id, 'abc123');
      expect(profiles.first.name, 'Child A');
    });

    test('createProfile returns created profile', () async {
      final service = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/profiles');
          return http.Response(
            jsonEncode({
              'data': {'id': 'ff0011'}
            }),
            200,
          );
        }),
      );

      final profile = await service.createProfile(
        name: 'Aarav',
        apiKey: 'k',
      );
      expect(profile.id, 'ff0011');
      expect(profile.name, 'Aarav');
    });

    test('setServiceBlocked posts to services endpoint', () async {
      Uri? seenUri;
      String? seenBody;

      final service = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((request) async {
          seenUri = request.url;
          seenBody = request.body;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );

      await service.setServiceBlocked(
        profileId: 'abc123',
        serviceId: 'youtube',
        blocked: true,
        apiKey: 'k',
      );

      expect(
        seenUri?.path,
        '/profiles/abc123/parentalControl/services',
      );
      expect(seenBody, contains('"id":"youtube"'));
      expect(seenBody, contains('"active":true'));
    });

    test('throws normalized exception on auth failure payload', () async {
      final service = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'errors': [
                {
                  'code': 'unauthorized',
                  'detail': 'Invalid API key',
                }
              ],
            }),
            401,
          );
        }),
      );

      expect(
        () => service.fetchProfiles(apiKey: 'bad-key'),
        throwsA(
          isA<NextDnsApiException>().having(
            (error) => error.code,
            'code',
            'unauthorized',
          ),
        ),
      );
    });

    test('throws timeout exception code on timeout', () async {
      final service = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        timeout: const Duration(milliseconds: 5),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response('{}', 200);
        }),
      );

      expect(
        () => service.fetchProfiles(apiKey: 'k'),
        throwsA(
          isA<NextDnsApiException>().having(
            (error) => error.code,
            'code',
            'timeout',
          ),
        ),
      );
    });

    test('rejects invalid allowlist domain', () async {
      final service = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => service.addToAllowlist(
          profileId: 'abc123',
          domain: 'not a domain',
          apiKey: 'k',
        ),
        throwsA(
          isA<NextDnsApiException>().having(
            (error) => error.code,
            'code',
            'invalid_domain',
          ),
        ),
      );
    });
  });
}
