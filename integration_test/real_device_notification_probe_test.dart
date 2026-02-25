// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/notification_service.dart';
import 'package:trustbridge_app/services/pairing_service.dart';

const String _role = String.fromEnvironment(
  'TB_ROLE',
  defaultValue: 'status',
);
const String _parentEmail = String.fromEnvironment(
  'TB_PARENT_EMAIL',
  defaultValue: '',
);
const String _parentPassword = String.fromEnvironment(
  'TB_PARENT_PASSWORD',
  defaultValue: '',
);
const String _childIdOverride = String.fromEnvironment(
  'TB_CHILD_ID',
  defaultValue: '',
);
const String _requestMarker = String.fromEnvironment(
  'TB_REQUEST_MARKER',
  defaultValue: 'tb-real-notif',
);
const String _requestTarget = String.fromEnvironment(
  'TB_REQUEST_TARGET',
  defaultValue: 'instagram.com',
);
const String _decision = String.fromEnvironment(
  'TB_DECISION',
  defaultValue: 'approve',
);
const int _watchSeconds = int.fromEnvironment(
  'TB_WATCH_SECONDS',
  defaultValue: 90,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real-device notification probe role runner',
    (tester) async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final role = _role.trim().toLowerCase();
      switch (role) {
        case 'parent_register':
          await _parentRegister();
          break;
        case 'parent_register_queue_probe':
          await _parentRegisterQueueProbe();
          break;
        case 'parent_repair_token':
          await _parentRepairToken();
          break;
        case 'parent_register_watch':
          await _parentRegister(watch: true);
          break;
        case 'child_register':
          await _childRegister();
          break;
        case 'child_register_watch':
          await _childRegister(watch: true);
          break;
        case 'child_submit_request':
          await _childSubmitRequest();
          break;
        case 'parent_respond_latest':
          await _parentRespondLatest();
          break;
        case 'parent_delete_child':
          await _parentDeleteChild();
          break;
        case 'inspect_queue':
          await _inspectQueue();
          break;
        default:
          fail('Unsupported TB_ROLE: $role');
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<User> _ensureParentAuthUser() async {
  final auth = FirebaseAuth.instance;
  final email = _parentEmail.trim();
  final password = _parentPassword.trim();
  if (email.isNotEmpty || password.isNotEmpty) {
    if (email.isEmpty || password.isEmpty) {
      fail('Provide both TB_PARENT_EMAIL and TB_PARENT_PASSWORD.');
    }
    await auth.signOut();
    final credential = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null || user.uid.trim().isEmpty) {
      fail('Sign-in succeeded but Firebase user is unavailable.');
    }
    return user;
  }

  final currentUser = auth.currentUser;
  if (currentUser != null && currentUser.uid.trim().isNotEmpty) {
    print('[NOTIF_PROBE] using existing auth session uid=${currentUser.uid}');
    return currentUser;
  }

  try {
    final restored = await auth
        .authStateChanges()
        .firstWhere((user) => user != null)
        .timeout(const Duration(seconds: 10));
    if (restored != null && restored.uid.trim().isNotEmpty) {
      print('[NOTIF_PROBE] restored auth session uid=${restored.uid}');
      return restored;
    }
  } catch (_) {
    // fall through to fail with a precise message below
  }

  fail(
    'No signed-in Firebase user on device. '
    'Provide TB_PARENT_EMAIL/TB_PARENT_PASSWORD or sign in via app UI first.',
  );
}

Future<void> _parentRegister({bool watch = false}) async {
  final user = await _ensureParentAuthUser();
  final parentId = user.uid.trim();
  if (parentId.isEmpty) {
    fail('Parent sign-in returned empty uid.');
  }

  final notifications = NotificationService();
  await notifications.initialize();
  try {
    await notifications
        .requestPermission()
        .timeout(const Duration(seconds: 15));
  } catch (error) {
    print('[NOTIF_PROBE] parent permission request skipped: $error');
  }
  final token = (await notifications.getToken())?.trim() ?? '';
  print('[NOTIF_PROBE] parent uid=$parentId token_len=${token.length}');
  if (token.isEmpty) {
    fail('Parent FCM token unavailable.');
  }

  await FirestoreService().saveFcmToken(parentId, token);
  print('[NOTIF_PROBE] parent token saved');
  if (watch) {
    await _watchWindow('parent');
  }
}

Future<void> _parentRegisterQueueProbe() async {
  final user = await _ensureParentAuthUser();
  final parentId = user.uid.trim();
  if (parentId.isEmpty) {
    fail('Parent sign-in returned empty uid.');
  }

  final notifications = NotificationService();
  await notifications.initialize();
  try {
    await notifications
        .requestPermission()
        .timeout(const Duration(seconds: 15));
  } catch (error) {
    print('[NOTIF_PROBE] parent permission request skipped: $error');
  }
  final token = (await notifications.getToken())?.trim() ?? '';
  print('[NOTIF_PROBE] parent uid=$parentId token_len=${token.length}');
  if (token.isEmpty) {
    fail('Parent FCM token unavailable.');
  }
  await FirestoreService().saveFcmToken(parentId, token);
  print('[NOTIF_PROBE] parent token saved');

  final marker = DateTime.now().millisecondsSinceEpoch;
  final queueRef = await FirebaseFirestore.instance.collection('notification_queue').add(
    <String, dynamic>{
      'parentId': parentId,
      'title': 'TrustBridge live watch check',
      'body': 'queue-probe-$marker',
      'route': '/parent/bypass-alerts',
      'eventType': 'device_offline_30m',
      'processed': false,
      'sentAt': FieldValue.serverTimestamp(),
    },
  );
  print(
    '[NOTIF_PROBE] queue_probe marker=queue-probe-$marker queueId=${queueRef.id}',
  );

  await _watchWindow('parent_queue_probe');
}

Future<void> _parentRepairToken() async {
  final user = await _ensureParentAuthUser();
  final parentId = user.uid.trim();
  if (parentId.isEmpty) {
    fail('Parent sign-in returned empty uid.');
  }

  final notifications = NotificationService();
  await notifications.initialize();
  try {
    await notifications
        .requestPermission()
        .timeout(const Duration(seconds: 15));
  } catch (error) {
    print('[NOTIF_PROBE] parent permission request skipped: $error');
  }

  try {
    await FirebaseMessaging.instance
        .deleteToken()
        .timeout(const Duration(seconds: 20));
    print('[NOTIF_PROBE] parent token deleted');
  } catch (error) {
    print('[NOTIF_PROBE] parent token delete failed: $error');
  }

  await Future<void>.delayed(const Duration(seconds: 2));
  final token = (await notifications
              .getToken()
              .timeout(const Duration(seconds: 45), onTimeout: () => null))
          ?.trim() ??
      '';
  print('[NOTIF_PROBE] parent repaired token_len=${token.length}');
  if (token.isEmpty) {
    fail('Parent FCM token unavailable after token repair.');
  }

  await FirestoreService().saveFcmToken(parentId, token);
  print('[NOTIF_PROBE] parent repaired token saved');
}

Future<void> _childRegister({bool watch = false}) async {
  final user = await _ensureParentAuthUser();
  final parentIdFromAuth = user.uid.trim();
  if (parentIdFromAuth.isEmpty) {
    fail('Child-side same-account sign-in returned empty uid.');
  }

  final notifications = NotificationService();
  await notifications.initialize();
  await notifications.requestPermission();
  final token = (await notifications.getToken())?.trim() ?? '';
  print('[NOTIF_PROBE] child token_len=${token.length}');
  if (token.isEmpty) {
    fail('Child FCM token unavailable.');
  }

  final pairing = PairingService();
  final pairedParentId = (await pairing.getPairedParentId())?.trim() ?? '';
  final parentId = pairedParentId.isNotEmpty ? pairedParentId : parentIdFromAuth;
  final childId = (_childIdOverride.trim().isNotEmpty
          ? _childIdOverride.trim()
          : (await pairing.getPairedChildId())?.trim()) ??
      '';
  final deviceId = (await pairing.getOrCreateDeviceId()).trim();

  if (parentId.isEmpty || childId.isEmpty || deviceId.isEmpty) {
    fail(
      'Missing child pairing context. '
      'parentId=$parentId childId=$childId deviceId=$deviceId',
    );
  }

  await FirebaseFirestore.instance
      .collection('children')
      .doc(childId)
      .collection('devices')
      .doc(deviceId)
      .set(
    <String, dynamic>{
      'parentId': parentId,
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  print(
    '[NOTIF_PROBE] child token saved childId=$childId deviceId=$deviceId '
    'parentId=$parentId authUid=$parentIdFromAuth',
  );
  if (watch) {
    await _watchWindow('child');
  }
}

Future<void> _childSubmitRequest() async {
  await _ensureParentAuthUser();
  final pairing = PairingService();
  final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  final pairedParentId = (await pairing.getPairedParentId())?.trim() ?? '';
  final parentId = pairedParentId.isNotEmpty ? pairedParentId : authUid;
  final childId = (_childIdOverride.trim().isNotEmpty
          ? _childIdOverride.trim()
          : (await pairing.getPairedChildId())?.trim()) ??
      '';

  if (parentId.isEmpty || childId.isEmpty) {
    fail('Missing child pairing context for submit request.');
  }

  final childSnapshot =
      await FirebaseFirestore.instance.collection('children').doc(childId).get();
  final childNickname =
      (childSnapshot.data()?['nickname'] as String?)?.trim().isNotEmpty == true
          ? (childSnapshot.data()?['nickname'] as String).trim()
          : 'Child';

  final target = '${_requestTarget.trim()}#${_requestMarker.trim()}';
  final request = AccessRequest.create(
    childId: childId,
    parentId: parentId,
    childNickname: childNickname,
    appOrSite: target,
    duration: RequestDuration.fifteenMin,
    reason: 'Real-device notification probe',
  );
  final firestoreService = FirestoreService();
  final requestId = await firestoreService.submitAccessRequest(request);
  await firestoreService.queueParentNotification(
    parentId: parentId,
    title: '$childNickname wants access',
    body: '$childNickname requested $target for 15 min.',
    route: '/parent-requests',
  );
  print(
    '[NOTIF_PROBE] child request submitted requestId=$requestId '
    'parentId=$parentId childId=$childId target=$target',
  );
}

Future<void> _parentRespondLatest() async {
  final user = await _ensureParentAuthUser();
  final parentId = user.uid.trim();
  if (parentId.isEmpty) {
    fail('Parent sign-in returned empty uid.');
  }

  final marker = _requestMarker.trim();
  final requestsSnapshot = await FirebaseFirestore.instance
      .collection('parents')
      .doc(parentId)
      .collection('access_requests')
      .orderBy('requestedAt', descending: true)
      .limit(20)
      .get();
  final doc = requestsSnapshot.docs.firstWhere(
    (doc) {
      final data = doc.data();
      final status = (data['status'] as String?)?.trim().toLowerCase();
      final appOrSite = (data['appOrSite'] as String?)?.trim() ?? '';
      return status == 'pending' && (marker.isEmpty || appOrSite.contains(marker));
    },
    orElse: () => throw StateError('No matching pending request found for marker=$marker'),
  );
  final matchedData = doc.data();
  print(
    '[NOTIF_PROBE] parent matched pending request '
    'requestId=${doc.id} '
    'rawChildId=${matchedData['childId']} '
    'rawParentId=${matchedData['parentId']} '
    'appOrSite=${matchedData['appOrSite']} '
    'status=${matchedData['status']}',
  );

  final decision = _decision.trim().toLowerCase();
  final status =
      decision == 'deny' ? RequestStatus.denied : RequestStatus.approved;

  await FirestoreService().respondToAccessRequest(
    parentId: parentId,
    requestId: doc.id,
    status: status,
    reply: status == RequestStatus.approved
        ? 'Approved in real-device probe'
        : 'Denied in real-device probe',
    approvedDurationOverride:
        status == RequestStatus.approved ? RequestDuration.fifteenMin : null,
  );

  print(
    '[NOTIF_PROBE] parent responded requestId=${doc.id} '
    'status=${status.name} parentId=$parentId',
  );
}

Future<void> _parentDeleteChild() async {
  final user = await _ensureParentAuthUser();
  final parentId = user.uid.trim();
  final childId = _childIdOverride.trim();
  if (parentId.isEmpty) {
    fail('Parent sign-in returned empty uid.');
  }
  if (childId.isEmpty) {
    fail('TB_CHILD_ID is required for parent_delete_child.');
  }

  await FirestoreService().deleteChild(parentId: parentId, childId: childId);
  print('[NOTIF_PROBE] child deleted childId=$childId parentId=$parentId');
}

Future<void> _inspectQueue() async {
  await _ensureParentAuthUser();
  final marker = _requestMarker.trim();
  final snapshot = await FirebaseFirestore.instance
      .collection('notification_queue')
      .orderBy('sentAt', descending: true)
      .limit(30)
      .get();

  var printed = 0;
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final body = (data['body'] as String?)?.trim() ?? '';
    final title = (data['title'] as String?)?.trim() ?? '';
    if (marker.isNotEmpty &&
        !body.contains(marker) &&
        !title.contains(marker)) {
      continue;
    }
    printed += 1;
    print(
      '[NOTIF_PROBE] queue doc=${doc.id} '
      'processed=${data['processed']} status=${data['status']} '
      'eventType=${data['eventType']} route=${data['route']} '
      'errorCode=${data['errorCode']} title=$title body=$body',
    );
  }

  if (printed == 0) {
    print('[NOTIF_PROBE] queue no docs matched marker=$marker');
  }
}

Future<void> _watchWindow(String label) async {
  print('[NOTIF_PROBE] watch start label=$label seconds=$_watchSeconds');
  final endAt = DateTime.now().add(const Duration(seconds: _watchSeconds));
  while (DateTime.now().isBefore(endAt)) {
    await Future<void>.delayed(const Duration(seconds: 5));
    print('[NOTIF_PROBE] watch tick label=$label ts=${DateTime.now().toIso8601String()}');
  }
  print('[NOTIF_PROBE] watch end label=$label');
}
