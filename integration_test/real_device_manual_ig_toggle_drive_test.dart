import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:flutter/foundation.dart';

const String _runIdRaw = String.fromEnvironment('TB_RUN_ID', defaultValue: '');
const String _pairingCodeRaw = String.fromEnvironment(
  'TB_PAIRING_CODE',
  defaultValue: '',
);
const int _phaseSeconds = int.fromEnvironment(
  'TB_PHASE_SECONDS',
  defaultValue: 30,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real-device manual instagram social toggle drive',
    (tester) async {
      final runId = _normalizeRunId(_runIdRaw);
      final pairingCode = _pairingCodeRaw.trim();
      if (runId.isEmpty) {
        fail('TB_RUN_ID is required.');
      }
      if (pairingCode.isEmpty) {
        fail('TB_PAIRING_CODE is required.');
      }

      await _initFirebase();

      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;
      final service = FirestoreService(firestore: firestore);
      final email = _parentEmailForRun(runId);
      final password = _parentPasswordForRun(runId);

      await auth.signOut();
      final credential = await _signInOrCreate(
        auth: auth,
        email: email,
        password: password,
      );
      final signedInUser = credential.user;
      if (signedInUser == null) {
        fail('Parent sign-in failed.');
      }
      final signedInParentId = signedInUser.uid.trim();
      if (signedInParentId.isEmpty) {
        fail('Signed-in parent uid is empty.');
      }

      final pairingSnapshot =
          await firestore.collection('pairing_codes').doc(pairingCode).get();
      if (!pairingSnapshot.exists) {
        fail('Pairing code not found: $pairingCode');
      }
      final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
      final parentId =
          (pairingData['parentId'] as String?)?.trim() ?? signedInParentId;
      final childId = (pairingData['childId'] as String?)?.trim() ?? '';
      if (parentId.isEmpty || childId.isEmpty) {
        fail('Pairing code is missing parentId or childId.');
      }

      debugPrint(
        '[IG_DRIVE] runId=$runId parentId=$parentId childId=$childId '
        'phaseSeconds=$_phaseSeconds',
      );

      await _applySocialPolicy(
        service: service,
        parentId: parentId,
        childId: childId,
        blockSocial: false,
      );
      debugPrint('[IG_DRIVE] phase=off_applied epochMs=${_nowMs()}');
      await Future<void>.delayed(const Duration(seconds: _phaseSeconds));

      await _applySocialPolicy(
        service: service,
        parentId: parentId,
        childId: childId,
        blockSocial: true,
      );
      debugPrint('[IG_DRIVE] phase=on_applied epochMs=${_nowMs()}');
      await Future<void>.delayed(const Duration(seconds: _phaseSeconds));

      await _applySocialPolicy(
        service: service,
        parentId: parentId,
        childId: childId,
        blockSocial: false,
      );
      debugPrint('[IG_DRIVE] phase=off2_applied epochMs=${_nowMs()}');
      await Future<void>.delayed(const Duration(seconds: 8));
    },
    timeout: const Timeout(Duration(minutes: 8)),
    semanticsEnabled: false,
  );
}

Future<void> _initFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
}

Future<void> _applySocialPolicy({
  required FirestoreService service,
  required String parentId,
  required String childId,
  required bool blockSocial,
}) async {
  final latest = await service.getChild(parentId: parentId, childId: childId);
  if (latest == null) {
    fail('Child not found while applying social policy: $childId');
  }

  final updatedChild = latest.copyWith(
    policy: latest.policy.copyWith(
      blockedCategories:
          blockSocial ? const <String>['social-networks'] : const <String>[],
      blockedDomains: const <String>[],
      schedules: const <Schedule>[],
    ),
    clearManualMode: true,
    clearPausedUntil: true,
  );

  await service.updateChild(parentId: parentId, child: updatedChild);
  await service.setChildManualMode(
    parentId: parentId,
    childId: childId,
    mode: null,
  );
  await service.setChildPause(
    parentId: parentId,
    childId: childId,
    pausedUntil: null,
  );
}

Future<UserCredential> _signInOrCreate({
  required FirebaseAuth auth,
  required String email,
  required String password,
}) async {
  try {
    return await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  } on FirebaseAuthException catch (error) {
    if (error.code == 'user-not-found' || error.code == 'invalid-credential') {
      return await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    }
    rethrow;
  }
}

String _normalizeRunId(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _parentEmailForRun(String runId) {
  return 'tb.schedule.$runId@trustbridge.local';
}

String _parentPasswordForRun(String runId) {
  final seed =
      runId.length >= 8 ? runId.substring(0, 8) : runId.padRight(8, '0');
  return 'Tb!${seed}Aa1';
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;
