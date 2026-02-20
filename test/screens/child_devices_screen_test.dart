import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/child_devices_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('ChildDevicesScreen', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;
    late ChildProfile child;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
      child = ChildProfile.create(
        nickname: 'Leo',
        ageBand: AgeBand.young,
      );
    });

    Future<void> seedChild(String parentId) {
      return fakeFirestore.collection('children').doc(child.id).set({
        ...child.toFirestore(),
        'parentId': parentId,
      });
    }

    testWidgets('renders empty state and add controls', (tester) async {
      await seedChild('parent-device-a');

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDevicesScreen(
            child: child,
            parentIdOverride: 'parent-device-a',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manage Devices'), findsOneWidget);
      expect(find.byKey(const Key('device_id_input')), findsOneWidget);
      expect(find.byKey(const Key('add_device_id_button')), findsOneWidget);
      expect(
        find.text(
            'No devices linked yet. Add one to start managing this child device.'),
        findsOneWidget,
      );
    });

    testWidgets('adds device and saves to firestore', (tester) async {
      const parentId = 'parent-device-b';
      await seedChild(parentId);

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDevicesScreen(
            child: child,
            parentIdOverride: parentId,
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('device_id_input')), 'pixel-7');
      await tester.tap(find.byKey(const Key('add_device_id_button')));
      await tester.pumpAndSettle();

      expect(find.text('SAVE'), findsOneWidget);
      expect(find.text('pixel-7'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'SAVE'));
      await tester.pumpAndSettle();

      final snapshot =
          await fakeFirestore.collection('children').doc(child.id).get();
      final data = snapshot.data()!;
      expect(data['deviceIds'], ['pixel-7']);
      expect(data['updatedAt'], isA<Timestamp>());
    });

    testWidgets('shows duplicate validation error', (tester) async {
      child = child.copyWith(deviceIds: ['device-a']);
      await seedChild('parent-device-c');

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDevicesScreen(
            child: child,
            parentIdOverride: 'parent-device-c',
            firestoreService: firestoreService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('device_id_input')), 'device-a');
      await tester.tap(find.byKey(const Key('add_device_id_button')));
      await tester.pumpAndSettle();

      expect(find.text('This device ID is already linked.'), findsOneWidget);
    });

    testWidgets('shows QR setup and verifies NextDNS routing for linked profile',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const parentId = 'parent-device-d';
      child = child.copyWith(nextDnsProfileId: 'abc123');
      await seedChild(parentId);

      final client = MockClient((request) async {
        if (request.url.toString() == 'https://test.nextdns.io') {
          return http.Response(
            jsonEncode({'profile': 'abc123'}),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDevicesScreen(
            child: child,
            parentIdOverride: parentId,
            firestoreService: firestoreService,
            httpClient: client,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('child_device_setup_qr')), findsOneWidget);
      expect(find.byKey(const Key('verify_nextdns_button')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('verify_nextdns_button')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('verify_nextdns_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('child_device_verify_message')), findsOneWidget);
      expect(find.textContaining('Protected'), findsOneWidget);
    });
  });
}
