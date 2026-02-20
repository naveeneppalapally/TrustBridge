import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/config/feature_gates.dart';
import 'package:trustbridge_app/models/subscription.dart';
import 'package:trustbridge_app/services/feature_gate_service.dart';
import 'package:trustbridge_app/services/subscription_service.dart';

void main() {
  group('FeatureGateService', () {
    test('free tier blocks schedules', () async {
      final service = FeatureGateService(
        subscriptionService: _FakeSubscriptionService(
          const Subscription(
            tier: SubscriptionTier.free,
            isInTrial: false,
          ),
        ),
      );

      final result = await service.checkGate(AppFeature.schedules);
      expect(result.allowed, isFalse);
    });

    test('free tier blocks additional children', () async {
      final service = FeatureGateService(
        subscriptionService: _FakeSubscriptionService(
          const Subscription(
            tier: SubscriptionTier.free,
            isInTrial: false,
          ),
        ),
      );

      final result = await service.checkGate(AppFeature.additionalChildren);
      expect(result.allowed, isFalse);
    });

    test('pro tier allows schedules', () async {
      final service = FeatureGateService(
        subscriptionService: _FakeSubscriptionService(
          Subscription(
            tier: SubscriptionTier.pro,
            validUntil: DateTime.now().add(const Duration(days: 30)),
            isInTrial: false,
          ),
        ),
      );

      final result = await service.checkGate(AppFeature.schedules);
      expect(result.allowed, isTrue);
    });

    test('pro tier allows all features', () async {
      final service = FeatureGateService(
        subscriptionService: _FakeSubscriptionService(
          Subscription(
            tier: SubscriptionTier.pro,
            validUntil: DateTime.now().add(const Duration(days: 30)),
            isInTrial: false,
          ),
        ),
      );

      for (final feature in AppFeature.values) {
        final result = await service.checkGate(feature);
        expect(result.allowed, isTrue,
            reason: 'Feature $feature should be allowed');
      }
    });

    test('expired pro falls back to free and blocks gates', () async {
      final service = FeatureGateService(
        subscriptionService: _FakeSubscriptionService(
          Subscription(
            tier: SubscriptionTier.pro,
            validUntil: DateTime.now().subtract(const Duration(days: 1)),
            isInTrial: false,
          ),
        ),
      );

      final result = await service.checkGate(AppFeature.schedules);
      expect(result.allowed, isFalse);
    });
  });
}

class _FakeSubscriptionService extends SubscriptionService {
  _FakeSubscriptionService(this.subscription) : super();

  final Subscription subscription;

  @override
  Future<Subscription> getCurrentSubscription() async => subscription;
}
