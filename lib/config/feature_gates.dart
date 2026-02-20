import '../models/subscription.dart';

/// Feature keys used for subscription gating.
enum AppFeature {
  additionalChildren,
  categoryBlocking,
  schedules,
  bypassAlerts,
  fullReports,
  requestApproveFlow,
  nextDnsIntegration,
}

/// Subscription requirements per feature.
class FeatureGates {
  FeatureGates._();

  static const Map<AppFeature, SubscriptionTier> _requirements =
      <AppFeature, SubscriptionTier>{
    AppFeature.additionalChildren: SubscriptionTier.pro,
    AppFeature.categoryBlocking: SubscriptionTier.pro,
    AppFeature.schedules: SubscriptionTier.pro,
    AppFeature.bypassAlerts: SubscriptionTier.pro,
    AppFeature.fullReports: SubscriptionTier.pro,
    AppFeature.nextDnsIntegration: SubscriptionTier.pro,
  };

  /// Returns true if [feature] is available in [currentTier].
  static bool isAvailable(AppFeature feature, SubscriptionTier currentTier) {
    final required = requiredTier(feature);
    return currentTier.index >= required.index;
  }

  /// Returns minimum required tier for a feature.
  static SubscriptionTier requiredTier(AppFeature feature) {
    return _requirements[feature] ?? SubscriptionTier.free;
  }
}
