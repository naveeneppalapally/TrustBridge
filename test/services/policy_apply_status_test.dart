import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/policy_apply_status.dart';

void main() {
  group('PolicyApplyStatusEvaluator', () {
    final now = DateTime(2026, 2, 26, 13, 0, 0);

    test('returns unknown when effective version is missing', () {
      final evaluation = PolicyApplyStatusEvaluator.evaluate(
        effectiveVersion: null,
        effectiveUpdatedAt: null,
        appliedVersion: 10,
        ackUpdatedAt: now,
        applyStatus: 'applied',
        now: now,
      );

      expect(evaluation.indicator, PolicyApplyIndicator.unknown);
    });

    test('returns pending when child ack is missing', () {
      final evaluation = PolicyApplyStatusEvaluator.evaluate(
        effectiveVersion: 100,
        effectiveUpdatedAt: now,
        appliedVersion: null,
        ackUpdatedAt: null,
        applyStatus: null,
        now: now,
      );

      expect(evaluation.indicator, PolicyApplyIndicator.pending);
    });

    test('returns pending when applied version lags effective version', () {
      final evaluation = PolicyApplyStatusEvaluator.evaluate(
        effectiveVersion: 120,
        effectiveUpdatedAt: now,
        appliedVersion: 119,
        ackUpdatedAt: now,
        applyStatus: 'applied',
        now: now,
      );

      expect(evaluation.indicator, PolicyApplyIndicator.pending);
      expect(evaluation.versionLag, 1);
    });

    test('returns applied for fresh matching versions', () {
      final evaluation = PolicyApplyStatusEvaluator.evaluate(
        effectiveVersion: 120,
        effectiveUpdatedAt: now.subtract(const Duration(seconds: 2)),
        appliedVersion: 120,
        ackUpdatedAt: now,
        applyStatus: 'applied',
        now: now,
      );

      expect(evaluation.indicator, PolicyApplyIndicator.applied);
      expect(evaluation.versionLag, 0);
      expect(evaluation.applyDelay, const Duration(seconds: 2));
    });

    test('returns stale when child reports failed status', () {
      final evaluation = PolicyApplyStatusEvaluator.evaluate(
        effectiveVersion: 120,
        effectiveUpdatedAt: now,
        appliedVersion: 120,
        ackUpdatedAt: now,
        applyStatus: 'failed',
        now: now,
      );

      expect(evaluation.indicator, PolicyApplyIndicator.stale);
      expect(evaluation.ackHasFailureStatus, isTrue);
    });

    test('returns stale when acknowledgement is too old', () {
      final evaluation = PolicyApplyStatusEvaluator.evaluate(
        effectiveVersion: 120,
        effectiveUpdatedAt: now.subtract(const Duration(minutes: 20)),
        appliedVersion: 120,
        ackUpdatedAt: now.subtract(const Duration(minutes: 15)),
        applyStatus: 'applied',
        now: now,
      );

      expect(evaluation.indicator, PolicyApplyIndicator.stale);
      expect(
        evaluation.ackAge,
        greaterThan(PolicyApplyStatusEvaluator.staleAckWindow),
      );
    });
  });
}
