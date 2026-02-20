import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/config/social_media_domains.dart';

void main() {
  group('SocialMediaDomains', () {
    test('all contains instagram.com', () {
      expect(SocialMediaDomains.all.contains('instagram.com'), isTrue);
    });

    test('all contains tiktok.com', () {
      expect(SocialMediaDomains.all.contains('tiktok.com'), isTrue);
    });

    test('appForDomain returns instagram', () {
      expect(
        SocialMediaDomains.appForDomain('instagram.com'),
        equals('instagram'),
      );
    });

    test('appForDomain returns null for unknown domain', () {
      expect(
        SocialMediaDomains.appForDomain('google.com'),
        isNull,
      );
    });
  });
}
