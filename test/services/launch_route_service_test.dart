import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/launch_route_service.dart';
import 'package:trustbridge_app/services/onboarding_state_service.dart';

class _MockFirestoreService extends Mock implements FirestoreService {}

class _MockOnboardingStateService extends Mock
    implements OnboardingStateService {}

class _MockUser extends Mock implements User {}

void main() {
  test(
    'resolveForUser waits for returning parent reconciliation before routing',
    () async {
      final firestoreService = _MockFirestoreService();
      final onboardingStateService = _MockOnboardingStateService();
      final user = _MockUser();
      final ensureCompleter = Completer<void>();

      when(() => user.uid).thenReturn('parent-123');
      when(() => user.phoneNumber).thenReturn(null);
      when(
        () => onboardingStateService.isCompleteLocally('parent-123'),
      ).thenAnswer((_) async => true);
      when(
        () => firestoreService.ensureParentProfile(
          parentId: 'parent-123',
          phoneNumber: null,
        ),
      ).thenAnswer((_) => ensureCompleter.future);
      when(
        () => firestoreService.getParentPreferences('parent-123'),
      ).thenAnswer((_) async => <String, dynamic>{'onboardingComplete': true});
      when(
        () => onboardingStateService.markCompleteLocally('parent-123'),
      ).thenAnswer((_) async {});

      final service = LaunchRouteService(
        firestoreService: firestoreService,
        onboardingStateService: onboardingStateService,
      );

      var resolved = false;
      final future = service.resolveForUser(user).then((route) {
        resolved = true;
        return route;
      });

      await Future<void>.delayed(Duration.zero);
      expect(resolved, isFalse);

      ensureCompleter.complete();
      final route = await future;

      expect(route.parentId, 'parent-123');
      expect(route.onboardingComplete, isTrue);
      verify(
        () => firestoreService.ensureParentProfile(
          parentId: 'parent-123',
          phoneNumber: null,
        ),
      ).called(1);
      verify(
        () => firestoreService.getParentPreferences('parent-123'),
      ).called(1);
    },
  );
}
