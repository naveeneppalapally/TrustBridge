// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';

const String _runIdRaw = String.fromEnvironment('TB_RUN_ID', defaultValue: '');
const String _childIdRaw = String.fromEnvironment('TB_CHILD_ID', defaultValue: '');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('inspect uninstall-related alerts/events', (tester) async {
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
    final credential = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      fail('Parent sign-in failed.');
    }
    final parentId = user.uid.trim();
    if (parentId.isEmpty) {
      fail('Parent uid is empty.');
    }

    final firestore = FirebaseFirestore.instance;
    final childSnapshot = await firestore.collection('children').doc(childId).get();
    if (!childSnapshot.exists) {
      fail('Child profile not found: $childId');
    }
    final childData = childSnapshot.data() ?? const <String, dynamic>{};
    final deviceIds = _readStringList(childData['deviceIds']);
    print(
      '[UNINSTALL_EVENT_INSPECT] parentId=$parentId childId=$childId '
      'deviceCount=${deviceIds.length}',
    );

    for (final deviceId in deviceIds) {
      try {
        final events = await firestore
            .collection('bypass_events')
            .doc(deviceId)
            .collection('events')
            .orderBy('timestampEpochMs', descending: true)
            .limit(5)
            .get();
        for (final eventDoc in events.docs) {
          final data = eventDoc.data();
          final type = (data['type'] as String?)?.trim() ?? '';
          if (type != 'vpn_disabled' && type != 'uninstall_attempt') {
            continue;
          }
          final epochMs = _readInt(data['timestampEpochMs']);
          print(
            '[UNINSTALL_EVENT] deviceId=$deviceId type=$type epochMs=$epochMs docId=${eventDoc.id}',
          );
        }
      } on FirebaseException catch (error) {
        print(
          '[UNINSTALL_EVENT] deviceId=$deviceId read_error=${error.code}',
        );
      }
    }

    print(
      '[UNINSTALL_NOTIFICATION] notification_queue is write-only in security rules; '
      'direct parent read is not permitted.',
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

List<String> _readStringList(Object? rawValue) {
  if (rawValue is! List) {
    return const <String>[];
  }
  return rawValue
      .map((entry) => entry?.toString().trim() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

int _readInt(Object? rawValue) {
  if (rawValue is int) {
    return rawValue;
  }
  if (rawValue is num) {
    return rawValue.toInt();
  }
  return 0;
}
