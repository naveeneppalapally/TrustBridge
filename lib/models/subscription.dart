import 'package:cloud_firestore/cloud_firestore.dart';

/// Subscription tiers supported by TrustBridge.
enum SubscriptionTier {
  free,
  pro,
}

/// Parent subscription state stored in Firestore.
class Subscription {
  const Subscription({
    required this.tier,
    this.validUntil,
    this.trialEndsAt,
    this.purchaseToken,
    required this.isInTrial,
  });

  /// Active tier from backend payload.
  final SubscriptionTier tier;

  /// Validity end timestamp for paid access.
  final DateTime? validUntil;

  /// Trial end timestamp (if trial started).
  final DateTime? trialEndsAt;

  /// Google Play purchase token (if purchased).
  final String? purchaseToken;

  /// Flag indicating subscription is in trial mode.
  final bool isInTrial;

  /// Returns true when paid subscription is active.
  bool get isActive =>
      tier == SubscriptionTier.pro &&
      (validUntil == null || validUntil!.isAfter(DateTime.now()));

  /// Returns true when trial is active.
  bool get isTrialActive =>
      isInTrial && trialEndsAt != null && trialEndsAt!.isAfter(DateTime.now());

  /// Returns true when pro access is available (paid or trial).
  bool get isPro => isActive || isTrialActive;

  /// Effective tier after expiry fallback logic.
  SubscriptionTier get effectiveTier =>
      isPro ? SubscriptionTier.pro : SubscriptionTier.free;

  /// Creates a free-tier fallback subscription.
  factory Subscription.free() {
    return const Subscription(
      tier: SubscriptionTier.free,
      isInTrial: false,
    );
  }

  /// Parses a subscription payload from Firestore map.
  factory Subscription.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return Subscription.free();
    }

    final tierRaw = (map['tier'] as String?)?.trim().toLowerCase();
    final tier =
        tierRaw == 'pro' ? SubscriptionTier.pro : SubscriptionTier.free;
    final validUntil = _toDateTime(map['validUntil']);
    final trialEndsAt = _toDateTime(map['trialEndsAt']);
    final purchaseToken = (map['purchaseToken'] as String?)?.trim();

    return Subscription(
      tier: tier,
      validUntil: validUntil,
      trialEndsAt: trialEndsAt,
      purchaseToken:
          purchaseToken == null || purchaseToken.isEmpty ? null : purchaseToken,
      isInTrial: map['isInTrial'] == true,
    );
  }

  /// Serializes subscription state to Firestore-friendly map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tier': tier.name,
      'validUntil': validUntil == null ? null : Timestamp.fromDate(validUntil!),
      'trialEndsAt':
          trialEndsAt == null ? null : Timestamp.fromDate(trialEndsAt!),
      'purchaseToken': purchaseToken,
      'isInTrial': isInTrial,
    };
  }

  static DateTime? _toDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return null;
  }
}
