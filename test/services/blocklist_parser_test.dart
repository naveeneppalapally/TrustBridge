import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/blocklist_parser.dart';

void main() {
  group('BlocklistParser.parse', () {
    test('parses 0.0.0.0 format', () {
      final result = BlocklistParser.parse('0.0.0.0 instagram.com');
      expect(result, <String>['instagram.com']);
    });

    test('parses 127.0.0.1 format', () {
      final result = BlocklistParser.parse('127.0.0.1 tiktok.com');
      expect(result, <String>['tiktok.com']);
    });

    test('skips comment lines', () {
      final result = BlocklistParser.parse('''
# this is a comment
0.0.0.0 instagram.com
''');
      expect(result, <String>['instagram.com']);
    });

    test('skips blank lines', () {
      final result = BlocklistParser.parse('''

0.0.0.0 twitter.com

''');
      expect(result, <String>['twitter.com']);
    });

    test('skips localhost', () {
      final result = BlocklistParser.parse('''
127.0.0.1 localhost
0.0.0.0 instagram.com
''');
      expect(result, <String>['instagram.com']);
    });

    test('skips broadcasthost', () {
      final result = BlocklistParser.parse('''
127.0.0.1 broadcasthost
0.0.0.0 tiktok.com
''');
      expect(result, <String>['tiktok.com']);
    });

    test('skips ip6 entries', () {
      final result = BlocklistParser.parse('''
0.0.0.0 ip6-localhost
0.0.0.0 ip6-allnodes
0.0.0.0 instagram.com
''');
      expect(result, <String>['instagram.com']);
    });

    test('handles mixed content', () {
      final result = BlocklistParser.parse('''
# header
127.0.0.1 localhost
0.0.0.0 instagram.com

0.0.0.0 tiktok.com
# trailing
127.0.0.1 broadcasthost
0.0.0.0 twitter.com
0.0.0.0 8.8.8.8
''');

      expect(
        result,
        <String>['instagram.com', 'tiktok.com', 'twitter.com'],
      );
    });

    test('lowercases domains', () {
      final result = BlocklistParser.parse('0.0.0.0 INSTAGRAM.COM');
      expect(result, <String>['instagram.com']);
    });

    test('trims whitespace', () {
      final result = BlocklistParser.parse('0.0.0.0  twitter.com  ');
      expect(result, <String>['twitter.com']);
    });
  });
}
