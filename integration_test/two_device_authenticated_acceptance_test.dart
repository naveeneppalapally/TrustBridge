import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/screens/child/child_status_screen.dart';
import 'package:trustbridge_app/screens/dashboard_screen.dart';
import 'package:trustbridge_app/screens/usage_reports_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/heartbeat_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';

const String _role = String.fromEnvironment(
  'TB_ROLE',
  defaultValue: '',
);
const String _runIdRaw = String.fromEnvironment(
  'TB_RUN_ID',
  defaultValue: '',
);
const String _emulatorHost = String.fromEnvironment(
  'TB_EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);
const bool _useEmulators = bool.fromEnvironment(
  'TB_USE_EMULATORS',
  defaultValue: true,
);
const int _authPort = int.fromEnvironment('TB_AUTH_PORT', defaultValue: 9099);
const int _firestorePort = int.fromEnvironment(
  'TB_FIRESTORE_PORT',
  defaultValue: 8080,
);
const int _watchSeconds = int.fromEnvironment(
  'TB_WATCH_SECONDS',
  defaultValue: 90,
);
const MethodChannel _vpnChannel = MethodChannel('com.navee.trustbridge/vpn');

bool _defaultEmulatorsConfigured = false;

Duration _authTimeout() =>
    _useEmulators ? const Duration(seconds: 30) : const Duration(seconds: 90);
Duration _ioTimeout() =>
    _useEmulators ? const Duration(seconds: 30) : const Duration(seconds: 90);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'two-device authenticated acceptance role runner',
    (WidgetTester tester) async {
      final normalizedRole = _role.trim().toLowerCase();
      final runId = _normalizeRunId(_runIdRaw);
      if (normalizedRole.isEmpty) {
        fail('TB_ROLE dart-define is required.');
      }
      if (runId.isEmpty) {
        fail('TB_RUN_ID dart-define is required.');
      }

      await _initializeDefaultFirebase();

      switch (normalizedRole) {
        case 'parent_setup':
          await _runParentSetup(runId);
          break;
        case 'child_validate':
          await _runChildValidation(runId, tester);
          break;
        case 'parent_verify':
          await _runParentVerification(runId, tester);
          break;
        case 'parent_dashboard_watch':
          await _runParentDashboardWatch(runId, tester);
          break;
        default:
          fail('Unsupported TB_ROLE value: $normalizedRole');
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _initializeDefaultFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (_defaultEmulatorsConfigured) {
    return;
  }

  if (_useEmulators) {
    FirebaseAuth.instance.useAuthEmulator(_emulatorHost, _authPort);
    FirebaseFirestore.instance
        .useFirestoreEmulator(_emulatorHost, _firestorePort);
    debugPrint(
      '[E2E] Using Firebase emulators auth=$_emulatorHost:$_authPort '
      'firestore=$_emulatorHost:$_firestorePort',
    );
  } else {
    debugPrint('[E2E] Using live Firebase project configuration.');
  }
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  _defaultEmulatorsConfigured = true;
}

Future<FirebaseApp> _createSecondaryFirebaseApp(String runId) async {
  final app = await Firebase.initializeApp(
    name: 'secondary_$runId',
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final auth = FirebaseAuth.instanceFor(app: app);
  if (_useEmulators) {
    auth.useAuthEmulator(_emulatorHost, _authPort);
  }

  final firestore = FirebaseFirestore.instanceFor(app: app);
  if (_useEmulators) {
    firestore.useFirestoreEmulator(_emulatorHost, _firestorePort);
  }
  firestore.settings = const Settings(
    persistenceEnabled: false,
  );

  return app;
}

String _normalizeRunId(String raw) {
  final normalized = raw.trim().toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
  return normalized;
}

String _parentEmailForRun(String runId) {
  return 'tb.e2e.$runId@trustbridge.local';
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

Future<void> _runParentSetup(String runId) async {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final firestoreService = FirestoreService(firestore: firestore);
  final email = _parentEmailForRun(runId);
  final password = _parentPasswordForRun(runId);

  await auth.signOut();
  final credential = await _signInParentAccount(
    auth: auth,
    email: email,
    password: password,
    allowCreate: true,
  );

  final user = credential.user;
  expect(user, isNotNull);
  final parentId = user!.uid;

  debugPrint('[E2E parent_setup] ensureParentProfile start parentId=$parentId');
  await firestoreService
      .ensureParentProfile(
        parentId: parentId,
        phoneNumber: user.phoneNumber,
      )
      .timeout(_ioTimeout());
  debugPrint('[E2E parent_setup] ensureParentProfile done');

  debugPrint('[E2E parent_setup] completeOnboarding start');
  await firestoreService.completeOnboarding(parentId).timeout(_ioTimeout());
  debugPrint('[E2E parent_setup] completeOnboarding done');

  debugPrint('[E2E parent_setup] addChild start');
  final child = await firestoreService
      .addChild(
        parentId: parentId,
        nickname: 'E2E Child $runId',
        ageBand: AgeBand.middle,
      )
      .timeout(_ioTimeout());
  debugPrint('[E2E parent_setup] addChild done childId=${child.id}');

  // Keep baseline policy deterministic for acceptance assertions.
  debugPrint('[E2E parent_setup] baseline updateChild start');
  await firestoreService
      .updateChild(
        parentId: parentId,
        child: child.copyWith(
          policy: child.policy.copyWith(
            blockedCategories: const <String>[],
            blockedDomains: const <String>[],
            schedules: const <Schedule>[],
          ),
          clearPausedUntil: true,
        ),
      )
      .timeout(_ioTimeout());
  debugPrint('[E2E parent_setup] baseline updateChild done');

  final pairingCode = _pairingCodeForRun(runId);
  debugPrint('[E2E parent_setup] pairing code write start code=$pairingCode');
  await firestore
      .collection('pairing_codes')
      .doc(pairingCode)
      .set(<String, dynamic>{
    'code': pairingCode,
    'childId': child.id,
    'parentId': parentId,
    'createdAt': Timestamp.now(),
    'expiresAt': Timestamp.fromDate(
      DateTime.now().add(const Duration(minutes: 15)),
    ),
    'used': false,
  }).timeout(_ioTimeout());
  debugPrint('[E2E parent_setup] pairing code write done');
}

Future<void> _runChildValidation(
  String runId,
  WidgetTester tester,
) async {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final pairingCode = _pairingCodeForRun(runId);

  final recordedCalls = <MethodCall>[];
  var vpnRunning = false;
  var cachedCategories = const <String>[];
  var cachedDomains = const <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    _vpnChannel,
    (MethodCall call) async {
      recordedCalls.add(call);
      switch (call.method) {
        case 'isVpnRunning':
          return vpnRunning;
        case 'startVpn':
          vpnRunning = true;
          return true;
        case 'restartVpn':
          vpnRunning = true;
          return true;
        case 'stopVpn':
          vpnRunning = false;
          return true;
        case 'updateFilterRules':
          final args = _asMap(call.arguments);
          cachedCategories = _asStringList(args['blockedCategories']);
          cachedDomains = _asStringList(args['blockedDomains']);
          return true;
        case 'getRuleCacheSnapshot':
          return <String, dynamic>{
            'categoryCount': cachedCategories.length,
            'domainCount': cachedDomains.length,
            'sampleCategories': cachedCategories.take(5).toList(),
            'sampleDomains': cachedDomains.take(5).toList(),
            'lastUpdatedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
          };
        case 'getStatus':
          return <String, dynamic>{
            'supported': true,
            'permissionGranted': true,
            'isRunning': vpnRunning,
            'privateDnsActive': false,
            'privateDnsMode': '',
          };
        default:
          return true;
      }
    },
  );

  FirebaseApp? secondaryApp;
  try {
    await auth.signOut();
    await _signInParentAccount(
      auth: auth,
      email: _parentEmailForRun(runId),
      password: _parentPasswordForRun(runId),
    );

    final pairingSnapshot = await firestore
        .collection('pairing_codes')
        .doc(pairingCode)
        .get()
        .timeout(const Duration(seconds: 30));
    expect(pairingSnapshot.exists, isTrue);
    final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
    final parentId = (pairingData['parentId'] as String?)?.trim() ?? '';
    final childId = (pairingData['childId'] as String?)?.trim() ?? '';
    if (parentId.isEmpty || childId.isEmpty || pairingCode.isEmpty) {
      fail('Pairing code record is incomplete for run $runId.');
    }

    final pairingService = PairingService(firestore: firestore);
    final deviceId = await pairingService.getOrCreateDeviceId();
    final pairingResult = await pairingService
        .validateAndPair(pairingCode, deviceId)
        .timeout(const Duration(seconds: 30));
    if (!pairingResult.success) {
      // Diagnostic for real-device acceptance runs.
      // ignore: avoid_print
      print(
        'TB child_validate pairing failed: '
        'error=${pairingResult.error} '
        'childId=${pairingResult.childId} '
        'parentId=${pairingResult.parentId} '
        'runId=$runId '
        'pairingCode=$pairingCode '
        'deviceId=$deviceId',
      );
    }
    expect(pairingResult.success, isTrue);

    await HeartbeatService.sendHeartbeat().timeout(
      const Duration(seconds: 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChildStatusScreen(
            firestore: firestore,
            parentId: parentId,
            childId: childId,
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      condition: () => find.textContaining('Hi,').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 35),
    );

    secondaryApp = await _createSecondaryFirebaseApp(runId);
    final parentAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    final parentFirestore = FirebaseFirestore.instanceFor(app: secondaryApp);
    final parentService = FirestoreService(firestore: parentFirestore);
    final parentEmail = _parentEmailForRun(runId);
    final parentPassword = _parentPasswordForRun(runId);

    await _signInParentAccount(
      auth: parentAuth,
      email: parentEmail,
      password: parentPassword,
    );

    var vpnCursor = 0;

    // 1) Pause internet.
    await parentService.setChildPause(
      parentId: parentId,
      childId: childId,
      pausedUntil: DateTime.now().add(const Duration(minutes: 20)),
    );
    vpnCursor = await _awaitVpnRulesUpdate(
      tester,
      calls: recordedCalls,
      startIndex: vpnCursor,
      matcher: (categories, _) => categories.contains('__block_all__'),
    );
    await _pumpUntil(
      tester,
      condition: () =>
          find.textContaining('Internet is paused').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );

    // 2) Bedtime quick mode.
    await parentService.setChildPause(
      parentId: parentId,
      childId: childId,
      pausedUntil: null,
    );
    await parentService.setChildManualMode(
      parentId: parentId,
      childId: childId,
      mode: 'bedtime',
      expiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );
    vpnCursor = await _awaitVpnRulesUpdate(
      tester,
      calls: recordedCalls,
      startIndex: vpnCursor,
      matcher: (categories, _) => categories.contains('__block_all__'),
    );
    await _pumpUntil(
      tester,
      condition: () => find.text('Bedtime Mode').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );

    // 3) Homework quick mode.
    await parentService.setChildManualMode(
      parentId: parentId,
      childId: childId,
      mode: 'homework',
      expiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );
    vpnCursor = await _awaitVpnRulesUpdate(
      tester,
      calls: recordedCalls,
      startIndex: vpnCursor,
      matcher: (categories, _) =>
          categories.contains('social') ||
          categories.contains('social-networks'),
    );
    await _pumpUntil(
      tester,
      condition: () => find.text('Study Mode').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );

    // 4) Block Apps (policy categories/domains).
    await parentService.setChildManualMode(
      parentId: parentId,
      childId: childId,
      mode: null,
    );
    final childForBlockApps = await parentService.getChild(
      parentId: parentId,
      childId: childId,
    );
    expect(childForBlockApps, isNotNull);
    final blockedPolicyChild = childForBlockApps!.copyWith(
      policy: childForBlockApps.policy.copyWith(
        blockedCategories: const <String>['social-networks'],
        blockedDomains: const <String>['instagram.com'],
        schedules: const <Schedule>[],
      ),
      clearPausedUntil: true,
    );
    await parentService.updateChild(
      parentId: parentId,
      child: blockedPolicyChild,
    );
    vpnCursor = await _awaitVpnRulesUpdate(
      tester,
      calls: recordedCalls,
      startIndex: vpnCursor,
      matcher: (categories, domains) =>
          categories.contains('social-networks') ||
          domains.contains('instagram.com'),
    );
    await _pumpUntil(
      tester,
      condition: () => find.textContaining('Instagram').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 25),
    );

    // 5) Schedule enforcement.
    final now = DateTime.now();
    final scheduleStart = _hhmm(now.subtract(const Duration(minutes: 1)));
    final scheduleEnd = _hhmm(now.add(const Duration(minutes: 20)));
    final scheduleChild = await parentService.getChild(
      parentId: parentId,
      childId: childId,
    );
    expect(scheduleChild, isNotNull);
    final activeBedtimeSchedule = Schedule(
      id: 'e2e_schedule_$runId',
      name: 'E2E Bedtime',
      type: ScheduleType.bedtime,
      days: <Day>[Day.fromDateTime(now)],
      startTime: scheduleStart,
      endTime: scheduleEnd,
      enabled: true,
      action: ScheduleAction.blockAll,
    );
    await parentService.updateChild(
      parentId: parentId,
      child: scheduleChild!.copyWith(
        policy: scheduleChild.policy.copyWith(
          blockedCategories: const <String>[],
          blockedDomains: const <String>[],
          schedules: <Schedule>[activeBedtimeSchedule],
        ),
        clearPausedUntil: true,
      ),
    );
    vpnCursor = await _awaitVpnRulesUpdate(
      tester,
      calls: recordedCalls,
      startIndex: vpnCursor,
      matcher: (categories, _) => categories.contains('__block_all__'),
    );
    await _pumpUntil(
      tester,
      condition: () => find.text('Bedtime Mode').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 25),
    );

    // 6) Pause all + resume all.
    await parentService.pauseAllChildren(
      parentId,
      duration: const Duration(minutes: 10),
    );
    // If a schedule is already enforcing block-all, pause-all may be an
    // effective no-op for VPN rules. The child UI should still switch to the
    // paused state because the reason changed.
    try {
      vpnCursor = await _awaitVpnRulesUpdate(
        tester,
        calls: recordedCalls,
        startIndex: vpnCursor,
        matcher: (categories, _) => categories.contains('__block_all__'),
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      // Accept no-op VPN rule updates when the effective rule set is unchanged.
    }
    await _pumpUntil(
      tester,
      condition: () =>
          find.textContaining('Internet is paused').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );

    await parentService.resumeAllChildren(parentId);
    await _pumpUntil(
      tester,
      condition: () =>
          find.textContaining('Internet is paused').evaluate().isEmpty,
      timeout: const Duration(seconds: 20),
    );

    final deviceSnapshot = await firestore
        .collection('devices')
        .doc(deviceId)
        .get()
        .timeout(const Duration(seconds: 30));
    expect(deviceSnapshot.exists, isTrue);
    final deviceData = deviceSnapshot.data() ?? const <String, dynamic>{};
    expect(deviceData['parentId'], parentId);
    expect(deviceData['childId'], childId);
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_vpnChannel, null);
    if (secondaryApp != null) {
      await secondaryApp.delete();
    }
  }
}

Future<void> _runParentVerification(
  String runId,
  WidgetTester tester,
) async {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final pairingCode = _pairingCodeForRun(runId);

  await auth.signOut();
  await _signInParentAccount(
    auth: auth,
    email: _parentEmailForRun(runId),
    password: _parentPasswordForRun(runId),
  );

  final pairingSnapshot = await firestore
      .collection('pairing_codes')
      .doc(pairingCode)
      .get()
      .timeout(const Duration(seconds: 30));
  expect(pairingSnapshot.exists, isTrue);
  final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
  final parentId = auth.currentUser?.uid ?? '';
  final childId = (pairingData['childId'] as String?)?.trim() ?? '';
  if (parentId.isEmpty || childId.isEmpty) {
    fail('Parent verification context is incomplete for run $runId.');
  }

  final firestoreService = FirestoreService(firestore: firestore);
  final childProfile = await _awaitChildDeviceBinding(
    firestoreService: firestoreService,
    parentId: parentId,
    childId: childId,
  );
  final childDeviceId = childProfile.deviceIds.first;

  final deviceSnapshot = await firestore
      .collection('devices')
      .doc(childDeviceId)
      .get()
      .timeout(const Duration(seconds: 30));
  expect(deviceSnapshot.exists, isTrue);
  final deviceData = deviceSnapshot.data() ?? const <String, dynamic>{};
  final lastSeenEpoch = _toInt(deviceData['lastSeenEpochMs']);
  expect(lastSeenEpoch, greaterThan(0));
  final heartbeatAge = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(lastSeenEpoch),
  );
  expect(
    heartbeatAge,
    lessThan(const Duration(minutes: 30)),
    reason: 'Connected child device should not appear offline to parent.',
  );

  final authService = AuthService(
    auth: auth,
    firestore: firestore,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: DashboardScreen(
        authService: authService,
        firestoreService: firestoreService,
        parentIdOverride: parentId,
      ),
    ),
  );
  await _pumpUntil(
    tester,
    condition: () => find.text('ONLINE').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 30),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: UsageReportsScreen(
        authService: authService,
        firestoreService: firestoreService,
        parentIdOverride: parentId,
      ),
    ),
  );
  await _pumpUntil(
    tester,
    condition: () =>
        find
            .byKey(const Key('usage_reports_hero_card'))
            .evaluate()
            .isNotEmpty ||
        find.text('Waiting for child usage data').evaluate().isNotEmpty ||
        find.text('No child devices paired').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 25),
  );
  expect(find.textContaining('Please sign in'), findsNothing);
}

Future<void> _runParentDashboardWatch(
  String runId,
  WidgetTester tester,
) async {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final pairingCode = _pairingCodeForRun(runId);

  await auth.signOut();
  await _signInParentAccount(
    auth: auth,
    email: _parentEmailForRun(runId),
    password: _parentPasswordForRun(runId),
  );

  final pairingSnapshot = await firestore
      .collection('pairing_codes')
      .doc(pairingCode)
      .get()
      .timeout(const Duration(seconds: 30));
  expect(pairingSnapshot.exists, isTrue);
  final pairingData = pairingSnapshot.data() ?? const <String, dynamic>{};
  final parentId = auth.currentUser?.uid ?? '';
  final childId = (pairingData['childId'] as String?)?.trim() ?? '';
  if (parentId.isEmpty || childId.isEmpty) {
    fail('Parent dashboard watch context is incomplete for run $runId.');
  }

  final firestoreService = FirestoreService(firestore: firestore);
  final authService = AuthService(
    auth: auth,
    firestore: firestore,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: DashboardScreen(
        authService: authService,
        firestoreService: firestoreService,
        parentIdOverride: parentId,
      ),
    ),
  );
  await _pumpUntil(
    tester,
    condition: () => find
        .byKey(const Key('dashboard_trust_summary_card'))
        .evaluate()
        .isNotEmpty,
    timeout: const Duration(seconds: 30),
  );

  final endAt = DateTime.now().add(const Duration(seconds: _watchSeconds));
  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(const Duration(seconds: 2));
    final blocked = _textValueOrQuestion(
      tester,
      const Key('dashboard_metric_blocked_attempts_value'),
    );
    final screenTime = _textValueOrQuestion(
      tester,
      const Key('dashboard_metric_total_screen_time_value'),
    );
    final onlineVisible = find.text('ONLINE').evaluate().isNotEmpty;
    debugPrint(
      '[E2E dashboard_watch] ts=${DateTime.now().toIso8601String()} '
      'online=$onlineVisible childId=$childId blockedAttempts=$blocked '
      'screenTime=$screenTime',
    );
  }
}

String _textValueOrQuestion(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty) {
    return '?';
  }
  final widget = tester.widget<Text>(finder.first);
  return widget.data?.trim().isNotEmpty == true ? widget.data!.trim() : '?';
}

Future<void> _pumpUntil(
  WidgetTester tester, {
  required bool Function() condition,
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    await tester.pump(step);
    if (condition()) {
      return;
    }
  }
  fail('Condition not met within ${timeout.inSeconds}s.');
}

Future<ChildProfile> _awaitChildDeviceBinding({
  required FirestoreService firestoreService,
  required String parentId,
  required String childId,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    final child = await firestoreService.getChild(
      parentId: parentId,
      childId: childId,
    );
    if (child != null && child.deviceIds.isNotEmpty) {
      return child;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  fail('Child device binding was not visible to parent within timeout.');
}

Future<int> _awaitVpnRulesUpdate(
  WidgetTester tester, {
  required List<MethodCall> calls,
  required int startIndex,
  required bool Function(List<String> categories, List<String> domains) matcher,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final stopwatch = Stopwatch()..start();
  var cursor = startIndex;
  final seen = <String>[];
  while (stopwatch.elapsed < timeout) {
    for (var i = cursor; i < calls.length; i++) {
      final call = calls[i];
      if (call.method != 'updateFilterRules' && call.method != 'startVpn') {
        continue;
      }
      final args = _asMap(call.arguments);
      final categories = _asStringList(args['blockedCategories']);
      final domains = _asStringList(args['blockedDomains']);
      final summary =
          '$i:${call.method}:cats=[${categories.join(',')}] domains=[${domains.join(',')}]';
      seen.add(summary);
      if (seen.length > 12) {
        seen.removeAt(0);
      }
      if (matcher(categories, domains)) {
        return i + 1;
      }
    }
    cursor = calls.length;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail(
    'Expected VPN rule update was not observed. '
    'startIndex=$startIndex '
    'recentCalls=${seen.join(' || ')}',
  );
}

Future<void> _primeAuthSession(User? user) async {
  if (user == null) return;
  try {
    await user.getIdToken(true).timeout(_authTimeout());
    debugPrint('[E2E auth] ID token refresh completed for uid=${user.uid}');
  } catch (error) {
    debugPrint('[E2E auth] ID token refresh skipped/failed: $error');
  }
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

List<String> _asStringList(Object? raw) {
  if (raw is List) {
    return raw
        .whereType<Object?>()
        .map((item) => item?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

int _toInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  return 0;
}

String _hhmm(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

Future<UserCredential> _signInParentAccount({
  required FirebaseAuth auth,
  required String email,
  required String password,
  bool allowCreate = false,
  int maxAttempts = 3,
}) async {
  final normalizedEmail = email.trim();
  final normalizedPassword = password.trim();
  Object? lastError;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    debugPrint(
      '[E2E auth] Sign-in attempt $attempt/$maxAttempts for $normalizedEmail',
    );
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
      debugPrint(
        '[E2E auth] Sign-in error on attempt $attempt: '
        'code=${error.code} message=${error.message}',
      );
      if (allowCreate &&
          (code == 'user-not-found' || code == 'invalid-credential')) {
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
          final createCode = createError.code.trim().toLowerCase();
          debugPrint(
            '[E2E auth] Create-user error on attempt $attempt: '
            'code=${createError.code} message=${createError.message}',
          );
          if (createCode != 'email-already-in-use') {
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
      if (!retryableCodes.contains(code) || attempt == maxAttempts) {
        rethrow;
      }
    } on TimeoutException catch (error) {
      lastError = error;
      debugPrint('[E2E auth] Timeout on attempt $attempt: $error');
      if (attempt == maxAttempts) {
        rethrow;
      }
    }

    await Future<void>.delayed(
      Duration(seconds: attempt + 1),
    );
  }

  throw StateError(
    'Sign-in failed after $maxAttempts attempts for $normalizedEmail. '
    'Last error: $lastError',
  );
}
