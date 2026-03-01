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

  testWidgets('inspect child device records', (tester) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final runId = _normalizeRunId(_runIdRaw);
    if (runId.isEmpty) {
      fail('TB_RUN_ID is required.');
    }
    final email = 'tb.schedule.$runId@trustbridge.local';
    final password = _passwordForRun(runId);
    final childIdOverride = _childIdRaw.trim();

    final auth = FirebaseAuth.instance;
    await auth.signOut();
    final credential = await _signInOrCreate(
      auth: auth,
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      fail('Failed to sign in parent user.');
    }
    final parentId = user.uid.trim();
    if (parentId.isEmpty) {
      fail('Signed-in parentId is empty.');
    }

    final firestore = FirebaseFirestore.instance;
    DocumentSnapshot<Map<String, dynamic>>? childSnapshot;
    if (childIdOverride.isNotEmpty) {
      final direct = await firestore.collection('children').doc(childIdOverride).get();
      if (direct.exists) {
        childSnapshot = direct;
      }
    }

    childSnapshot ??= await _findLatestChildForParent(
      firestore: firestore,
      parentId: parentId,
    );
    if (childSnapshot == null || !childSnapshot.exists) {
      fail('No child profile found for parent $parentId.');
    }

    final childId = childSnapshot.id;
    final childData = childSnapshot.data() ?? const <String, dynamic>{};
    final deviceIds = _readStringList(childData['deviceIds']);
    final updatedAt = _readDateTime(childData['updatedAt']);
    final pausedUntil = _readDateTime(childData['pausedUntil']);
    final manualMode = childData['manualMode'];

    debugPrint(
      '[CHILD_INSPECT] parentId=$parentId childId=$childId '
      'deviceIds=${deviceIds.join(",")} '
      'updatedAt=${updatedAt?.toIso8601String() ?? "null"} '
      'pausedUntil=${pausedUntil?.toIso8601String() ?? "null"} '
      'manualMode=$manualMode',
    );

    final devicesSnapshot = await firestore
        .collection('children')
        .doc(childId)
        .collection('devices')
        .get();
    for (final doc in devicesSnapshot.docs) {
      final data = doc.data();
      final fcmToken = (data['fcmToken'] as String?)?.trim();
      final model = (data['model'] as String?)?.trim();
      final osVersion = (data['osVersion'] as String?)?.trim();
      debugPrint(
        '[CHILD_INSPECT_DEVICE] id=${doc.id} '
        'hasFcm=${fcmToken != null && fcmToken.isNotEmpty} '
        'model=${model ?? ""} os=${osVersion ?? ""}',
      );
    }
  });
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
    final code = error.code.trim().toLowerCase();
    if (code != 'user-not-found' && code != 'invalid-credential') {
      rethrow;
    }
    try {
      return await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (createError) {
      if (createError.code.trim().toLowerCase() != 'email-already-in-use') {
        rethrow;
      }
      return auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    }
  }
}

Future<DocumentSnapshot<Map<String, dynamic>>?> _findLatestChildForParent({
  required FirebaseFirestore firestore,
  required String parentId,
}) async {
  final byUpdated = await firestore
      .collection('children')
      .where('parentId', isEqualTo: parentId)
      .orderBy('updatedAt', descending: true)
      .limit(1)
      .get();
  if (byUpdated.docs.isNotEmpty) {
    return byUpdated.docs.first;
  }

  final fallback = await firestore
      .collection('children')
      .where('parentId', isEqualTo: parentId)
      .limit(1)
      .get();
  if (fallback.docs.isNotEmpty) {
    return fallback.docs.first;
  }
  return null;
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
  final values = rawValue
      .map((entry) => entry?.toString().trim() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return values;
}

DateTime? _readDateTime(Object? rawValue) {
  if (rawValue is Timestamp) {
    return rawValue.toDate();
  }
  if (rawValue is DateTime) {
    return rawValue;
  }
  return null;
}
