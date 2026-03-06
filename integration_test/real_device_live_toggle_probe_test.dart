import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/services/child_effective_policy_sync_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

const String _roleRaw = String.fromEnvironment('TB_ROLE', defaultValue: '');
const String _childIdRaw = String.fromEnvironment('TB_CHILD_ID', defaultValue: '');
const int _cycles = int.fromEnvironment('TB_CYCLES', defaultValue: 4);
const int _phaseSeconds = int.fromEnvironment('TB_PHASE_SECONDS', defaultValue: 15);
const int _watchSeconds = int.fromEnvironment('TB_WATCH_SECONDS', defaultValue: 420);
const int _pollMs = int.fromEnvironment('TB_POLL_MS', defaultValue: 1000);

const String _instagramDomain = 'instagram.com';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real-device live toggle probe role runner',
    (tester) async {
      final role = _roleRaw.trim().toLowerCase();
      if (role.isEmpty) {
        fail('TB_ROLE is required: drive_parent | watch_child');
      }

      await _initFirebase();

      switch (role) {
        case 'drive_parent':
          await _runDriveParent();
          break;
        case 'watch_child':
          await _runWatchChild(tester);
          break;
        default:
          fail('Unsupported TB_ROLE value: $role');
      }
    },
    timeout: const Timeout(Duration(minutes: 25)),
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

Future<void> _runDriveParent() async {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final service = FirestoreService(firestore: firestore);

  final user = auth.currentUser;
  if (user == null || user.uid.trim().isEmpty) {
    fail(
      'No signed-in parent session on this device. '
      'Open parent app and sign in first.',
    );
  }

  final parentId = user.uid.trim();
  final child = await _resolveDriveChild(
    service: service,
    parentId: parentId,
    preferredChildId: _childIdRaw.trim(),
  );
  final childId = child.id;

  debugPrint(
    '[LIVE_DRIVE] ready parentId=$parentId childId=$childId '
    'cycles=$_cycles phaseSeconds=$_phaseSeconds',
  );

  for (var cycle = 1; cycle <= _cycles; cycle++) {
    await _applyInstagramPolicy(
      service: service,
      parentId: parentId,
      childId: childId,
      blocked: true,
    );
    debugPrint('[LIVE_DRIVE] cycle=$cycle phase=on appliedAtMs=${_nowMs()}');
    await Future<void>.delayed(const Duration(seconds: _phaseSeconds));

    await _applyInstagramPolicy(
      service: service,
      parentId: parentId,
      childId: childId,
      blocked: false,
    );
    debugPrint('[LIVE_DRIVE] cycle=$cycle phase=off appliedAtMs=${_nowMs()}');
    if (cycle < _cycles) {
      await Future<void>.delayed(const Duration(seconds: _phaseSeconds));
    }
  }

  debugPrint('[LIVE_DRIVE] done');
}

Future<ChildProfile> _resolveDriveChild({
  required FirestoreService service,
  required String parentId,
  required String preferredChildId,
}) async {
  if (preferredChildId.isNotEmpty) {
    try {
      final preferred = await service.getChild(
        parentId: parentId,
        childId: preferredChildId,
      );
      if (preferred != null) {
        return preferred;
      }
      debugPrint(
        '[LIVE_DRIVE] preferred child not found for this parent. '
        'childId=$preferredChildId',
      );
    } catch (error) {
      debugPrint(
        '[LIVE_DRIVE] preferred child lookup failed '
        'childId=$preferredChildId error=$error',
      );
    }
  }

  final children = await service.getChildrenOnce(parentId);
  if (children.isEmpty) {
    fail(
      'No accessible children found for signed-in parent. parentId=$parentId',
    );
  }
  return children.first;
}

Future<void> _runWatchChild(WidgetTester tester) async {
  final pairing = PairingService();
  final vpn = VpnService();

  final parentId = (await pairing.getPairedParentId())?.trim() ?? '';
  final childId = (await pairing.getPairedChildId())?.trim() ?? '';
  if (parentId.isEmpty || childId.isEmpty) {
    fail('Child device is not paired. parentId=$parentId childId=$childId');
  }

  var hasPermission = await vpn.hasVpnPermission();
  if (!hasPermission) {
    final requested = await vpn.requestPermission();
    debugPrint('[LIVE_WATCH] requestPermission returned=$requested');
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
    fail('VPN permission missing on child device.');
  }

  final running = await vpn.isVpnRunning();
  if (!running) {
    await vpn.startVpn(
      blockedCategories: const <String>[],
      blockedDomains: const <String>[],
      parentId: parentId,
      childId: childId,
    );
  }

  await ChildEffectivePolicySyncService.instance.start();
  try {
    debugPrint(
      '[LIVE_WATCH] ready parentId=$parentId childId=$childId '
      'watchSeconds=$_watchSeconds pollMs=$_pollMs',
    );

    final deadline = DateTime.now().add(const Duration(seconds: _watchSeconds));
    bool? lastBlocked;
    while (DateTime.now().isBefore(deadline)) {
      final status = await vpn.getStatus();
      final evaluation = await vpn.evaluateDomainPolicy(_instagramDomain);
      final blocked = evaluation.blocked;
      final tsMs = _nowMs();

      if (lastBlocked == null || blocked != lastBlocked) {
        debugPrint(
          '[LIVE_WATCH_CHANGE] tsMs=$tsMs insta=$blocked '
          'running=${status.isRunning} cats=${status.blockedCategoryCount} '
          'domains=${status.blockedDomainCount}',
        );
        lastBlocked = blocked;
      }

      debugPrint(
        '[LIVE_WATCH] tsMs=$tsMs running=${status.isRunning} '
        'cats=${status.blockedCategoryCount} '
        'domains=${status.blockedDomainCount} '
        'insta=$blocked matchedRule=${evaluation.matchedRule ?? ''}',
      );

      await Future<void>.delayed(const Duration(milliseconds: _pollMs));
      await tester.pump();
    }

    debugPrint('[LIVE_WATCH] done');
  } finally {
    await ChildEffectivePolicySyncService.instance.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _applyInstagramPolicy({
  required FirestoreService service,
  required String parentId,
  required String childId,
  required bool blocked,
}) async {
  final latest = await service.getChild(parentId: parentId, childId: childId);
  if (latest == null) {
    fail('Child not found while applying policy. childId=$childId');
  }

  final nextChild = latest.copyWith(
    policy: latest.policy.copyWith(
      blockedCategories: blocked
          ? const <String>['social-networks']
          : const <String>[],
      blockedDomains: const <String>[],
      schedules: const <Schedule>[],
    ),
    clearManualMode: true,
    clearPausedUntil: true,
  );

  await service.updateChild(parentId: parentId, child: nextChild);
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

int _nowMs() => DateTime.now().millisecondsSinceEpoch;
