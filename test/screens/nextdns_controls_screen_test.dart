import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/nextdns_controls_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';

void main() {
  group('NextDnsControlsScreen', () {
    testWidgets('shows profile-required message when child is not linked',
        (tester) async {
      final child = ChildProfile.create(
        nickname: 'Maya',
        ageBand: AgeBand.middle,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NextDnsControlsScreen(
            child: child,
            parentIdOverride: 'parent-id',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not linked to a NextDNS profile'),
          findsOneWidget);
    });

    testWidgets('renders control switches for linked child', (tester) async {
      final child = ChildProfile.create(
        nickname: 'Aarav',
        ageBand: AgeBand.middle,
      ).copyWith(nextDnsProfileId: 'abc123');
      expect(child.nextDnsProfileId, 'abc123');

      final firestoreService = FirestoreService(
        firestore: FakeFirebaseFirestore(),
      );
      final apiService = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'data': {}}),
              200,
            )),
      );
      await apiService.setNextDnsApiKey('key');

      await tester.pumpWidget(
        MaterialApp(
          home: NextDnsControlsScreen(
            child: child,
            firestoreService: firestoreService,
            nextDnsApiService: apiService,
            parentIdOverride: 'parent-id',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not linked to a NextDNS profile'), findsNothing);
      expect(find.text('Service Blocking'), findsOneWidget);
      expect(find.text('Category Blocking'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('SafeSearch'), findsOneWidget);
      expect(find.text('YouTube Restricted Mode'), findsOneWidget);
      expect(find.text('Block Bypass'), findsOneWidget);
    });
  });
}
