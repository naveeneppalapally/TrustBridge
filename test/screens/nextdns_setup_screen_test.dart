import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/nextdns_setup_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';

void main() {
  group('NextDnsSetupScreen', () {
    testWidgets('renders API key connect controls', (tester) async {
      final firestoreService = FirestoreService(
        firestore: FakeFirebaseFirestore(),
      );
      final nextDnsApiService = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NextDnsSetupScreen(
            firestoreService: firestoreService,
            nextDnsApiService: nextDnsApiService,
            parentIdOverride: 'parent-test',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('nextdns_setup_api_key_field')), findsOneWidget);
      expect(find.byKey(const Key('nextdns_setup_connect_button')),
          findsOneWidget);
    });

    testWidgets('loads child mapping after successful connect', (tester) async {
      const parentId = 'parent-a';
      final fakeFirestore = FakeFirebaseFirestore();
      final child = ChildProfile.create(
        nickname: 'Aarav',
        ageBand: AgeBand.middle,
      );
      await fakeFirestore.collection('children').doc(child.id).set({
        ...child.toFirestore(),
        'parentId': parentId,
      });

      final firestoreService = FirestoreService(firestore: fakeFirestore);
      final nextDnsApiService = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/profiles') {
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': 'abc123', 'name': 'Aarav Profile'},
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NextDnsSetupScreen(
            firestoreService: firestoreService,
            nextDnsApiService: nextDnsApiService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('nextdns_setup_api_key_field')),
        'test-key',
      );
      await tester.tap(find.byKey(const Key('nextdns_setup_connect_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Connected'), findsWidgets);
      expect(
        find.byType(DropdownButtonFormField<String>),
        findsOneWidget,
      );
    });
  });
}
