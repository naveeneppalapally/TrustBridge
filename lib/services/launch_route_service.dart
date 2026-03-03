import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_service.dart';
import 'onboarding_state_service.dart';

class LaunchRoute {
  const LaunchRoute({
    required this.parentId,
    required this.onboardingComplete,
  });

  final String parentId;
  final bool onboardingComplete;
}

class LaunchRouteService {
  LaunchRouteService({
    FirestoreService? firestoreService,
    OnboardingStateService? onboardingStateService,
  })  : _firestoreService = firestoreService ?? FirestoreService(),
        _onboardingStateService =
            onboardingStateService ?? OnboardingStateService();

  final FirestoreService _firestoreService;
  final OnboardingStateService _onboardingStateService;

  Future<LaunchRoute> resolveForUser(User user) async {
    var localCompletion = false;
    try {
      localCompletion = await _onboardingStateService
          .isCompleteLocally(user.uid)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      localCompletion = false;
    }

    if (localCompletion) {
      unawaited(_reconcileOnboardingStateWithCloud(user));
      return LaunchRoute(
        parentId: user.uid,
        onboardingComplete: true,
      );
    }

    try {
      await _firestoreService
          .ensureParentProfile(
            parentId: user.uid,
            phoneNumber: user.phoneNumber,
          )
          .timeout(const Duration(seconds: 12));

      final parentPrefs = await _firestoreService
          .getParentPreferences(user.uid)
          .timeout(const Duration(seconds: 12));
      final remoteCompletion =
          (parentPrefs?['onboardingComplete'] as bool?) ?? false;
      var onboardingComplete = remoteCompletion || localCompletion;

      if (!onboardingComplete) {
        final hasExistingChildren = await _firestoreService
            .hasAnyChildProfiles(user.uid)
            .timeout(const Duration(seconds: 12));
        if (hasExistingChildren) {
          onboardingComplete = true;
        }
      }

      if (remoteCompletion && !localCompletion) {
        unawaited(_onboardingStateService.markCompleteLocally(user.uid));
      } else if (onboardingComplete && !remoteCompletion) {
        unawaited(_firestoreService.completeOnboarding(user.uid));
      }

      return LaunchRoute(
        parentId: user.uid,
        onboardingComplete: onboardingComplete,
      );
    } catch (_) {
      return LaunchRoute(
        parentId: user.uid,
        onboardingComplete: localCompletion,
      );
    }
  }

  Future<void> _reconcileOnboardingStateWithCloud(User user) async {
    try {
      await _firestoreService
          .ensureParentProfile(
            parentId: user.uid,
            phoneNumber: user.phoneNumber,
          )
          .timeout(const Duration(seconds: 12));
      final parentPrefs = await _firestoreService
          .getParentPreferences(user.uid)
          .timeout(const Duration(seconds: 12));
      final remoteCompletion =
          (parentPrefs?['onboardingComplete'] as bool?) ?? false;
      if (!remoteCompletion) {
        await _firestoreService.completeOnboarding(user.uid).timeout(
              const Duration(seconds: 12),
            );
      } else {
        await _onboardingStateService.markCompleteLocally(user.uid).timeout(
              const Duration(seconds: 2),
            );
      }
    } catch (_) {
      // Best-effort reconciliation.
    }
  }
}
