
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
const int _opTimeoutSeconds = int.fromEnvironment(
  'TB_OP_TIMEOUT_SECONDS',
  defaultValue: 20,
);
const int _observePollMs = int.fromEnvironment(
  'TB_OBSERVE_POLL_MS',
  defaultValue: 100,
);
const String _domainA = 'sync-speed-a.trustbridge.test';
const String _domainB = 'sync-speed-b.trustbridge.test';

class _ExpectedRuleState {
  const _ExpectedRuleState({
    this.categoryBlocked,
    this.domainBlocked,
  });

  final bool? categoryBlocked;
  final bool? domainBlocked;
}

class _StressOperation {
  const _StressOperation({
    required this.seq,
    required this.id,
    required this.label,
    required this.kind,
    required this.expected,
  });

  final int seq;
  final String id;
  final String label;
  final String kind;
  final _ExpectedRuleState expected;
}

class _EnforcementSample {
  const _EnforcementSample({
    required this.enforcedAtMs,
    required this.status,
  });

  final int enforcedAtMs;
  final VpnStatus status;
}

const List<_StressOperation> _operations = <_StressOperation>[
  _StressOperation(
    seq: 1,
    id: 'op01_block_domain',
    label: 'block domain',
    kind: 'block_domain',
    expected: _ExpectedRuleState(categoryBlocked: false, domainBlocked: true),
  ),
  _StressOperation(
    seq: 2,
    id: 'op02_unblock_domain',
    label: 'unblock domain',
    kind: 'unblock_domain',
    expected: _ExpectedRuleState(categoryBlocked: false, domainBlocked: false),
  ),
  _StressOperation(
    seq: 3,
    id: 'op03_block_category',
    label: 'block category',
    kind: 'block_category',
    expected: _ExpectedRuleState(categoryBlocked: true),
  ),
  _StressOperation(
    seq: 4,
    id: 'op04_unblock_category',
    label: 'unblock category',
    kind: 'unblock_category',
    expected: _ExpectedRuleState(categoryBlocked: false, domainBlocked: false),
  ),
  _StressOperation(
    seq: 5,
    id: 'op05_add_custom_domain',
    label: 'add custom domain',
    kind: 'add_custom_domain',
    expected: _ExpectedRuleState(categoryBlocked: false, domainBlocked: true),
  ),
  _StressOperation(
    seq: 6,
    id: 'op06_remove_custom_domain',
    label: 'remove custom domain',
    kind: 'remove_custom_domain',
    expected: _ExpectedRuleState(categoryBlocked: false, domainBlocked: false),
  ),
  _StressOperation(
    seq: 7,
    id: 'op07_enable_quick_mode',
    label: 'enable quick mode',
    kind: 'enable_quick_mode',
    expected: _ExpectedRuleState(categoryBlocked: true),
  ),
  _StressOperation(
    seq: 8,
    id: 'op08_disable_quick_mode',
    label: 'disable quick mode',
    kind: 'disable_quick_mode',
    expected: _ExpectedRuleState(categoryBlocked: false, domainBlocked: false),
  ),
  _StressOperation(
    seq: 9,
    id: 'op09_pause_device',
    label: 'pause device',
    kind: 'pause_device',
    expected: _ExpectedRuleState(categoryBlocked: true),
  ),
  _StressOperation(
    seq: 10,
    id: 'op10_unpause_device',
    label: 'unpause device',
    kind: 'unpause_device',
    expected: _ExpectedRuleState(categoryBlocked: false, domainBlocked: false),
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real-device policy sync stress role runner',
    (tester) async {
      final role = _roleRaw.trim().toLowerCase();
      final runId = _normalizeRunId(_runIdRaw);
      if (role.isEmpty) {
        fail('TB_ROLE is required: setup | drive | observe');
      }
      if (runId.isEmpty) {
        fail('TB_RUN_ID is required.');
      }

      await _initFirebase();
      switch (role) {
        case 'setup':
          await _runSetup(runId);
          break;
        case 'drive':
          await _runDrive(runId);
          break;
        case 'observe':
          await _runObserve(runId, tester);
          break;
        default:
          fail('Unsupported TB_ROLE value: $role');
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
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
    '[SYNC_STRESS_SETUP] runId=$runId parentId=$parentId childId=${child.id} '
    'email=$email pairingCode=$pairingCode',
  );
}

Future<void> _runDrive(String runId) async {
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
    fail('Drive sign-in failed.');
  }

  final pairingSnapshot =
      await firestore.collection('pairing_codes').doc(pairingCode).get();
  if (!pairingSnapshot.exists) {
    fail('Pairing code not found for drive. Run setup first.');
  }
  final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
  final parentId = (pairingData['parentId'] as String?)?.trim() ?? '';
  final childId = (pairingData['childId'] as String?)?.trim() ?? '';
  if (parentId.isEmpty || childId.isEmpty) {
    fail('Pairing code is missing parentId or childId.');
  }

  // Deterministic baseline before rapid updates.
  await _setPolicy(
    firestoreService: service,
    parentId: parentId,
    childId: childId,
    blockedCategories: const <String>[],
    blockedDomains: const <String>[],
  );
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

  for (final op in _operations) {
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _applyOperation(
      operation: op,
      firestoreService: service,
      parentId: parentId,
      childId: childId,
    );
    final savedAtMs = DateTime.now().millisecondsSinceEpoch;
    print(
      '[SYNC_STRESS_DRIVE] seq=${op.seq} opId=${op.id} kind=${op.kind} '
      'startedAtMs=$startedAtMs savedAtMs=$savedAtMs',
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  final childSnapshot = await firestore.collection('children').doc(childId).get();
  if (!childSnapshot.exists) {
    fail('Child profile disappeared during drive.');
  }
  final child = ChildProfile.fromFirestore(childSnapshot);
  final childRaw = childSnapshot.data() ?? const <String, dynamic>{};
  final manualMode = childRaw['manualMode'];
  final parentFinalPolicyOk =
      child.policy.blockedCategories.isEmpty && child.policy.blockedDomains.isEmpty;
  final parentFinalPauseOk =
      child.pausedUntil == null || !child.pausedUntil!.isAfter(DateTime.now());
  final parentFinalManualOk = manualMode == null;
  final finalStateOk = parentFinalPolicyOk && parentFinalPauseOk && parentFinalManualOk;

  print(
    '[SYNC_STRESS_DRIVE_FINAL] finalStateOk=$finalStateOk '
    'parentFinalPolicyOk=$parentFinalPolicyOk '
    'parentFinalPauseOk=$parentFinalPauseOk '
    'parentFinalManualOk=$parentFinalManualOk',
  );
}

Future<void> _runObserve(String runId, WidgetTester tester) async {
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
    fail('Observe sign-in failed.');
  }

  final pairingSnapshot =
      await firestore.collection('pairing_codes').doc(pairingCode).get();
  if (!pairingSnapshot.exists) {
    fail('Pairing code not found for observe. Run setup first.');
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
        'Observe pairing failed and cloud recovery did not restore context. '
        'error=${pairResult.error}',
      );
    }
  }

  var hasPermission = await vpn.hasVpnPermission();
  if (!hasPermission) {
    final requested = await vpn.requestPermission();
    print('[SYNC_STRESS_OBSERVE] requestPermission returned=$requested');
    final waitUntil = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(waitUntil)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      hasPermission = await vpn.hasVpnPermission();
      if (hasPermission) {
        break;
      }
    }
  }
  if (!hasPermission) {
    fail(
      'VPN permission not granted. Human action required on child phone: '
      'approve Android VPN consent dialog.',
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

  print('[SYNC_STRESS_OBSERVE] ready runId=$runId childId=$childId');
  var lastObservedBlocked = _isBlocked(await vpn.getStatus());
  print('[SYNC_STRESS_OBSERVE] initialBlocked=$lastObservedBlocked');

  for (final op in _operations) {
    final timeout = op.seq == 1
        ? const Duration(seconds: _opTimeoutSeconds * 4)
        : const Duration(seconds: _opTimeoutSeconds);
    final sample = await _waitForOperationEnforcement(
      vpn: vpn,
      expected: op.expected,
      previousBlockedState: lastObservedBlocked,
      timeout: timeout,
      pollEvery: const Duration(milliseconds: _observePollMs),
    );
    if (sample == null) {
      final last = await vpn.getStatus();
      print(
        '[SYNC_STRESS_OBSERVE_RESULT] seq=${op.seq} opId=${op.id} '
        'status=lost reason=state_not_enforced '
        'enforcedAtMs=-1 cats=${last.blockedCategoryCount} '
        'domains=${last.blockedDomainCount}',
      );
      continue;
    }

    lastObservedBlocked = _isBlocked(sample.status);
    print(
      '[SYNC_STRESS_OBSERVE_RESULT] seq=${op.seq} opId=${op.id} '
      'status=enforced enforcedAtMs=${sample.enforcedAtMs} '
      'cats=${sample.status.blockedCategoryCount} '
      'domains=${sample.status.blockedDomainCount}',
    );
  }

  await Future<void>.delayed(const Duration(seconds: 2));
  final finalStatus = await vpn.getStatus();
  final childSnapshot = await firestore.collection('children').doc(childId).get();
  if (!childSnapshot.exists) {
    fail('Child profile missing while finalizing observe.');
  }
  final child = ChildProfile.fromFirestore(childSnapshot);
  final raw = childSnapshot.data() ?? const <String, dynamic>{};
  final manualMode = raw['manualMode'];

  final finalPolicyClear =
      child.policy.blockedCategories.isEmpty && child.policy.blockedDomains.isEmpty;
  final finalPauseClear =
      child.pausedUntil == null || !child.pausedUntil!.isAfter(DateTime.now());
  final finalManualClear = manualMode == null;
  final finalVpnClear = _statusMatches(
    status: finalStatus,
    expected: const _ExpectedRuleState(
      categoryBlocked: false,
      domainBlocked: false,
    ),
  );
  final finalStateOk =
      finalPolicyClear && finalPauseClear && finalManualClear && finalVpnClear;

  print(
    '[SYNC_STRESS_OBSERVE_FINAL] finalStateOk=$finalStateOk '
    'finalPolicyClear=$finalPolicyClear finalPauseClear=$finalPauseClear '
    'finalManualClear=$finalManualClear finalVpnClear=$finalVpnClear '
      'cats=${finalStatus.blockedCategoryCount} domains=${finalStatus.blockedDomainCount}',
  );

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 200));
}

Future<_EnforcementSample?> _waitForOperationEnforcement({
  required VpnService vpn,
  required _ExpectedRuleState expected,
  required bool previousBlockedState,
  required Duration timeout,
  required Duration pollEvery,
}) async {
  final expectedBlocked = _expectedBlocked(expected);
  final requireOppositeFlip = expectedBlocked == previousBlockedState;
  var sawOpposite = false;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = await vpn.getStatus();
    final blockedNow = _isBlocked(status);
    if (requireOppositeFlip && blockedNow != previousBlockedState) {
      sawOpposite = true;
    }
    final matchesRuleState = _statusMatches(status: status, expected: expected);
    if (matchesRuleState && (!requireOppositeFlip || sawOpposite)) {
      return _EnforcementSample(
        enforcedAtMs: DateTime.now().millisecondsSinceEpoch,
        status: status,
      );
    }
    await Future<void>.delayed(pollEvery);
  }
  return null;
}

bool _statusMatches({
  required VpnStatus status,
  required _ExpectedRuleState expected,
}) {
  if (!status.isRunning) {
    return false;
  }
  final expectedCategoryBlocked = expected.categoryBlocked;
  if (expectedCategoryBlocked != null) {
    final actualCategoryBlocked = status.blockedCategoryCount > 0;
    if (actualCategoryBlocked != expectedCategoryBlocked) {
      return false;
    }
  }
  final expectedDomainBlocked = expected.domainBlocked;
  if (expectedDomainBlocked != null) {
    final actualDomainBlocked = status.blockedDomainCount > 0;
    if (actualDomainBlocked != expectedDomainBlocked) {
      return false;
    }
  }
  return true;
}

bool _isBlocked(VpnStatus status) {
  return status.blockedCategoryCount > 0 || status.blockedDomainCount > 0;
}

bool _expectedBlocked(_ExpectedRuleState expected) {
  if (expected.categoryBlocked == true || expected.domainBlocked == true) {
    return true;
  }
  return false;
}

Future<void> _applyOperation({
  required _StressOperation operation,
  required FirestoreService firestoreService,
  required String parentId,
  required String childId,
}) async {
  switch (operation.kind) {
    case 'block_domain':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>[],
        blockedDomains: const <String>[_domainA],
      );
      return;
    case 'unblock_domain':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>[],
        blockedDomains: const <String>[],
      );
      return;
    case 'block_category':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>['social-networks'],
        blockedDomains: const <String>[],
      );
      return;
    case 'unblock_category':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>[],
        blockedDomains: const <String>[],
      );
      return;
    case 'add_custom_domain':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>[],
        blockedDomains: const <String>[_domainB],
      );
      return;
    case 'remove_custom_domain':
      await _setPolicy(
        firestoreService: firestoreService,
        parentId: parentId,
        childId: childId,
        blockedCategories: const <String>[],
        blockedDomains: const <String>[],
      );
      return;
    case 'enable_quick_mode':
      await firestoreService.setChildManualMode(
        parentId: parentId,
        childId: childId,
        mode: 'bedtime',
        expiresAt: DateTime.now().add(const Duration(minutes: 20)),
      );
      return;
    case 'disable_quick_mode':
      await firestoreService.setChildManualMode(
        parentId: parentId,
        childId: childId,
        mode: null,
      );
      return;
    case 'pause_device':
      await firestoreService.setChildPause(
        parentId: parentId,
        childId: childId,
        pausedUntil: DateTime.now().add(const Duration(minutes: 20)),
      );
      return;
    case 'unpause_device':
      await firestoreService.setChildPause(
        parentId: parentId,
        childId: childId,
        pausedUntil: null,
      );
      return;
    default:
      throw StateError('Unsupported operation kind: ${operation.kind}');
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
