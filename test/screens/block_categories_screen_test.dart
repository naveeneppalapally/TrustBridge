import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';
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
      RolloutFlags.resetForTest();
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
      RolloutFlags.resetForTest();
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
      await tester.pumpAndSettle();

      expect(find.text('Category Blocking'), findsOneWidget);
      expect(find.byKey(const Key('block_categories_search')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('APP CATEGORIES'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('APP CATEGORIES'), findsOneWidget);
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

      final socialCategorySwitch =
          find.byKey(const Key('block_category_switch_social-networks'));
      await tester.scrollUntilVisible(
        socialCategorySwitch,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(socialCategorySwitch);
      await tester.pumpAndSettle();
      await tester.tap(socialCategorySwitch);
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

    testWidgets('hides policy sync diagnostics for parent-facing UI',
        (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);
      const parentId = 'parent-policy-status';
      final child = testChild.copyWith(
        policy: testChild.policy.copyWith(
          blockedCategories: const <String>['social-networks'],
          blockedServices: const <String>['instagram'],
          blockedDomains: const <String>[],
        ),
      );

      await fakeFirestore.collection('children').doc(child.id).set({
        ...child.toFirestore(),
        'parentId': parentId,
      });

      await fakeFirestore
          .collection('children')
          .doc(child.id)
          .collection('effective_policy')
          .doc('current')
          .set({
        'parentId': parentId,
        'childId': child.id,
        'version': 200,
        'updatedAt': Timestamp.now(),
      });

      await fakeFirestore
          .collection('children')
          .doc(child.id)
          .collection('policy_apply_acks')
          .doc('device-1')
          .set({
        'parentId': parentId,
        'childId': child.id,
        'deviceId': 'device-1',
        'applyStatus': 'applied',
        'appliedVersion': 199,
        'updatedAt': Timestamp.now(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(
            child: child,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('block_categories_policy_sync_card')),
        findsNothing,
      );
      expect(find.text('APP CATEGORIES'), findsOneWidget);
    });

    testWidgets('hides web validation diagnostics for parent-facing UI',
        (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);
      const parentId = 'parent-web-hints';

      await fakeFirestore.collection('children').doc(testChild.id).set({
        ...testChild.toFirestore(),
        'parentId': parentId,
      });

      await fakeFirestore
          .collection('children')
          .doc(testChild.id)
          .collection('vpn_diagnostics')
          .doc('current')
          .set({
        'parentId': parentId,
        'childId': testChild.id,
        'vpnRunning': true,
        'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 26, 12, 0)),
        'likelyDnsBypass': false,
        'bypassReasonCode': 'browser_not_foreground',
        'lastBlockedDnsQuery': {
          'domain': 'instagram.com',
          'reasonCode': 'block_custom_domain_rule',
          'matchedRule': 'instagram.com',
          'timestampEpochMs':
              DateTime(2026, 2, 26, 11, 59).millisecondsSinceEpoch,
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BlockCategoriesScreen(
            child: testChild,
            firestoreService: firestoreService,
            parentIdOverride: parentId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('block_categories_web_validation_card')),
        findsNothing,
      );
      expect(find.text('APP CATEGORIES'), findsOneWidget);
    });
  });
}
