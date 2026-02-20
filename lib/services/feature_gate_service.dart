import '../config/feature_gates.dart';
import '../models/subscription.dart';
import 'subscription_service.dart';

/// Result of a feature gate check.
class GateResult {
  const GateResult({
    required this.allowed,
    this.blockedFeature,
    this.upgradeReason,
  });

  /// True when feature is allowed for current subscription.
  final bool allowed;

  /// Feature that was blocked.
  final AppFeature? blockedFeature;

  /// Human readable upgrade reason.
  final String? upgradeReason;
}

/// Subscription-backed feature gate resolver.
class FeatureGateService {
  FeatureGateService({
    SubscriptionService? subscriptionService,
  }) : _subscriptionService = subscriptionService ?? SubscriptionService();

  final SubscriptionService _subscriptionService;

  /// Checks availability for a feature based on effective subscription tier.
  Future<GateResult> checkGate(AppFeature feature) async {
    // Free features should never require backend access.
    final requiredTier = FeatureGates.requiredTier(feature);
    if (requiredTier == SubscriptionTier.free) {
      return const GateResult(allowed: true);
    }

    final subscription = await _subscriptionService.getCurrentSubscription();
    final tier = subscription.effectiveTier;
    final allowed = FeatureGates.isAvailable(feature, tier);
    if (allowed) {
      return const GateResult(allowed: true);
    }

    return GateResult(
      allowed: false,
      blockedFeature: feature,
      upgradeReason: _reasonForFeature(feature),
    );
  }

  String _reasonForFeature(AppFeature feature) {
    switch (feature) {
      case AppFeature.additionalChildren:
        return 'Multiple child profiles are available with TrustBridge Pro.';
      case AppFeature.categoryBlocking:
        return 'Advanced category controls are available with TrustBridge Pro.';
      case AppFeature.schedules:
        return 'Schedules are available with TrustBridge Pro.';
      case AppFeature.bypassAlerts:
        return 'Bypass alerts are available with TrustBridge Pro.';
      case AppFeature.fullReports:
        return 'Detailed reports are available with TrustBridge Pro.';
      case AppFeature.requestApproveFlow:
        return 'Request and approve flow is available with TrustBridge Pro.';
      case AppFeature.nextDnsIntegration:
        return 'NextDNS integration is available with TrustBridge Pro.';
    }
  }
}
