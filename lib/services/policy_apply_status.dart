enum PolicyApplyIndicator {
  applied,
  pending,
  stale,
  unknown,
}

class PolicyApplyEvaluation {
  const PolicyApplyEvaluation({
    required this.indicator,
    required this.effectiveVersion,
    required this.appliedVersion,
    required this.versionLag,
    required this.ackAge,
    required this.applyDelay,
    required this.ackHasFailureStatus,
  });

  final PolicyApplyIndicator indicator;
  final int? effectiveVersion;
  final int? appliedVersion;
  final int? versionLag;
  final Duration? ackAge;
  final Duration? applyDelay;
  final bool ackHasFailureStatus;
}

class PolicyApplyStatusEvaluator {
  const PolicyApplyStatusEvaluator._();

  static const Duration staleAckWindow = Duration(minutes: 10);

  static PolicyApplyEvaluation evaluate({
    required int? effectiveVersion,
    required DateTime? effectiveUpdatedAt,
    required int? appliedVersion,
    required DateTime? ackUpdatedAt,
    required String? applyStatus,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final normalizedStatus = applyStatus?.trim().toLowerCase();
    final hasFailureStatus = normalizedStatus == 'failed' ||
        normalizedStatus == 'error' ||
        normalizedStatus == 'mismatch';

    final versionLag = (effectiveVersion == null || appliedVersion == null)
        ? null
        : effectiveVersion - appliedVersion;

    final ackAge = ackUpdatedAt == null
        ? null
        : _clampPositive(currentTime.difference(ackUpdatedAt));

    final applyDelay = (effectiveUpdatedAt == null || ackUpdatedAt == null)
        ? null
        : _clampPositive(ackUpdatedAt.difference(effectiveUpdatedAt));

    final indicator = _deriveIndicator(
      effectiveVersion: effectiveVersion,
      appliedVersion: appliedVersion,
      versionLag: versionLag,
      ackAge: ackAge,
      hasFailureStatus: hasFailureStatus,
    );

    return PolicyApplyEvaluation(
      indicator: indicator,
      effectiveVersion: effectiveVersion,
      appliedVersion: appliedVersion,
      versionLag: versionLag,
      ackAge: ackAge,
      applyDelay: applyDelay,
      ackHasFailureStatus: hasFailureStatus,
    );
  }

  static PolicyApplyIndicator _deriveIndicator({
    required int? effectiveVersion,
    required int? appliedVersion,
    required int? versionLag,
    required Duration? ackAge,
    required bool hasFailureStatus,
  }) {
    if (effectiveVersion == null) {
      return PolicyApplyIndicator.unknown;
    }
    if (appliedVersion == null) {
      return PolicyApplyIndicator.pending;
    }
    if (versionLag != null && versionLag > 0) {
      return PolicyApplyIndicator.pending;
    }
    if (versionLag != null && versionLag < 0) {
      return PolicyApplyIndicator.stale;
    }
    if (hasFailureStatus) {
      return PolicyApplyIndicator.stale;
    }
    if (ackAge != null && ackAge > staleAckWindow) {
      return PolicyApplyIndicator.stale;
    }
    return PolicyApplyIndicator.applied;
  }

  static Duration _clampPositive(Duration input) {
    if (input.isNegative) {
      return Duration.zero;
    }
    return input;
  }
}
