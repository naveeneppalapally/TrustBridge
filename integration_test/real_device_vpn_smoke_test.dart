// ignore_for_file: avoid_print

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/services/heartbeat_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

const String _role = String.fromEnvironment(
  'TB_ROLE',
  defaultValue: 'status',
);
const String _blockedDomain = String.fromEnvironment(
  'TB_BLOCKED_DOMAIN',
  defaultValue: 'reddit.com',
);
const String _evalDomain = String.fromEnvironment(
  'TB_EVAL_DOMAIN',
  defaultValue: '',
);
const int _watchSeconds = int.fromEnvironment(
  'TB_WATCH_SECONDS',
  defaultValue: 30,
);
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real-device vpn smoke role runner',
    (tester) async {
      final vpn = VpnService();
      final role = _role.trim().toLowerCase();
      if (role == 'send_heartbeat' ||
          role == 'pairing_status' ||
          role == 'sign_in_pair_start_watch') {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      switch (role) {
        case 'status':
          await _printStatus(vpn);
          break;
        case 'start_blocking':
          await _startBlocking(vpn, _blockedDomain.trim());
          break;
        case 'start_and_watch':
          await _startBlocking(vpn, _blockedDomain.trim(), watchSeconds: _watchSeconds);
          break;
        case 'stop':
          await _stopVpn(vpn);
          break;
        case 'clear_logs':
          await _clearLogs(vpn);
          break;
        case 'evaluate':
          await _evaluate(vpn);
          break;
        case 'send_heartbeat':
          await _sendHeartbeat();
          break;
        case 'pairing_status':
          await _printPairingStatus();
          break;
        case 'sign_in_pair_start_watch':
          await _signInPairStartWatch(vpn);
          break;
        default:
          fail('Unsupported TB_ROLE value: $role');
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _sendHeartbeat() async {
  await HeartbeatService.sendHeartbeat();
  print('[VPN_SMOKE] sendHeartbeat invoked');
}

Future<void> _printPairingStatus() async {
  final pairing = PairingService();
  final deviceId = await pairing.getOrCreateDeviceId();
  final parentId = await pairing.getPairedParentId();
  final childId = await pairing.getPairedChildId();
  print(
    '[VPN_SMOKE] pairing deviceId=$deviceId parentId=$parentId childId=$childId',
  );
}

Future<void> _signInPairStartWatch(VpnService vpn) async {
  final email = _parentEmail.trim();
  final password = _parentPassword.trim();
  final pairingCode = _pairingCode.trim();
  if (email.isEmpty || password.isEmpty || pairingCode.isEmpty) {
    fail(
      'TB_PARENT_EMAIL, TB_PARENT_PASSWORD, and TB_PAIRING_CODE are required '
      'for sign_in_pair_start_watch.',
    );
  }

  final auth = FirebaseAuth.instance;
  await auth.signOut();
  final credential = await auth.signInWithEmailAndPassword(
    email: email,
    password: password,
  );
  final uid = credential.user?.uid;
  print('[VPN_SMOKE] signed_in uid=$uid');

  final pairing = PairingService();
  final deviceId = await pairing.getOrCreateDeviceId();
  final result = await pairing.validateAndPair(pairingCode, deviceId);
  print(
    '[VPN_SMOKE] pair result success=${result.success} error=${result.error} '
    'childId=${result.childId} parentId=${result.parentId} deviceId=$deviceId',
  );
  if (!result.success) {
    fail('Pairing failed: ${result.error}');
  }

  await _startBlocking(vpn, _blockedDomain.trim(), watchSeconds: 0);

  final endAt = DateTime.now().add(const Duration(seconds: _watchSeconds));
  while (DateTime.now().isBefore(endAt)) {
    await Future<void>.delayed(const Duration(seconds: 5));
    await HeartbeatService.sendHeartbeat();
    print('[VPN_SMOKE] heartbeat sent during watch');
    await _printStatus(vpn);
  }
}

Future<void> _printStatus(VpnService vpn) async {
  final status = await vpn.getStatus();
  final telemetry = await vpn.getVpnTelemetry();
  final cache = await vpn.getRuleCacheSnapshot(sampleLimit: 10);
  final queries = await vpn.getRecentDnsQueries(limit: 20);

  print(
    '[VPN_SMOKE] status supported=${status.supported} '
    'permission=${status.permissionGranted} running=${status.isRunning} '
    'processed=${status.queriesProcessed} blocked=${status.queriesBlocked} '
    'allowed=${status.queriesAllowed} privateDns=${status.privateDnsActive}'
    ' mode=${status.privateDnsMode}',
  );
  print(
    '[VPN_SMOKE] telemetry running=${telemetry.isRunning} '
    'intercepted=${telemetry.queriesIntercepted} '
    'blocked=${telemetry.queriesBlocked} allowed=${telemetry.queriesAllowed}',
  );
  print(
    '[VPN_SMOKE] cache categories=${cache.categoryCount} domains=${cache.domainCount} '
    'sampleDomains=${cache.sampleDomains}',
  );
  for (final entry in queries.take(10)) {
    print(
      '[VPN_SMOKE] query domain=${entry.domain} blocked=${entry.blocked} '
      'ts=${entry.timestamp.toIso8601String()}',
    );
  }
}

Future<void> _startBlocking(
  VpnService vpn,
  String domain, {
  int watchSeconds = 0,
}) async {
  final normalizedDomain = domain.trim().toLowerCase();
  if (normalizedDomain.isEmpty) {
    fail('TB_BLOCKED_DOMAIN is required for start_blocking role.');
  }

  final initial = await vpn.getStatus();
  print(
    '[VPN_SMOKE] initial permission=${initial.permissionGranted} '
    'running=${initial.isRunning}',
  );

  var permissionGranted = initial.permissionGranted;
  if (!permissionGranted) {
    final requestResult = await vpn.requestPermission();
    print('[VPN_SMOKE] requestPermission returned=$requestResult');
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: 30)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      permissionGranted = await vpn.hasVpnPermission();
      if (permissionGranted) {
        break;
      }
    }
  }

  if (!permissionGranted) {
    fail(
      'VPN permission not granted. Approve the Android VPN permission prompt '
      'on the device and rerun.',
    );
  }

  final started = await vpn.startVpn(
    blockedDomains: <String>[normalizedDomain],
  );
  print('[VPN_SMOKE] startVpn returned=$started domain=$normalizedDomain');
  if (!started) {
    fail('startVpn returned false.');
  }

  final updated = await vpn.updateFilterRules(
    blockedCategories: const <String>[],
    blockedDomains: <String>[normalizedDomain],
  );
  print('[VPN_SMOKE] updateFilterRules returned=$updated');

  await Future<void>.delayed(const Duration(seconds: 2));
  await _printStatus(vpn);

  if (watchSeconds > 0) {
    final endAt = DateTime.now().add(Duration(seconds: watchSeconds));
    while (DateTime.now().isBefore(endAt)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _printStatus(vpn);
    }
  }
}

Future<void> _stopVpn(VpnService vpn) async {
  final stopped = await vpn.stopVpn();
  print('[VPN_SMOKE] stopVpn returned=$stopped');
  await Future<void>.delayed(const Duration(seconds: 1));
  await _printStatus(vpn);
}

Future<void> _clearLogs(VpnService vpn) async {
  final clearedLogs = await vpn.clearDnsQueryLogs();
  final clearedCache = await vpn.clearRuleCache();
  print(
    '[VPN_SMOKE] clearDnsQueryLogs=$clearedLogs clearRuleCache=$clearedCache',
  );
}

Future<void> _evaluate(VpnService vpn) async {
  final input = (_evalDomain.trim().isEmpty ? _blockedDomain : _evalDomain)
      .trim()
      .toLowerCase();
  final evaluation = await vpn.evaluateDomainPolicy(input);
  print(
    '[VPN_SMOKE] evaluate input=${evaluation.inputDomain} '
    'normalized=${evaluation.normalizedDomain} blocked=${evaluation.blocked} '
    'matchedRule=${evaluation.matchedRule}',
  );
}
