import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/services/notification_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';

const String _emulatorHost = String.fromEnvironment(
  'TB_DIAG_EMULATOR_HOST',
  defaultValue: '',
);
const int _authPort = int.fromEnvironment(
  'TB_DIAG_AUTH_PORT',
  defaultValue: 9099,
);
const int _firestorePort = int.fromEnvironment(
  'TB_DIAG_FIRESTORE_PORT',
  defaultValue: 8080,
);
const String _parentEmail = String.fromEnvironment(
  'TB_DIAG_PARENT_EMAIL',
  defaultValue: '',
);
const String _parentPassword = String.fromEnvironment(
  'TB_DIAG_PARENT_PASSWORD',
  defaultValue: '',
);
const String _providedChildId = String.fromEnvironment(
  'TB_DIAG_CHILD_ID',
  defaultValue: '',
);
const String _childNickname = String.fromEnvironment(
  'TB_DIAG_CHILD_NICKNAME',
  defaultValue: 'Diagnostic Child',
);
const bool _autoCreateParent = bool.fromEnvironment(
  'TB_DIAG_AUTO_CREATE_PARENT',
  defaultValue: false,
);
const bool _autoCreateChild = bool.fromEnvironment(
  'TB_DIAG_AUTO_CREATE_CHILD',
  defaultValue: true,
);

bool _initialized = false;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'child mode same-account connection diagnostic',
    (WidgetTester tester) async {
      await _initializeFirebase();

      final email = _parentEmail.trim();
      final password = _parentPassword.trim();
      if (email.isEmpty || password.isEmpty) {
        fail(
          'Missing credentials. Provide TB_DIAG_PARENT_EMAIL and '
          'TB_DIAG_PARENT_PASSWORD dart defines.',
        );
      }

      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;
      await auth.signOut();

      UserCredential credential;
      try {
        credential = await auth
            .signInWithEmailAndPassword(
              email: email,
              password: password,
            )
            .timeout(const Duration(seconds: 30));
      } on FirebaseAuthException catch (error) {
        if (error.code != 'user-not-found' ||
            !_autoCreateParent ||
            _emulatorHost.trim().isEmpty) {
          rethrow;
        }
        credential = await auth
            .createUserWithEmailAndPassword(
              email: email,
              password: password,
            )
            .timeout(const Duration(seconds: 30));
      }

      final parentId = credential.user?.uid.trim() ?? '';
      if (parentId.isEmpty) {
        fail('Parent sign-in succeeded but Firebase UID is missing.');
      }
      debugPrint('[DIAG] Signed in parent UID: $parentId');

      final childRef = await _resolveChildRef(
        firestore: firestore,
        parentId: parentId,
      );
      final childId = childRef.id;
      debugPrint('[DIAG] Target childId: $childId');

      final childSnapshot = await childRef.get();
      if (!childSnapshot.exists) {
        fail('[DIAG] Child profile not found at children/$childId');
      }
      final childData = childSnapshot.data() ?? const <String, dynamic>{};
      final childParentId = (childData['parentId'] as String?)?.trim();
      if (childParentId != parentId) {
        fail(
          '[DIAG] Child parentId mismatch. '
          'expected=$parentId actual=${childParentId ?? 'null'}',
        );
      }
      debugPrint('[DIAG] Child profile read OK: children/$childId');

      final pairingService = PairingService();
      final deviceId = await pairingService.getOrCreateDeviceId();
      debugPrint('[DIAG] Local deviceId: $deviceId');

      final childDeviceRef = childRef.collection('devices').doc(deviceId);
      await childDeviceRef.set(
        <String, dynamic>{
          'parentId': parentId,
          'model': 'Diagnostic Emulator',
          'osVersion': Platform.operatingSystemVersion,
          'pairedAt': FieldValue.serverTimestamp(),
          'diagnosticUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await childRef.set(
        <String, dynamic>{
          'parentId': parentId,
          'deviceIds': FieldValue.arrayUnion(<String>[deviceId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final childDeviceSnapshot = await childDeviceRef.get();
      if (!childDeviceSnapshot.exists) {
        fail(
          '[DIAG] Device registration write failed at '
          'children/$childId/devices/$deviceId',
        );
      }
      final childDeviceData =
          childDeviceSnapshot.data() ?? const <String, dynamic>{};
      debugPrint(
        '[DIAG] Device registration OK: children/$childId/devices/$deviceId '
        'fields=${childDeviceData.keys.toList()}',
      );

      final rootDeviceRef = firestore.collection('devices').doc(deviceId);
      await rootDeviceRef.set(
        <String, dynamic>{
          'deviceId': deviceId,
          'parentId': parentId,
          'childId': childId,
          'lastSeen': FieldValue.serverTimestamp(),
          'lastSeenEpochMs': DateTime.now().millisecondsSinceEpoch,
          'vpnActive': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      final rootDeviceSnapshot = await rootDeviceRef.get();
      if (!rootDeviceSnapshot.exists) {
        fail(
            '[DIAG] Root device heartbeat doc write failed at devices/$deviceId');
      }
      debugPrint('[DIAG] Root heartbeat doc write OK: devices/$deviceId');

      final policyRaw = childData['policy'];
      if (policyRaw is! Map) {
        fail(
          '[DIAG] Child policy is missing or malformed in children/$childId.',
        );
      }
      debugPrint(
        '[DIAG] Child policy field is readable with keys: '
        '${policyRaw.keys.map((key) => key.toString()).toList()}',
      );

      final policyCollection = await childRef.collection('policy').limit(1).get();
      debugPrint(
        '[DIAG] children/$childId/policy subcollection docs: '
        '${policyCollection.docs.length}',
      );

      String? token;
      try {
        token = await NotificationService()
            .getToken()
            .timeout(const Duration(seconds: 15));
      } catch (error) {
        debugPrint(
            '[DIAG] Failed to fetch FCM token on child app start: $error');
      }

      final normalizedToken = token?.trim() ?? '';
      if (normalizedToken.isEmpty) {
        debugPrint(
          '[DIAG] FCM token unavailable in this environment; '
          'token write check skipped.',
        );
      } else {
        await childDeviceRef.set(
          <String, dynamic>{
            'parentId': parentId,
            'fcmToken': normalizedToken,
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        final tokenSnapshot = await childDeviceRef.get();
        final storedToken =
            (tokenSnapshot.data()?['fcmToken'] as String?)?.trim();
        if (storedToken != normalizedToken) {
          fail(
            '[DIAG] FCM token write mismatch at children/$childId/devices/$deviceId. '
            'expected=${normalizedToken.length} chars, '
            'actual=${storedToken?.length ?? 0} chars',
          );
        }
        debugPrint(
          '[DIAG] FCM token write OK: children/$childId/devices/$deviceId/fcmToken',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _initializeFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (_initialized) {
    return;
  }

  final host = _emulatorHost.trim();
  if (host.isNotEmpty) {
    FirebaseAuth.instance.useAuthEmulator(host, _authPort);
    final firestore = FirebaseFirestore.instance;
    firestore.useFirestoreEmulator(host, _firestorePort);
    firestore.settings = const Settings(persistenceEnabled: false);
    debugPrint(
      '[DIAG] Using Firebase emulators auth=$host:$_authPort '
      'firestore=$host:$_firestorePort',
    );
  } else {
    debugPrint('[DIAG] Using live Firebase project configuration.');
  }

  _initialized = true;
}

Future<DocumentReference<Map<String, dynamic>>> _resolveChildRef({
  required FirebaseFirestore firestore,
  required String parentId,
}) async {
  final provided = _providedChildId.trim();
  if (provided.isNotEmpty) {
    final ref = firestore.collection('children').doc(provided);
    final snapshot = await ref.get();
    if (snapshot.exists || !_autoCreateChild) {
      return ref;
    }
    await _createChildDocument(
      ref: ref,
      parentId: parentId,
    );
    return ref;
  }

  final query = await firestore
      .collection('children')
      .where('parentId', isEqualTo: parentId)
      .limit(1)
      .get();
  if (query.docs.isNotEmpty) {
    return query.docs.first.reference;
  }

  if (!_autoCreateChild) {
    fail(
      '[DIAG] No child profile found for parent $parentId and '
      'TB_DIAG_AUTO_CREATE_CHILD=false.',
    );
  }

  final ref = firestore.collection('children').doc(
        'diag_child_${DateTime.now().millisecondsSinceEpoch}',
      );
  await _createChildDocument(
    ref: ref,
    parentId: parentId,
  );
  return ref;
}

Future<void> _createChildDocument({
  required DocumentReference<Map<String, dynamic>> ref,
  required String parentId,
}) async {
  await ref.set(<String, dynamic>{
    'nickname': _childNickname.trim().isEmpty
        ? 'Diagnostic Child'
        : _childNickname.trim(),
    'ageBand': '10-13',
    'deviceIds': <String>[],
    'policy': <String, dynamic>{
      'blockedCategories': <String>[],
      'blockedDomains': <String>[],
      'safeSearchEnabled': true,
      'schedules': <Map<String, dynamic>>[],
    },
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'parentId': parentId,
  });
  debugPrint('[DIAG] Created diagnostic child profile at ${ref.path}');
}
