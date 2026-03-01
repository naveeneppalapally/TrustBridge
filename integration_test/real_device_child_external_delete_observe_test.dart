import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/screens/child/child_status_screen.dart';
import 'package:trustbridge_app/services/pairing_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

const String _parentEmail = String.fromEnvironment(
  'TB_PARENT_EMAIL',
  defaultValue: '',
);
const String _parentPassword = String.fromEnvironment(
  'TB_PARENT_PASSWORD',
  defaultValue: '',
);
const String _pairingCode = String.fromEnvironment(
  'TB_PAIRING_CODE',
  defaultValue: '',
);
const String _blockedDomain = String.fromEnvironment(
  'TB_BLOCKED_DOMAIN',
  defaultValue: 'instagram.com',
);
const int _waitForDeleteSeconds = int.fromEnvironment(
  'TB_WAIT_FOR_DELETE_SECONDS',
  defaultValue: 180,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'child observes external parent delete cleanup',
    (tester) async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final email = _parentEmail.trim();
      final password = _parentPassword.trim();
      final pairingCode = _pairingCode.trim();
      if (email.isEmpty || password.isEmpty || pairingCode.isEmpty) {
        fail(
          'TB_PARENT_EMAIL, TB_PARENT_PASSWORD, and TB_PAIRING_CODE are required.',
        );
      }

      final auth = FirebaseAuth.instance;
      await auth.signOut();
      final credential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null || user.uid.trim().isEmpty) {
        fail('Parent-account sign-in failed on child device.');
      }

      final pairing = PairingService();
      final deviceId = await pairing.getOrCreateDeviceId();
      final pairResult = await pairing.validateAndPair(pairingCode, deviceId);
      if (!pairResult.success) {
        final recovered = await pairing.recoverPairingFromCloud();
        if (recovered == null) {
          fail(
            'Pairing failed and recovery could not restore context. '
            'error=${pairResult.error}',
          );
        }
      }

      final parentId = (await pairing.getPairedParentId())?.trim() ?? '';
      final childId = (await pairing.getPairedChildId())?.trim() ?? '';
      if (parentId.isEmpty || childId.isEmpty) {
        fail('Paired parent/child IDs are missing after pairing attempt.');
      }

      final vpn = VpnService();
      var permissionGranted = await vpn.hasVpnPermission();
      if (!permissionGranted) {
        final requested = await vpn.requestPermission();
        debugPrint('[EXTERNAL_DELETE_OBSERVE] requestPermission returned=$requested');
        final granted = await _waitUntil(
          predicate: () => vpn.hasVpnPermission(),
          timeout: const Duration(seconds: 45),
          interval: const Duration(milliseconds: 500),
        );
        permissionGranted = granted;
      }
      if (!permissionGranted) {
        fail(
          'VPN permission not granted. Approve Android VPN consent and retry.',
        );
      }

      final normalizedDomain = _blockedDomain.trim().toLowerCase();
      final started = await vpn.startVpn(
        blockedDomains: <String>[normalizedDomain],
      );
      if (!started) {
        fail('startVpn returned false.');
      }
      await vpn.updateFilterRules(
        blockedCategories: const <String>[],
        blockedDomains: <String>[normalizedDomain],
      );

      final runningBeforeDelete = await _waitUntil(
        predicate: () async => (await vpn.getStatus()).isRunning,
        timeout: const Duration(seconds: 30),
      );
      if (!runningBeforeDelete) {
        fail('VPN was not running before waiting for parent delete.');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChildStatusScreen(
              parentId: parentId,
              childId: childId,
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

      debugPrint(
        '[EXTERNAL_DELETE_OBSERVE] ready '
        'parentId=$parentId childId=$childId deviceId=$deviceId running=true',
      );

      final firestore = FirebaseFirestore.instance;
      final waitStart = DateTime.now();
      final childDeleted = await _waitUntil(
        predicate: () async {
          try {
            final snapshot =
                await firestore.collection('children').doc(childId).get();
            return !snapshot.exists;
          } on FirebaseException catch (error) {
            final code = error.code.trim().toLowerCase();
            if (code == 'permission-denied' || code == 'unauthenticated') {
              // After parent deletion, child session can lose read access first.
              return true;
            }
            rethrow;
          }
        },
        timeout: const Duration(seconds: _waitForDeleteSeconds),
      );
      if (!childDeleted) {
        fail(
          'Timed out waiting for parent to delete child profile '
          '(childId=$childId).',
        );
      }
      final deleteDetectedAt = DateTime.now();

      final vpnStopped = await _waitUntil(
        predicate: () async => !(await vpn.getStatus()).isRunning,
        timeout: const Duration(seconds: 30),
      );

      final localPairingCleared = await _waitUntil(
        predicate: () async {
          final parent = (await pairing.getPairedParentId())?.trim() ?? '';
          final child = (await pairing.getPairedChildId())?.trim() ?? '';
          return parent.isEmpty && child.isEmpty;
        },
        timeout: const Duration(seconds: 30),
      );

      final childUnpairedMessageVisible = await _waitForAnyText(
        tester: tester,
        candidates: const <String>[
          'This phone is no longer paired.',
          'Child profile not found.',
          'Setup is incomplete.',
        ],
        timeout: const Duration(seconds: 30),
      );

      final waitForDeleteMs = deleteDetectedAt.difference(waitStart).inMilliseconds;
      debugPrint(
        '[EXTERNAL_DELETE_OBSERVE] '
        'deleteDetectedMs=$waitForDeleteMs '
        'vpnStopped=$vpnStopped '
        'localPairingCleared=$localPairingCleared '
        'unpairedUi=$childUnpairedMessageVisible',
      );

      expect(
        vpnStopped,
        isTrue,
        reason: 'VPN did not stop within 30s after child deletion.',
      );
      expect(
        localPairingCleared,
        isTrue,
        reason: 'Local pairing IDs were not cleared within 30s.',
      );
      expect(
        childUnpairedMessageVisible,
        isTrue,
        reason: 'Child UI did not show unpaired message within 30s.',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
    semanticsEnabled: false,
  );
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
