// ignore_for_file: avoid_print

import 'dart:async';

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

const String _roleRaw = String.fromEnvironment('TB_ROLE', defaultValue: '');
const String _runIdRaw = String.fromEnvironment('TB_RUN_ID', defaultValue: '');
const String _pairingCodeOverride = String.fromEnvironment(
  'TB_PAIRING_CODE',
  defaultValue: '',
);
const String _opRaw = String.fromEnvironment('TB_OP', defaultValue: '');
const int _watchSeconds = int.fromEnvironment('TB_WATCH_SECONDS', defaultValue: 900);
const int _pollMs = int.fromEnvironment('TB_POLL_MS', defaultValue: 1000);

const String _domainInstagram = 'instagram.com';
const String _domainYoutube = 'youtube.com';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real-device offline resilience role runner',
    (tester) async {
      final role = _roleRaw.trim().toLowerCase();
      final runId = _normalizeRunId(_runIdRaw);
      if (role.isEmpty) {
        fail('TB_ROLE is required: setup | parent_apply | child_watch');
      }
      if (runId.isEmpty) {
        fail('TB_RUN_ID is required.');
      }

      await _initFirebase();
      switch (role) {
        case 'setup':
          await _runSetup(runId);
          break;
        case 'parent_apply':
          await _runParentApply(runId);
          break;
        case 'child_watch':
          await _runChildWatch(runId, tester);
          break;
        default:
          fail('Unsupported TB_ROLE value: $role');
      }
    },
    timeout: const Timeout(Duration(minutes: 40)),
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

Future<void> _runSetup(String runId) async {
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
  final user = credential.user;
  if (user == null) {
    fail('Setup sign-in failed.');
  }
  final parentId = user.uid.trim();
  if (parentId.isEmpty) {
    fail('Setup parentId is empty.');
  }

  await service.ensureParentProfile(
    parentId: parentId,
    phoneNumber: user.phoneNumber,
  );
  await service.completeOnboarding(parentId);

  final child = await _pickExistingOrCreateChild(
    firestoreService: service,
    parentId: parentId,
    nickname: 'Schedule Child $runId',
  );

  await _setPolicy(
    firestoreService: service,
    parentId: parentId,
    childId: child.id,
    blockedCategories: const <String>[],
    blockedDomains: const <String>[],
  );
  await service.setChildManualMode(
    parentId: parentId,
    childId: child.id,
    mode: null,
  );
  await service.setChildPause(
    parentId: parentId,
    childId: child.id,
    pausedUntil: null,
  );

  final pairingService = PairingService(
    firestore: firestore,
    currentUserIdResolver: () => parentId,
  );
  final pairingCode = await pairingService.generatePairingCode(child.id);
  print(
    '[OFFLINE_SETUP] runId=$runId parentId=$parentId childId=${child.id} '
    'email=$email pairingCode=$pairingCode',
  );
}

Future<void> _runParentApply(String runId) async {
  final op = _opRaw.trim().toLowerCase();
  if (op.isEmpty) {
    fail('TB_OP is required for parent_apply.');
  }

  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final service = FirestoreService(firestore: firestore);
  final email = _parentEmailForRun(runId);
  final password = _parentPasswordForRun(runId);
  final pairingCode = _resolvePairingCode(runId);

  await auth.signOut();
  final credential = await _signInOrCreate(
    auth: auth,
    email: email,
    password: password,
  );
  if (credential.user == null) {
    fail('parent_apply sign-in failed.');
  }

  final pairingSnapshot =
      await firestore.collection('pairing_codes').doc(pairingCode).get();
  if (!pairingSnapshot.exists) {
    fail('Pairing code not found for parent_apply. Run setup first.');
  }
  final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
  final parentId = (pairingData['parentId'] as String?)?.trim() ?? '';
  final childId = (pairingData['childId'] as String?)?.trim() ?? '';
  if (parentId.isEmpty || childId.isEmpty) {
    fail('Pairing code is missing parentId or childId.');
  }

  await _applyParentOperation(
    firestoreService: service,
    parentId: parentId,
    childId: childId,
    op: op,
  );

  final savedAtMs = DateTime.now().millisecondsSinceEpoch;
  print(
    '[OFFLINE_PARENT] op=$op savedAtMs=$savedAtMs parentId=$parentId '
    'childId=$childId',
  );
}

Future<void> _runChildWatch(String runId, WidgetTester tester) async {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final pairing = PairingService();
  final vpn = VpnService();
  final email = _parentEmailForRun(runId);
  final password = _parentPasswordForRun(runId);
  final pairingCode = _resolvePairingCode(runId);

  await auth.signOut();
  final credential = await _signInOrCreate(
    auth: auth,
    email: email,
    password: password,
  );
  if (credential.user == null) {
    fail('child_watch sign-in failed.');
  }

  final pairingSnapshot =
      await firestore.collection('pairing_codes').doc(pairingCode).get();
  if (!pairingSnapshot.exists) {
    fail('Pairing code not found for child_watch. Run setup first.');
  }
  final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
  final parentId = (pairingData['parentId'] as String?)?.trim() ?? '';
  final childId = (pairingData['childId'] as String?)?.trim() ?? '';
  if (parentId.isEmpty || childId.isEmpty) {
    fail('Pairing code is missing parentId or childId.');
  }

  final deviceId = await pairing.getOrCreateDeviceId();
  final pairResult = await pairing.validateAndPair(pairingCode, deviceId);
  if (!pairResult.success) {
    final recovered = await pairing.recoverPairingFromCloud();
    if (recovered == null ||
        recovered.parentId.trim() != parentId ||
        recovered.childId.trim() != childId) {
      fail(
        'Child pairing failed and recovery did not restore context. '
        'error=${pairResult.error}',
      );
    }
  }

  final hasPermission = await vpn.hasVpnPermission();
  if (!hasPermission) {
    fail(
      'VPN permission missing on child device. '
      'Human action required: open TrustBridge and grant VPN permission.',
    );
  }

  await vpn.startVpn(
    blockedCategories: const <String>[],
    blockedDomains: const <String>[],
  );
  await vpn.updateFilterRules(
    blockedCategories: const <String>[],
    blockedDomains: const <String>[],
    temporaryAllowedDomains: const <String>[],
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChildStatusScreen(
          parentId: parentId,
          childId: childId,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));

  print(
    '[OFFLINE_WATCH] ready runId=$runId parentId=$parentId childId=$childId '
    'deviceId=$deviceId',
  );

  final watchUntil = DateTime.now().add(const Duration(seconds: _watchSeconds));
  while (DateTime.now().isBefore(watchUntil)) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final status = await vpn.getStatus();
    final insta = await vpn.evaluateDomainPolicy(_domainInstagram);
    final youtube = await vpn.evaluateDomainPolicy(_domainYoutube);
    print(
      '[OFFLINE_WATCH] tsMs=$nowMs running=${status.isRunning} '
      'cats=${status.blockedCategoryCount} domains=${status.blockedDomainCount} '
      'insta=${insta.blocked} youtube=${youtube.blocked}',
    );
    await Future<void>.delayed(const Duration(milliseconds: _pollMs));
    await tester.pump();
  }

  print('[OFFLINE_WATCH] done');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _applyParentOperation({
  required FirestoreService firestoreService,
  required String parentId,
  required String childId,
  required String op,
}) async {
  switch (op) {
    case 'block_instagram':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>[],
        blockedDomains: const <String>[_domainInstagram],
      );
      await firestoreService.setChildManualMode(
        parentId: parentId,
        childId: childId,
        mode: null,
      );
      await firestoreService.setChildPause(
        parentId: parentId,
        childId: childId,
        pausedUntil: null,
      );
      return;
    case 'block_youtube':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>[],
        blockedDomains: const <String>[_domainYoutube],
      );
      await firestoreService.setChildManualMode(
        parentId: parentId,
        childId: childId,
        mode: null,
      );
      await firestoreService.setChildPause(
        parentId: parentId,
        childId: childId,
        pausedUntil: null,
      );
      return;
    case 'unblock_all':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>[],
        blockedDomains: const <String>[],
      );
      await firestoreService.setChildManualMode(
        parentId: parentId,
        childId: childId,
        mode: null,
      );
      await firestoreService.setChildPause(
        parentId: parentId,
        childId: childId,
        pausedUntil: null,
      );
      return;
    default:
      throw StateError('Unsupported TB_OP value: $op');
  }
}

Future<void> _setPolicy({
  required FirestoreService firestoreService,
  required String parentId,
  required String childId,
  required List<String> blockedCategories,
  required List<String> blockedDomains,
}) async {
  final latest = await firestoreService.getChild(
    parentId: parentId,
    childId: childId,
  );
  if (latest == null) {
    throw StateError('Child not found while setting policy: $childId');
  }
  await firestoreService.updateChild(
    parentId: parentId,
    child: latest.copyWith(
      policy: latest.policy.copyWith(
        blockedCategories: blockedCategories,
        blockedDomains: blockedDomains,
        schedules: const <Schedule>[],
      ),
    ),
  );
}

Future<ChildProfile> _pickExistingOrCreateChild({
  required FirestoreService firestoreService,
  required String parentId,
  required String nickname,
}) async {
  final existing = await firestoreService.getChildren(parentId);
  if (existing.isNotEmpty) {
    for (final child in existing) {
      if (child.nickname.trim() == nickname.trim()) {
        return child;
      }
    }
    return existing.first;
  }
  return firestoreService.addChild(
    parentId: parentId,
    nickname: nickname,
    ageBand: AgeBand.middle,
  );
}

Future<UserCredential> _signInOrCreate({
  required FirebaseAuth auth,
  required String email,
  required String password,
}) async {
  final normalizedEmail = email.trim();
  final normalizedPassword = password.trim();
  Object? lastError;

  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final credential = await auth
          .signInWithEmailAndPassword(
            email: normalizedEmail,
            password: normalizedPassword,
          )
          .timeout(_authTimeout());
      await _primeAuthSession(credential.user);
      return credential;
    } on FirebaseAuthException catch (error) {
      lastError = error;
      final code = error.code.trim().toLowerCase();
      if (code == 'user-not-found' || code == 'invalid-credential') {
        try {
          final credential = await auth
              .createUserWithEmailAndPassword(
                email: normalizedEmail,
                password: normalizedPassword,
              )
              .timeout(_authTimeout());
          await _primeAuthSession(credential.user);
          return credential;
        } on FirebaseAuthException catch (createError) {
          if (createError.code.trim().toLowerCase() != 'email-already-in-use') {
            rethrow;
          }
        }
      }

      final retryableCodes = <String>{
        'network-request-failed',
        'too-many-requests',
        'internal-error',
        'unknown',
      };
      if (!retryableCodes.contains(code) || attempt == 3) {
        rethrow;
      }
    } on TimeoutException catch (error) {
      lastError = error;
      if (attempt == 3) {
        rethrow;
      }
    }

    await Future<void>.delayed(Duration(seconds: attempt + 1));
  }

  throw StateError(
    'Sign-in failed for $normalizedEmail. Last error: $lastError',
  );
}

Duration _authTimeout() => const Duration(seconds: 90);

Future<void> _primeAuthSession(User? user) async {
  if (user == null) {
    return;
  }
  try {
    await user.getIdToken(true).timeout(_authTimeout());
  } catch (_) {
    // Best-effort for flaky real-device auth sessions.
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

String _pairingCodeForRun(String runId) {
  final digitsOnly = runId.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) {
    return '000000';
  }
  if (digitsOnly.length >= 6) {
    return digitsOnly.substring(digitsOnly.length - 6);
  }
  return digitsOnly.padLeft(6, '0');
}

String _resolvePairingCode(String runId) {
  final override = _pairingCodeOverride.trim();
  if (override.isNotEmpty) {
    return override;
  }
  return _pairingCodeForRun(runId);
}
