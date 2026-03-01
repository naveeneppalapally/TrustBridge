import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:flutter/foundation.dart';

const String _runIdRaw = String.fromEnvironment('TB_RUN_ID', defaultValue: '');
const String _childIdRaw = String.fromEnvironment('TB_CHILD_ID', defaultValue: '');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('issue pairing code for existing child', (tester) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final runId = _normalizeRunId(_runIdRaw);
    final childId = _childIdRaw.trim();
    if (runId.isEmpty) {
      fail('TB_RUN_ID is required.');
    }
    if (childId.isEmpty) {
      fail('TB_CHILD_ID is required.');
    }

    final email = 'tb.schedule.$runId@trustbridge.local';
    final password = _passwordForRun(runId);
    final auth = FirebaseAuth.instance;
    await auth.signOut();
    final signInWatch = Stopwatch()..start();
    final credential = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    signInWatch.stop();
    final user = credential.user;
    if (user == null) {
      fail('Parent sign-in failed.');
    }
    final parentId = user.uid.trim();
    if (parentId.isEmpty) {
      fail('Parent uid is empty.');
    }

    final code = _generateCode();
    final writeWatch = Stopwatch()..start();
    await FirebaseFirestore.instance.collection('pairing_codes').doc(code).set(
      <String, dynamic>{
        'code': code,
        'childId': childId,
        'parentId': parentId,
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 15)),
        ),
        'used': false,
      },
    );
    writeWatch.stop();

    debugPrint(
      '[PAIRING_CODE_ISSUE] runId=$runId parentId=$parentId childId=$childId pairingCode=$code',
    );
    debugPrint(
      '[PAIRING_CODE_ISSUE_TIMING] signInMs=${signInWatch.elapsedMilliseconds} '
      'writeCodeMs=${writeWatch.elapsedMilliseconds}',
    );
  });
}

String _normalizeRunId(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _passwordForRun(String runId) {
  final seed = runId.length >= 8 ? runId.substring(0, 8) : runId.padRight(8, '0');
  return 'Tb!${seed}Aa1';
}

String _generateCode() {
  final digits = DateTime.now().millisecondsSinceEpoch.toString();
  return digits.substring(digits.length - 6);
}
