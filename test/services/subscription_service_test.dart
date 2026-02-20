import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/subscription.dart';
import 'package:trustbridge_app/services/subscription_service.dart';

void main() {
  group('SubscriptionService', () {
    late FakeFirebaseFirestore firestore;
    late DateTime now;
    late SubscriptionService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      now = DateTime(2026, 2, 20, 12, 0, 0);
      service = SubscriptionService(
        firestore: firestore,
        nowProvider: () => now,
        currentUserIdResolver: () => 'parent-1',
      );
    });

    test('pro with future validUntil is active', () async {
      await _setSubscription(
        firestore: firestore,
        parentId: 'parent-1',
        data: <String, dynamic>{
          'tier': 'pro',
          'validUntil': Timestamp.fromDate(now.add(const Duration(days: 5))),
          'isInTrial': false,
        },
      );

      final subscription = await service.getCurrentSubscription();
      expect(subscription.isPro, isTrue);
    });

    test('pro with past validUntil falls back to free', () async {
      await _setSubscription(
        firestore: firestore,
        parentId: 'parent-1',
        data: <String, dynamic>{
          'tier': 'pro',
          'validUntil':
              Timestamp.fromDate(now.subtract(const Duration(days: 1))),
          'isInTrial': false,
        },
      );

      final subscription = await service.getCurrentSubscription();
      expect(subscription.isPro, isFalse);
      expect(subscription.effectiveTier, SubscriptionTier.free);
    });

    test('missing subscription document returns free tier', () async {
      final subscription = await service.getCurrentSubscription();
      expect(subscription.effectiveTier, SubscriptionTier.free);
    });

    test('startTrial can only be used once', () async {
      await firestore.collection('parents').doc('parent-1').set(
        <String, dynamic>{
          'subscription': <String, dynamic>{
            'tier': 'free',
            'isInTrial': false,
            'trialUsed': false,
          },
        },
      );

      final first = await service.startTrial();
      final second = await service.startTrial();

      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('trial ending in past is not pro', () async {
      await _setSubscription(
        firestore: firestore,
        parentId: 'parent-1',
        data: <String, dynamic>{
          'tier': 'pro',
          'isInTrial': true,
          'trialEndsAt':
              Timestamp.fromDate(now.subtract(const Duration(days: 1))),
          'validUntil':
              Timestamp.fromDate(now.subtract(const Duration(days: 1))),
        },
      );

      final subscription = await service.getCurrentSubscription();
      expect(subscription.isPro, isFalse);
      expect(subscription.effectiveTier, SubscriptionTier.free);
    });
  });
}

Future<void> _setSubscription({
  required FakeFirebaseFirestore firestore,
  required String parentId,
  required Map<String, dynamic> data,
}) async {
  await firestore.collection('parents').doc(parentId).set(
    <String, dynamic>{
      'subscription': data,
    },
  );
}
