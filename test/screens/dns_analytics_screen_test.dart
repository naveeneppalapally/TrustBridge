import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/screens/dns_analytics_screen.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

void main() {
  group('VpnTelemetry', () {
    test('empty returns zeroed telemetry', () {
      final telemetry = VpnTelemetry.empty();
      expect(telemetry.queriesBlocked, 0);
      expect(telemetry.queriesIntercepted, 0);
      expect(telemetry.queriesAllowed, 0);
      expect(telemetry.isRunning, isFalse);
    });

    test('blockRate is 0 when no queries were intercepted', () {
      final telemetry = VpnTelemetry.empty();
      expect(telemetry.blockRate, 0.0);
    });

    test('blockRate calculates correctly', () {
      const telemetry = VpnTelemetry(
        queriesIntercepted: 100,
        queriesBlocked: 40,
        queriesAllowed: 60,
        isRunning: true,
      );
      expect(telemetry.blockRate, closeTo(0.4, 0.001));
    });

    test('fromMap parses expected fields', () {
      final telemetry = VpnTelemetry.fromMap({
        'queriesIntercepted': 200,
        'queriesBlocked': 80,
        'queriesAllowed': 120,
        'upstreamFailureCount': 3,
        'fallbackQueryCount': 3,
        'activeUpstreamDns': 'abc.dns.nextdns.io',
        'isRunning': true,
      });

      expect(telemetry.queriesIntercepted, 200);
      expect(telemetry.queriesBlocked, 80);
      expect(telemetry.activeUpstreamDns, 'abc.dns.nextdns.io');
      expect(telemetry.isRunning, isTrue);
    });

    test('fromMap handles missing fields', () {
      final telemetry = VpnTelemetry.fromMap(const <String, dynamic>{});
      expect(telemetry.queriesIntercepted, 0);
      expect(telemetry.isRunning, isFalse);
    });
  });

  group('DnsAnalyticsScreen', () {
    testWidgets('renders screen title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DnsAnalyticsScreen()),
      );
      await tester.pump();

      expect(find.text('Protection Analytics'), findsOneWidget);
    });

    testWidgets('shows refresh button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DnsAnalyticsScreen()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
