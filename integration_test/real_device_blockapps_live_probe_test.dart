import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trustbridge_app/firebase_options.dart';
import 'package:flutter/foundation.dart';

const int _watchSeconds = int.fromEnvironment(
  'TB_WATCH_SECONDS',
  defaultValue: 120,
);
const String _childIdOverride = String.fromEnvironment(
  'TB_CHILD_ID',
  defaultValue: '',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real-device block apps live probe',
    (tester) async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;
      final user = auth.currentUser;
      if (user == null || user.uid.trim().isEmpty) {
        fail(
          'No signed-in parent session found. Open parent app, sign in, then rerun.',
        );
      }
      final parentId = user.uid.trim();

      final childDoc = await _resolveChildDoc(
        firestore: firestore,
        parentId: parentId,
        childIdOverride: _childIdOverride.trim(),
      );
      if (childDoc == null || !childDoc.exists) {
        fail('No child profile found for parentId=$parentId');
      }
      final childId = childDoc.id;

      debugPrint(
        '[LIVE_BLOCK] ready parentId=$parentId childId=$childId watchSeconds=$_watchSeconds',
      );
      debugPrint(
        '[LIVE_BLOCK] action=Toggle Block Apps ON and OFF on parent now.',
      );

      final seenEventIds = <String>{};
      final seenAckKeys = <String>{};
      final eventByVersion = <int, _ParentSaveEvent>{};
      final latencies = <int>[];
      var observedParentSaves = 0;
      var observedChildAcks = 0;
      var matchedPairs = 0;
      bool? latestVpnRunning;

      final startedAt = DateTime.now();
      final deadline = startedAt.add(const Duration(seconds: _watchSeconds));

      while (DateTime.now().isBefore(deadline)) {
        final parentEvents = await _loadRecentParentEvents(
          firestore: firestore,
          childId: childId,
        );
        for (final event in parentEvents) {
          if (!seenEventIds.add(event.docId)) {
            continue;
          }
          observedParentSaves++;
          debugPrint(
            '[LIVE_BLOCK_PARENT] '
            'doc=${event.docId} '
            'createdAtMs=${event.createdAtMs} '
            'version=${event.effectiveVersion ?? -1} '
            'cats=${event.blockedCategoriesCount ?? -1} '
            'domains=${event.blockedDomainsCount ?? -1} '
            'origin=${event.origin ?? ''}',
          );
          if (event.effectiveVersion != null) {
            eventByVersion[event.effectiveVersion!] = event;
          }
        }

        final childAcks = await _loadRecentPolicyAcks(
          firestore: firestore,
          childId: childId,
        );
        for (final ack in childAcks) {
          final key = '${ack.docId}:${ack.updatedAtMs}';
          if (!seenAckKeys.add(key)) {
            continue;
          }
          observedChildAcks++;
          latestVpnRunning = ack.vpnRunning;
          debugPrint(
            '[LIVE_BLOCK_CHILD] '
            'doc=${ack.docId} '
            'updatedAtMs=${ack.updatedAtMs} '
            'appliedVersion=${ack.appliedVersion ?? -1} '
            'status=${ack.applyStatus ?? ''} '
            'vpnRunning=${ack.vpnRunning} '
            'cachedCats=${ack.cachedCategories ?? -1} '
            'cachedDomains=${ack.cachedDomains ?? -1} '
            'expectedCats=${ack.expectedCategories ?? -1} '
            'expectedDomains=${ack.expectedDomains ?? -1} '
            'applyLatencyMs=${ack.applyLatencyMs ?? -1}',
          );

          final version = ack.appliedVersion;
          if (version == null) {
            continue;
          }
          final parentEvent = eventByVersion[version];
          if (parentEvent == null) {
            continue;
          }
          final endToEndMs = ack.updatedAtMs - parentEvent.createdAtMs;
          latencies.add(endToEndMs);
          matchedPairs++;
          debugPrint(
            '[LIVE_BLOCK_LATENCY] '
            'version=$version '
            'endToEndMs=$endToEndMs '
            'parentAtMs=${parentEvent.createdAtMs} '
            'childAckAtMs=${ack.updatedAtMs}',
          );
        }

        await Future<void>.delayed(const Duration(seconds: 1));
      }

      final minLatency = latencies.isEmpty
          ? null
          : latencies.reduce((a, b) => a < b ? a : b);
      final maxLatency = latencies.isEmpty
          ? null
          : latencies.reduce((a, b) => a > b ? a : b);
      final avgLatency = latencies.isEmpty
          ? null
          : (latencies.reduce((a, b) => a + b) / latencies.length).round();

      debugPrint(
        '[LIVE_BLOCK_SUMMARY] '
        'parentSaves=$observedParentSaves '
        'childAcks=$observedChildAcks '
        'matchedPairs=$matchedPairs '
        'latencyMinMs=${minLatency ?? -1} '
        'latencyMaxMs=${maxLatency ?? -1} '
        'latencyAvgMs=${avgLatency ?? -1} '
        'latestVpnRunning=${latestVpnRunning ?? false}',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
    semanticsEnabled: false,
  );
}

Future<DocumentSnapshot<Map<String, dynamic>>?> _resolveChildDoc({
  required FirebaseFirestore firestore,
  required String parentId,
  required String childIdOverride,
}) async {
  if (childIdOverride.isNotEmpty) {
    final direct = await firestore.collection('children').doc(childIdOverride).get();
    if (direct.exists) {
      return direct;
    }
  }

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

Future<List<_ParentSaveEvent>> _loadRecentParentEvents({
  required FirebaseFirestore firestore,
  required String childId,
}) async {
  final snapshot = await firestore
      .collection('children')
      .doc(childId)
      .collection('parent_debug_events')
      .orderBy('createdAt', descending: true)
      .limit(20)
      .get();

  final events = <_ParentSaveEvent>[];
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final screen = (data['screen'] as String?)?.trim().toLowerCase() ?? '';
    final eventType = (data['eventType'] as String?)?.trim().toLowerCase() ?? '';
    if (screen != 'block_apps' || eventType != 'policy_save_succeeded') {
      continue;
    }
    final payload = data['payload'];
    final payloadMap = payload is Map<String, dynamic>
        ? payload
        : (payload is Map ? Map<String, dynamic>.from(payload) : const <String, dynamic>{});
    final createdAt = _readDateTime(data['createdAt']) ?? DateTime.now();
    events.add(
      _ParentSaveEvent(
        docId: doc.id,
        createdAtMs: createdAt.millisecondsSinceEpoch,
        effectiveVersion: _toInt(payloadMap['effectivePolicyVersion']),
        blockedCategoriesCount: _toInt(payloadMap['blockedCategoriesCount']),
        blockedDomainsCount: _toInt(payloadMap['blockedDomainsCount']),
        origin: payloadMap['origin']?.toString(),
      ),
    );
  }
  return events;
}

Future<List<_ChildPolicyAck>> _loadRecentPolicyAcks({
  required FirebaseFirestore firestore,
  required String childId,
}) async {
  final snapshot = await firestore
      .collection('children')
      .doc(childId)
      .collection('policy_apply_acks')
      .orderBy('updatedAt', descending: true)
      .limit(10)
      .get();

  final acks = <_ChildPolicyAck>[];
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final updatedAt = _readDateTime(data['updatedAt']) ?? DateTime.now();
    final ruleCountsRaw = data['ruleCounts'];
    final ruleCounts = ruleCountsRaw is Map<String, dynamic>
        ? ruleCountsRaw
        : (ruleCountsRaw is Map
            ? Map<String, dynamic>.from(ruleCountsRaw)
            : const <String, dynamic>{});
    acks.add(
      _ChildPolicyAck(
        docId: doc.id,
        updatedAtMs: updatedAt.millisecondsSinceEpoch,
        appliedVersion: _toInt(data['appliedVersion']),
        applyStatus: data['applyStatus']?.toString(),
        vpnRunning: data['vpnRunning'] == true,
        applyLatencyMs: _toInt(data['applyLatencyMs']),
        expectedCategories: _toInt(ruleCounts['categoriesExpected']),
        expectedDomains: _toInt(ruleCounts['domainsExpected']),
        cachedCategories: _toInt(ruleCounts['categoriesCached']),
        cachedDomains: _toInt(ruleCounts['domainsCached']),
      ),
    );
  }
  return acks;
}

DateTime? _readDateTime(Object? raw) {
  if (raw is Timestamp) {
    return raw.toDate();
  }
  if (raw is DateTime) {
    return raw;
  }
  return null;
}

int? _toInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw.trim());
  }
  return null;
}

class _ParentSaveEvent {
  const _ParentSaveEvent({
    required this.docId,
    required this.createdAtMs,
    required this.effectiveVersion,
    required this.blockedCategoriesCount,
    required this.blockedDomainsCount,
    required this.origin,
  });

  final String docId;
  final int createdAtMs;
  final int? effectiveVersion;
  final int? blockedCategoriesCount;
  final int? blockedDomainsCount;
  final String? origin;
}

class _ChildPolicyAck {
  const _ChildPolicyAck({
    required this.docId,
    required this.updatedAtMs,
    required this.appliedVersion,
    required this.applyStatus,
    required this.vpnRunning,
    required this.applyLatencyMs,
    required this.expectedCategories,
    required this.expectedDomains,
    required this.cachedCategories,
    required this.cachedDomains,
  });

  final String docId;
  final int updatedAtMs;
  final int? appliedVersion;
  final String? applyStatus;
  final bool vpnRunning;
  final int? applyLatencyMs;
  final int? expectedCategories;
  final int? expectedDomains;
  final int? cachedCategories;
  final int? cachedDomains;
}
