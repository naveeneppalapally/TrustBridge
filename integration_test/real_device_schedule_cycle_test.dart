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
const int _startInMinutes = int.fromEnvironment(
  'TB_FIRST_START_IN_MINUTES',
  defaultValue: 3,
);
const int _firstDurationMinutes = int.fromEnvironment(
  'TB_FIRST_DURATION_MINUTES',
  defaultValue: 10,
);
const int _secondDurationMinutesA = int.fromEnvironment(
  'TB_SECOND_A_DURATION_MINUTES',
  defaultValue: 3,
);
const int _gapMinutes = int.fromEnvironment(
  'TB_GAP_MINUTES',
  defaultValue: 1,
);
const int _secondDurationMinutesB = int.fromEnvironment(
  'TB_SECOND_B_DURATION_MINUTES',
  defaultValue: 3,
);
const int _observeMinutes = int.fromEnvironment(
  'TB_OBSERVE_MINUTES',
  defaultValue: 30,
);
const int _observePollSeconds = int.fromEnvironment(
  'TB_OBSERVE_POLL_SECONDS',
  defaultValue: 15,
);
const String _observeDomain = String.fromEnvironment(
  'TB_OBSERVE_DOMAIN',
  defaultValue: 'instagram.com',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real-device schedule cycle role runner',
    (tester) async {
      final role = _roleRaw.trim().toLowerCase();
      final runId = _normalizeRunId(_runIdRaw);
      if (role.isEmpty) {
        fail('TB_ROLE is required: setup | cycle | observe');
      }
      if (runId.isEmpty) {
        fail('TB_RUN_ID is required.');
      }

      await _initFirebase();

      switch (role) {
        case 'setup':
          await _runSetup(runId);
          break;
        case 'cycle':
          await _runCycle(runId);
          break;
        case 'observe':
          await _runObserve(runId, tester);
          break;
        default:
          fail('Unsupported TB_ROLE value: $role');
      }
    },
    timeout: const Timeout(Duration(minutes: 65)),
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
  final firestoreService = FirestoreService(firestore: firestore);
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
    fail('Failed to sign in for setup.');
  }
  final parentId = user.uid.trim();
  if (parentId.isEmpty) {
    fail('Signed-in parentId is empty.');
  }

  await firestoreService.ensureParentProfile(
    parentId: parentId,
    phoneNumber: user.phoneNumber,
  );
  await firestoreService.completeOnboarding(parentId);

  final child = await _getOrCreateChild(
    firestoreService: firestoreService,
    parentId: parentId,
    nickname: 'Schedule Child $runId',
  );

  await _applyPolicy(
    firestoreService: firestoreService,
    parentId: parentId,
    childId: child.id,
    schedules: const <Schedule>[],
  );
  await firestore.collection('children').doc(child.id).set(
    <String, dynamic>{
      'manualMode': null,
      'pausedUntil': null,
      'updatedAt': Timestamp.now(),
    },
    SetOptions(merge: true),
  );

  final pairingService = PairingService(
    firestore: firestore,
    currentUserIdResolver: () => parentId,
  );
  final pairingCode = await pairingService.generatePairingCode(child.id);

  debugPrint(
    '[SCHEDULE_SETUP] runId=$runId parentId=$parentId childId=${child.id} '
    'email=$email pairingCode=$pairingCode',
  );
}

Future<void> _runCycle(String runId) async {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final firestoreService = FirestoreService(firestore: firestore);
  final email = _parentEmailForRun(runId);
  final password = _parentPasswordForRun(runId);
  final pairingCode = _resolvePairingCode(runId);

  await auth.signOut();
  final credential = await _signInOrCreate(
    auth: auth,
    email: email,
    password: password,
  );
  final user = credential.user;
  if (user == null) {
    fail('Failed to sign in for cycle.');
  }

  final pairingSnapshot =
      await firestore.collection('pairing_codes').doc(pairingCode).get();
  if (!pairingSnapshot.exists) {
    fail('Pairing code not found for runId=$runId. Run setup first.');
  }
  final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
  final parentId = (pairingData['parentId'] as String?)?.trim() ?? '';
  final childId = (pairingData['childId'] as String?)?.trim() ?? '';
  if (parentId.isEmpty || childId.isEmpty) {
    fail('Pairing doc is incomplete for runId=$runId.');
  }

  final child = await firestoreService.getChild(
    parentId: parentId,
    childId: childId,
  );
  if (child == null) {
    fail('Child not found for runId=$runId childId=$childId.');
  }

  await _applyPolicy(
    firestoreService: firestoreService,
    parentId: parentId,
    childId: childId,
    schedules: const <Schedule>[],
  );
  await firestore.collection('children').doc(childId).set(
    <String, dynamic>{
      'manualMode': null,
      'pausedUntil': null,
      'updatedAt': Timestamp.now(),
    },
    SetOptions(merge: true),
  );

  final now = DateTime.now();
  final firstStart = now.add(const Duration(minutes: _startInMinutes));
  final firstEnd =
      firstStart.add(const Duration(minutes: _firstDurationMinutes));
  final firstSchedule = _buildSchedule(
    id: 'first_$runId',
    name: 'First 10m',
    start: firstStart,
    end: firstEnd,
  );
  await _applyPolicy(
    firestoreService: firestoreService,
    parentId: parentId,
    childId: childId,
    schedules: <Schedule>[firstSchedule],
  );
  await firestore.collection('children').doc(childId).set(
    <String, dynamic>{
      'manualMode': null,
      'pausedUntil': null,
      'updatedAt': Timestamp.now(),
    },
    SetOptions(merge: true),
  );
  debugPrint(
    '[SCHEDULE_CYCLE] phase=first start=${firstStart.toIso8601String()} '
    'end=${firstEnd.toIso8601String()}',
  );

  await _waitUntil(
    firstEnd.add(const Duration(seconds: 45)),
    label: 'wait_first_end',
  );

  final secondAStart = DateTime.now().add(const Duration(minutes: 1));
  final secondAEnd =
      secondAStart.add(const Duration(minutes: _secondDurationMinutesA));
  final secondBStart = secondAEnd.add(const Duration(minutes: _gapMinutes));
  final secondBEnd =
      secondBStart.add(const Duration(minutes: _secondDurationMinutesB));

  final scheduleA = _buildSchedule(
    id: 'second_a_$runId',
    name: 'Second A',
    start: secondAStart,
    end: secondAEnd,
  );
  final scheduleB = _buildSchedule(
    id: 'second_b_$runId',
    name: 'Second B',
    start: secondBStart,
    end: secondBEnd,
  );

  await _applyPolicy(
    firestoreService: firestoreService,
    parentId: parentId,
    childId: childId,
    schedules: <Schedule>[scheduleA, scheduleB],
  );
  await firestore.collection('children').doc(childId).set(
    <String, dynamic>{
      'manualMode': null,
      'pausedUntil': null,
      'updatedAt': Timestamp.now(),
    },
    SetOptions(merge: true),
  );

  debugPrint(
    '[SCHEDULE_CYCLE] phase=second aStart=${secondAStart.toIso8601String()} '
    'aEnd=${secondAEnd.toIso8601String()} bStart=${secondBStart.toIso8601String()} '
    'bEnd=${secondBEnd.toIso8601String()} gapMin=$_gapMinutes',
  );

  await _waitUntil(
    secondBEnd.add(const Duration(seconds: 45)),
    label: 'wait_second_end',
  );

  await _applyPolicy(
    firestoreService: firestoreService,
    parentId: parentId,
    childId: childId,
    schedules: const <Schedule>[],
  );
  await firestore.collection('children').doc(childId).set(
    <String, dynamic>{
      'manualMode': null,
      'pausedUntil': null,
      'updatedAt': Timestamp.now(),
    },
    SetOptions(merge: true),
  );
  debugPrint('[SCHEDULE_CYCLE] phase=done clearedSchedules=true');
}

Future<void> _runObserve(
  String runId,
  WidgetTester tester,
) async {
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
    fail('Observer sign-in failed.');
  }

  final pairingSnapshot =
      await firestore.collection('pairing_codes').doc(pairingCode).get();
  if (!pairingSnapshot.exists) {
    fail('Pairing code not found for runId=$runId. Run setup first.');
  }
  final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
  final parentId = (pairingData['parentId'] as String?)?.trim() ?? '';
  final childId = (pairingData['childId'] as String?)?.trim() ?? '';
  if (parentId.isEmpty || childId.isEmpty) {
    fail('Pairing doc missing parentId/childId.');
  }

  final deviceId = await pairing.getOrCreateDeviceId();
  final pairResult = await pairing.validateAndPair(pairingCode, deviceId);
  if (!pairResult.success) {
    final recovered = await pairing.recoverPairingFromCloud();
    if (recovered == null ||
        recovered.parentId.trim() != parentId ||
        recovered.childId.trim() != childId) {
      fail(
        'Child pairing failed and cloud recovery did not restore context. '
        'error=${pairResult.error} parentId=$parentId childId=$childId',
      );
    }
  }

  var hasPermission = await vpn.hasVpnPermission();
  if (!hasPermission) {
    final requested = await vpn.requestPermission();
    debugPrint('[SCHEDULE_OBSERVE] requestPermission returned=$requested');
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
      'VPN permission not granted. Human action needed on child phone: '
      'approve Android VPN consent dialog for TrustBridge.',
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

  final observeEndAt =
      DateTime.now().add(const Duration(minutes: _observeMinutes));
  final observedStates = <bool>[];
  var mismatchCount = 0;
  var vpnDownCount = 0;
  var sampleCount = 0;

  while (DateTime.now().isBefore(observeEndAt)) {
    sampleCount += 1;
    final now = DateTime.now();
    final childSnapshot =
        await firestore.collection('children').doc(childId).get();
    if (!childSnapshot.exists) {
      fail('Child profile disappeared during observe: $childId');
    }
    final child = ChildProfile.fromFirestore(childSnapshot);
    final expectedBlocked = _expectedBlockedForDomain(
      child: child,
      now: now,
      domain: _observeDomain,
    );
    final status = await vpn.getStatus();
    final eval = await vpn.evaluateDomainPolicy(_observeDomain);
    final actualBlocked =
        status.blockedCategoryCount > 0 || status.blockedDomainCount > 0;
    if (!status.isRunning) {
      vpnDownCount += 1;
    }
    if (expectedBlocked != actualBlocked) {
      mismatchCount += 1;
    }
    if (observedStates.isEmpty || observedStates.last != actualBlocked) {
      observedStates.add(actualBlocked);
      debugPrint(
        '[SCHEDULE_OBSERVE] transition=${actualBlocked ? 'BLOCKED' : 'UNBLOCKED'} '
        'at=${now.toIso8601String()}',
      );
    }
    debugPrint(
      '[SCHEDULE_OBSERVE] sample=$sampleCount ts=${now.toIso8601String()} '
      'running=${status.isRunning} expectedBlocked=$expectedBlocked '
      'actualBlocked=$actualBlocked evalBlocked=${eval.blocked} '
      'blockedCats=${status.blockedCategoryCount} '
      'blockedDomains=${status.blockedDomainCount} mismatches=$mismatchCount',
    );

    await Future<void>.delayed(const Duration(seconds: _observePollSeconds));
    await tester.pump();
  }

  const requiredPattern = <bool>[false, true, false, true, false, true, false];
  final sequenceOk = _containsSubsequence(observedStates, requiredPattern);
  debugPrint(
    '[SCHEDULE_OBSERVE] sequence=$observedStates required=$requiredPattern '
    'sequenceOk=$sequenceOk samples=$sampleCount mismatches=$mismatchCount '
    'vpnDown=$vpnDownCount',
  );

  if (!sequenceOk) {
    fail(
      'Did not observe expected block/unblock cycle sequence. '
      'observedStates=$observedStates',
    );
  }
  if (mismatchCount > 8) {
    fail(
      'Too many expected-vs-actual mismatches during cycle '
      '(mismatchCount=$mismatchCount).',
    );
  }
  if (vpnDownCount > 3) {
    fail('VPN was down too often during observe (vpnDownCount=$vpnDownCount).');
  }
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
          if (createError.code.trim().toLowerCase() !=
              'email-already-in-use') {
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
    // Best-effort token priming for flaky real-device auth sessions.
  }
}

Future<ChildProfile> _getOrCreateChild({
  required FirestoreService firestoreService,
  required String parentId,
  required String nickname,
}) async {
  final existing = await firestoreService.getChildren(parentId);
  for (final child in existing) {
    if (child.nickname.trim() == nickname.trim()) {
      return child;
    }
  }
  return firestoreService.addChild(
    parentId: parentId,
    nickname: nickname,
    ageBand: AgeBand.middle,
  );
}

Future<void> _applyPolicy({
  required FirestoreService firestoreService,
  required String parentId,
  required String childId,
  required List<Schedule> schedules,
}) async {
  final latestChild = await firestoreService.getChild(
    parentId: parentId,
    childId: childId,
  );
  if (latestChild == null) {
    throw StateError('Child not found while applying policy: $childId');
  }
  await firestoreService.updateChild(
    parentId: parentId,
    child: latestChild.copyWith(
      policy: latestChild.policy.copyWith(
        blockedCategories: const <String>[],
        blockedDomains: const <String>[],
        schedules: schedules,
      ),
      clearPausedUntil: true,
    ),
  );
}

Schedule _buildSchedule({
  required String id,
  required String name,
  required DateTime start,
  required DateTime end,
}) {
  return Schedule(
    id: id,
    name: name,
    type: ScheduleType.bedtime,
    days: <Day>{Day.fromDateTime(start), Day.fromDateTime(end)}.toList(),
    startTime: _hhmm(start),
    endTime: _hhmm(end),
    enabled: true,
    action: ScheduleAction.blockAll,
  );
}

bool _expectedBlockedForDomain({
  required ChildProfile child,
  required DateTime now,
  required String domain,
}) {
  final normalized = domain.trim().toLowerCase();
  final pauseActive =
      child.pausedUntil != null && child.pausedUntil!.isAfter(now);
  if (pauseActive) {
    return true;
  }

  final activeSchedule = _activeSchedule(child.policy.schedules, now);
  if (activeSchedule != null) {
    switch (activeSchedule.action) {
      case ScheduleAction.blockAll:
        return true;
      case ScheduleAction.blockDistracting:
        return normalized.contains('instagram');
      case ScheduleAction.allowAll:
        break;
    }
  }

  if (child.policy.blockedDomains
      .map((d) => d.trim().toLowerCase())
      .contains(normalized)) {
    return true;
  }
  return false;
}

Schedule? _activeSchedule(List<Schedule> schedules, DateTime now) {
  for (final schedule in schedules) {
    if (!schedule.enabled) {
      continue;
    }
    if (!_isScheduleActiveAt(schedule, now)) {
      continue;
    }
    return schedule;
  }
  return null;
}

bool _isScheduleActiveAt(Schedule schedule, DateTime now) {
  final start = _parseTime(schedule.startTime);
  final end = _parseTime(schedule.endTime);
  if (start == null || end == null) {
    return false;
  }

  final today = Day.fromDateTime(now);
  final yesterday = Day.fromDateTime(now.subtract(const Duration(days: 1)));
  final startsToday = schedule.days.contains(today);
  final startedYesterday = schedule.days.contains(yesterday);

  final nowMinutes = now.hour * 60 + now.minute;
  final startMinutes = start.$1 * 60 + start.$2;
  final endMinutes = end.$1 * 60 + end.$2;

  if (startMinutes == endMinutes) {
    return startsToday;
  }

  final crossesMidnight = endMinutes < startMinutes;
  if (!crossesMidnight) {
    return startsToday && nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }

  if (startsToday && nowMinutes >= startMinutes) {
    return true;
  }
  if (startedYesterday && nowMinutes < endMinutes) {
    return true;
  }
  return false;
}

(int, int)? _parseTime(String raw) {
  final parts = raw.split(':');
  if (parts.length != 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return (hour, minute);
}

bool _containsSubsequence(List<bool> source, List<bool> pattern) {
  if (pattern.isEmpty) {
    return true;
  }
  var j = 0;
  for (final item in source) {
    if (item == pattern[j]) {
      j += 1;
      if (j == pattern.length) {
        return true;
      }
    }
  }
  return false;
}

Future<void> _waitUntil(DateTime target, {required String label}) async {
  while (true) {
    final now = DateTime.now();
    if (!target.isAfter(now)) {
      return;
    }
    final remaining = target.difference(now);
    final sleep = remaining > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : remaining;
    debugPrint(
      '[SCHEDULE_WAIT] label=$label now=${now.toIso8601String()} '
      'remainingSec=${remaining.inSeconds}',
    );
    await Future<void>.delayed(sleep);
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

String _hhmm(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
