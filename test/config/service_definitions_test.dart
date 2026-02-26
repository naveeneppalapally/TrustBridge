import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/config/service_definitions.dart';

void main() {
  group('ServiceDefinitions', () {
    test('YouTube service includes ReVanced Android package mapping', () {
      final youtube = ServiceDefinitions.byId['youtube'];
      expect(youtube, isNotNull);

      final packages =
          youtube!.androidPackages.map((p) => p.toLowerCase()).toSet();
      expect(packages, contains('com.google.android.youtube'));
      expect(packages, contains('app.revanced.android.youtube'));
    });

    test('resolvePackages returns ReVanced package when YouTube is blocked',
        () {
      final packages = ServiceDefinitions.resolvePackages(
        blockedCategories: const <String>[],
        blockedServices: const <String>['youtube'],
      );

      expect(packages, contains('app.revanced.android.youtube'));
    });

    test(
        'individual Facebook service block uses critical domains to avoid shared Meta collateral',
        () {
      final domains = ServiceDefinitions.resolveDomains(
        blockedCategories: const <String>[],
        blockedServices: const <String>['facebook'],
        customBlockedDomains: const <String>[],
      );

      expect(domains, contains('facebook.com'));
      expect(domains, isNot(contains('connect.facebook.net')));
      expect(domains, isNot(contains('fbcdn.net')));
      expect(domains, isNot(contains('facebook.net')));
    });

    test(
        'social-networks category block still uses full service domain coverage',
        () {
      final domains = ServiceDefinitions.resolveDomains(
        blockedCategories: const <String>['social-networks'],
        blockedServices: const <String>[],
        customBlockedDomains: const <String>[],
      );

      expect(domains, contains('facebook.com'));
      expect(domains, contains('connect.facebook.net'));
      expect(domains, contains('fbcdn.net'));
    });
  });
}
