// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/screens/child/child_status_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

const String _runIdRaw = String.fromEnvironment(
  'TB_RUN_ID',
  defaultValue: '',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'child cleans up within 30s after profile deletion',
    (tester) async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final firestore = FirebaseFirestore.instance;
      final firestoreService = FirestoreService(firestore: firestore);
      final auth = FirebaseAuth.instance;
      final pairing = PairingService();
      final vpn = VpnService();

      final runId = _normalizeRunId(_runIdRaw);
      final email = 'tb.child.delete.$runId@trustbridge.local';
      final password = _passwordForRun(runId);

      await auth.signOut();
      UserCredential credential;
      try {
        credential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (error) {
        if (error.code == 'invalid-credential' ||
            error.code == 'user-not-found' ||
            error.code == 'wrong-password') {
          credential = await auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          rethrow;
        }
      }

      final user = credential.user;
      expect(user, isNotNull);
      final parentId = user!.uid;
      await firestoreService.ensureParentProfile(
        parentId: parentId,
        phoneNumber: user.phoneNumber,
      );
      await firestoreService.completeOnboarding(parentId);

      final child = await firestoreService.addChild(
        parentId: parentId,
        nickname: 'Delete Probe $runId',
        ageBand: AgeBand.middle,
      );
      final deviceId = await pairing.getOrCreateDeviceId();
      final pairingCode = _pairingCodeForRun(runId);

      await firestore.collection('pairing_codes').doc(pairingCode).set(
        <String, dynamic>{
          'code': pairingCode,
          'childId': child.id,
          'parentId': parentId,
          'createdAt': Timestamp.now(),
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(minutes: 15)),
          ),
          'used': false,
        },
      );

      final pairingResult =
          await pairing.validateAndPair(pairingCode, deviceId);
      expect(
        pairingResult.success,
        isTrue,
        reason: 'Child pairing failed: ${pairingResult.error}',
      );

      await firestore.collection('children').doc(child.id).set(
        <String, dynamic>{
          'parentId': parentId,
          'deviceIds': FieldValue.arrayUnion(<String>[deviceId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChildStatusScreen(
              firestore: firestore,
              parentId: parentId,
              childId: child.id,
            ),
          ),
          routes: <String, WidgetBuilder>{
            '/child/setup': (_) => const Scaffold(
                  body: Center(child: Text('child setup')),
                ),
          },
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final permissionGranted = await _ensureVpnPermission(vpn);
      if (!permissionGranted) {
        print(
          '[DELETE_CLEANUP] VPN permission unavailable. '
          'Proceeding with pairing-clear verification only.',
        );
      }

      if (permissionGranted) {
        await firestoreService.updateChild(
          parentId: parentId,
          child: child.copyWith(
            policy: child.policy.copyWith(
              blockedCategories: const <String>[],
              blockedDomains: const <String>['instagram.com'],
              schedules: const <Schedule>[],
            ),
            clearPausedUntil: true,
          ),
        );

        final started = await _waitUntil(
          predicate: () async => (await vpn.getStatus()).isRunning,
          timeout: const Duration(seconds: 30),
        );
        expect(started, isTrue, reason: 'VPN did not start before delete.');
      }

      final timer = Stopwatch()..start();
      await firestoreService.deleteChild(
        parentId: parentId,
        childId: child.id,
      );

      final stoppedWithinThirtySeconds = permissionGranted
          ? await _waitUntil(
              predicate: () async {
                final status = await vpn.getStatus();
                return !status.isRunning;
              },
              timeout: const Duration(seconds: 30),
            )
          : true;

      final childUnpairedMessageVisible = await _waitForAnyText(
        tester: tester,
        candidates: const <String>[
          'This phone is no longer paired.',
          'Child profile not found.',
          'Setup is incomplete.',
        ],
        timeout: const Duration(seconds: 30),
      );

      final elapsedMs = timer.elapsedMilliseconds;
      print(
        '[DELETE_CLEANUP] elapsedMs=$elapsedMs '
        'stopped=$stoppedWithinThirtySeconds '
        'unpairedUi=$childUnpairedMessageVisible',
      );

      if (permissionGranted) {
        expect(
          stoppedWithinThirtySeconds,
          isTrue,
          reason: 'VPN still running 30s after child profile deletion.',
        );
      }
      expect(
        childUnpairedMessageVisible,
        isTrue,
        reason:
            'Child UI did not show unpaired state within 30s after deletion.',
      );

      // Ensure cleanup happens for the next manual/device run.
      await pairing.clearLocalPairing();
      await vpn.stopVpn();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

String _normalizeRunId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isNotEmpty) {
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  }
  return DateTime.now().millisecondsSinceEpoch.toString();
}

String _passwordForRun(String runId) {
  final seed =
      runId.length >= 8 ? runId.substring(0, 8) : runId.padRight(8, '0');
  return 'Tb!${seed}Aa1';
}

String _pairingCodeForRun(String runId) {
  final digits = runId.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return '000000';
  }
  if (digits.length >= 6) {
    return digits.substring(digits.length - 6);
  }
  return digits.padLeft(6, '0');
}

Future<bool> _ensureVpnPermission(VpnService vpn) async {
  return vpn.hasVpnPermission();
}

Future<bool> _waitUntil({
  required Future<bool> Function() predicate,
  required Duration timeout,
  Duration interval = const Duration(seconds: 1),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed <= timeout) {
    if (await predicate()) {
      return true;
    }
    await Future<void>.delayed(interval);
  }
  return false;
}

Future<bool> _waitForAnyText({
  required WidgetTester tester,
  required List<String> candidates,
  required Duration timeout,
  Duration interval = const Duration(seconds: 1),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed <= timeout) {
    await tester.pump(interval);
    for (final candidate in candidates) {
      if (find.textContaining(candidate).evaluate().isNotEmpty) {
        return true;
      }
    }
  }
  return false;
}
