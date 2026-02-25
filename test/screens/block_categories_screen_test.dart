import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/block_categories_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';

void main() {
  group('BlockCategoriesScreen', () {
    late ChildProfile testChild;
    late Map<String, String> secureStorage;
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

    setUp(() async {
      testChild = ChildProfile.create(
        nickname: 'Test Child',
        ageBand: AgeBand.young,
      );
      secureStorage = <String, String>{
        'trustbridge_pin_enabled': 'false',
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
        switch (call.method) {
          case 'read':
            return secureStorage[call.arguments['key'] as String? ?? ''];
          case 'write':
            final key = call.arguments['key'] as String? ?? '';
            final value = call.arguments['value'] as String?;
            if (value == null) {
              secureStorage.remove(key);
            } else {
              secureStorage[key] = value;
            }
            return null;
          case 'delete':
            secureStorage.remove(call.arguments['key'] as String? ?? '');
            return null;
          case 'deleteAll':
            secureStorage.clear();
            return null;
          case 'containsKey':
            return secureStorage
                .containsKey(call.arguments['key'] as String? ?? '');
          case 'readAll':
            return Map<String, String>.from(secureStorage);
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });

    testWidgets('renders search and category section', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(find.text('Category Blocking'), findsOneWidget);
      expect(find.byKey(const Key('block_categories_search')), findsOneWidget);
      expect(find.text('APP CATEGORIES'), findsOneWidget);
      expect(find.text('Adult Content'), findsOneWidget);
    });

    testWidgets('shows custom blocked sites section with add button',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('CUSTOM BLOCKED SITES'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('CUSTOM BLOCKED SITES'), findsOneWidget);
      expect(
          find.byKey(const Key('block_categories_add_domain')), findsOneWidget);
    });

    testWidgets('switch updates state and shows sticky save bar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );
      await tester.pump();

      expect(
          find.byKey(const Key('block_categories_save_button')), findsNothing);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('block_categories_save_button')),
          findsOneWidget);
      expect(find.textContaining('Safe Mode Active'), findsOneWidget);
    });

    testWidgets('can add a custom blocked domain', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(child: testChild),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.byKey(const Key('block_categories_add_domain')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('block_categories_add_domain')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('block_categories_domain_input')),
        'reddit.com',
      );
      await tester
          .tap(find.byKey(const Key('block_categories_add_domain_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('reddit.com'), findsOneWidget);
    });

    testWidgets('renders NextDNS controls when child profile is linked',
        (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);
      const parentId = 'parent-nextdns-block';
      final linkedChild = testChild.copyWith(nextDnsProfileId: 'abc123');

      await fakeFirestore.collection('children').doc(linkedChild.id).set({
        ...linkedChild.toFirestore(),
        'parentId': parentId,
      });

      final nextDnsApiService = NextDnsApiService(
        secretStore: InMemoryNextDnsSecretStore(),
        httpClient: MockClient((_) async {
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );
      await nextDnsApiService.setNextDnsApiKey('test-api-key');

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(
            child: linkedChild,
            firestoreService: firestoreService,
            nextDnsApiService: nextDnsApiService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('block_categories_nextdns_card')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const Key('block_categories_nextdns_card')),
        findsOneWidget,
      );
      expect(
          find.byKey(const Key('nextdns_safe_search_switch')), findsOneWidget);
    });
  });
}
