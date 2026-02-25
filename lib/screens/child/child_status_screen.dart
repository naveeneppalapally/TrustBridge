import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/category_ids.dart';
import '../../config/social_media_domains.dart';
import '../../models/access_request.dart';
import '../../models/blocklist_source.dart';
import '../../models/child_profile.dart';
import '../../models/schedule.dart';
import '../../services/blocklist_sync_service.dart';
import '../../services/child_usage_upload_service.dart';
import '../../services/firestore_service.dart';
import '../../services/heartbeat_service.dart';
import '../../services/notification_service.dart';
import '../../services/pairing_service.dart';
import '../../services/remote_command_service.dart';
import '../../services/vpn_service.dart';
import '../../widgets/child/blocked_apps_list.dart';
import '../../widgets/child/mode_display_card.dart';
import 'request_access_screen.dart';

/// Child-mode home screen with simple and transparent language.
class ChildStatusScreen extends StatefulWidget {
  const ChildStatusScreen({
    super.key,
    this.firestore,
    this.parentId,
    this.childId,
  });

  final FirebaseFirestore? firestore;
  final String? parentId;
  final String? childId;

  @override
  State<ChildStatusScreen> createState() => _ChildStatusScreenState();
}

class _ChildStatusScreenState extends State<ChildStatusScreen>
    with WidgetsBindingObserver {
  static const String _blockAllCategory = '__block_all__';
  static const Set<String> _distractingCategories = <String>{
    'social-networks',
    'chat',
    'streaming',
    'games',
  };
  static const Map<String, List<String>> _categoryDomainFallbacks =
      <String, List<String>>{
    'chat': <String>[
      'whatsapp.com',
      'web.whatsapp.com',
      'telegram.org',
      'discord.com',
      'discord.gg',
      'messenger.com',
    ],
    'streaming': <String>[
      'youtube.com',
      'googlevideo.com',
      'ytimg.com',
      'netflix.com',
      'nflxvideo.net',
      'hotstar.com',
      'disneyplus.com',
      'twitch.tv',
    ],
    'games': <String>[
      'roblox.com',
      'rbxcdn.com',
      'epicgames.com',
      'steampowered.com',
      'riotgames.com',
      'minecraft.net',
    ],
    'shopping': <String>[
      'amazon.com',
      'flipkart.com',
      'myntra.com',
      'ebay.com',
    ],
    'forums': <String>[
      'reddit.com',
      'redd.it',
      'discord.com',
      'quora.com',
    ],
  };

  late final FirebaseFirestore _firestore;
  final VpnService _vpnService = VpnService();
  BlocklistSyncService? _blocklistSyncService;
  BlocklistSyncService get _resolvedBlocklistSyncService {
    _blocklistSyncService ??= BlocklistSyncService(enableRemoteLogging: false);
    return _blocklistSyncService!;
  }

  PairingService? _pairingService;
  PairingService get _resolvedPairingService {
    _pairingService ??= PairingService();
    return _pairingService!;
  }

  RemoteCommandService? _remoteCommandService;
  RemoteCommandService get _resolvedRemoteCommandService {
    _remoteCommandService ??= RemoteCommandService(
      firestore: _firestore,
      pairingService: _resolvedPairingService,
      vpnService: _vpnService,
    );
    return _remoteCommandService!;
  }

  ChildUsageUploadService? _usageUploadService;
  ChildUsageUploadService get _resolvedUsageUploadService {
    _usageUploadService ??= ChildUsageUploadService(firestore: _firestore);
    return _usageUploadService!;
  }

  late final FirestoreService _firestoreService;

  String? _parentId;
  String? _childId;
  bool _loadingContext = true;
  bool _redirectingToSetup = false;
  bool _recoveringPairing = false;
  bool _handledMissingChildProfile = false;
  Timer? _heartbeatTimer;
  Timer? _remoteCommandTimer;
  Timer? _protectionRetryTimer;
  Timer? _protectionBoundaryTimer;
  Timer? _scheduleWarningTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _accessRequestsSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _childProfileSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _policyEventsSubscription;
  StreamSubscription<String>? _childTokenRefreshSubscription;
  String? _accessRequestsSubscriptionKey;
  String? _childProfileSubscriptionKey;
  String? _policyEventsSubscriptionKey;
  final Queue<_PolicyEventSnapshot> _pendingPolicyEvents =
      Queue<_PolicyEventSnapshot>();
  final Set<String> _processedPolicyEventIds = <String>{};
  int? _policyEventEpochFloorMs;
  bool _isApplyingProtectionRules = false;
  final Queue<_QueuedProtectionApply> _pendingProtectionApplies =
      Queue<_QueuedProtectionApply>();
  String? _lastAppliedPolicySignature;
  bool _protectionRetryScheduled = false;
  DateTime? _lastPolicyApplyHeartbeatAt;
  ChildProfile? _lastKnownChild;
  _ManualModeOverride? _lastManualModeOverride;
  Set<String> _activeApprovedExceptionDomains = const <String>{};
  DateTime? _nextApprovedExceptionExpiry;
  DateTime? _lastWarnedScheduleStartAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firestore = widget.firestore ?? FirebaseFirestore.instance;
    _firestoreService = FirestoreService(firestore: _firestore);
    _parentId = widget.parentId?.trim();
    _childId = widget.childId?.trim();
    unawaited(_resolveContext());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Re-check VPN and re-apply rules when app comes back to foreground.
      final child = _lastKnownChild;
      if (child != null) {
        unawaited(_ensureProtectionApplied(child, forceRecheck: true));
      }
      unawaited(_processPendingRemoteCommands());
    }
  }

  Future<void> _resolveContext() async {
    if ((_parentId?.isNotEmpty ?? false) && (_childId?.isNotEmpty ?? false)) {
      final resolved = await _resolvePairingWithCloudFallback(
        parentId: _parentId,
        childId: _childId,
      );
      if (resolved != null) {
        _parentId = resolved.parentId;
        _childId = resolved.childId;
      }
      await _ensureChildAuthAndPrimeHeartbeat(
        parentId: _parentId,
        childId: _childId,
      );
      if (mounted) {
        setState(() {
          _loadingContext = false;
        });
      }
      _startHeartbeatLoop();
      _startRemoteCommandLoop();
      unawaited(_syncChildDeviceNotificationToken());
      _ensureAccessRequestSubscription();
      _ensureChildProfileSubscription();
      _ensurePolicyEventSubscription();
      return;
    }
    final parentId = await _resolvedPairingService.getPairedParentId();
    final childId = await _resolvedPairingService.getPairedChildId();
    final resolved = await _resolvePairingWithCloudFallback(
      parentId: parentId,
      childId: childId,
    );
    final resolvedParentId = _parentId ?? resolved?.parentId ?? parentId;
    final resolvedChildId = _childId ?? resolved?.childId ?? childId;
    await _ensureChildAuthAndPrimeHeartbeat(
      parentId: resolvedParentId,
      childId: resolvedChildId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _parentId = resolvedParentId;
      _childId = resolvedChildId;
      _loadingContext = false;
    });
    _startHeartbeatLoop();
    _startRemoteCommandLoop();
    unawaited(_syncChildDeviceNotificationToken());
    _ensureAccessRequestSubscription();
    _ensureChildProfileSubscription();
    _ensurePolicyEventSubscription();
  }

  Future<void> _ensureChildAuthAndPrimeHeartbeat({
    required String? parentId,
    required String? childId,
  }) async {
    final normalizedParentId = parentId?.trim();
    final normalizedChildId = childId?.trim();
    if (normalizedParentId == null ||
        normalizedParentId.isEmpty ||
        normalizedChildId == null ||
        normalizedChildId.isEmpty) {
      return;
    }

    if (Firebase.apps.isEmpty) {
      // Widget tests may render this screen without Firebase initialization.
      return;
    }

    User? currentUser;
    try {
      currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        final credential = await FirebaseAuth.instance.signInAnonymously();
        currentUser = credential.user;
      }
    } catch (_) {
      return;
    }
    final currentUid = currentUser?.uid.trim();
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
        '[ChildStatus] Missing signed-in Firebase session. '
        'Child mode expects the shared parent account session.',
      );
      return;
    }
    if (currentUid != normalizedParentId) {
      debugPrint(
        '[ChildStatus] Parent mismatch during bootstrap. '
        'expectedParentId=$normalizedParentId currentUid=$currentUid',
      );
    }

    try {
      await _resolvedPairingService.getOrCreateDeviceId();
    } catch (_) {
      // Device ID refresh is best-effort.
    }

    try {
      await HeartbeatService.sendHeartbeat();
    } catch (_) {
      // Heartbeat bootstrap is best-effort.
    }
  }

  Future<PairingContext?> _resolvePairingWithCloudFallback({
    required String? parentId,
    required String? childId,
  }) async {
    final normalizedParentId = parentId?.trim();
    final normalizedChildId = childId?.trim();
    if (normalizedParentId == null ||
        normalizedParentId.isEmpty ||
        normalizedChildId == null ||
        normalizedChildId.isEmpty) {
      return await _resolvedPairingService.recoverPairingFromCloud();
    }

    try {
      final snapshot =
          await _firestore.collection('children').doc(normalizedChildId).get();
      if (snapshot.exists) {
        return PairingContext(
          childId: normalizedChildId,
          parentId: normalizedParentId,
        );
      }
    } catch (_) {
      // Fall through to cloud recovery.
    }
    return await _resolvedPairingService.recoverPairingFromCloud();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _remoteCommandTimer?.cancel();
    _remoteCommandTimer = null;
    _protectionRetryTimer?.cancel();
    _protectionRetryTimer = null;
    _protectionBoundaryTimer?.cancel();
    _protectionBoundaryTimer = null;
    _scheduleWarningTimer?.cancel();
    _scheduleWarningTimer = null;
    _accessRequestsSubscription?.cancel();
    _accessRequestsSubscription = null;
    _childProfileSubscription?.cancel();
    _childProfileSubscription = null;
    _policyEventsSubscription?.cancel();
    _policyEventsSubscription = null;
    _childTokenRefreshSubscription?.cancel();
    _childTokenRefreshSubscription = null;
    _pendingProtectionApplies.clear();
    _pendingPolicyEvents.clear();
    _processedPolicyEventIds.clear();
    super.dispose();
  }

  void _startHeartbeatLoop() {
    if (_heartbeatTimer != null) {
      return;
    }
    unawaited(_sendHeartbeatOnce());
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_sendHeartbeatOnce()),
    );
  }

  Future<void> _sendHeartbeatOnce() async {
    try {
      await HeartbeatService.sendHeartbeat();
    } catch (_) {
      // Child heartbeat is best-effort.
    }

    // Upload usage data alongside heartbeat (throttled internally).
    final childId = _childId;
    if (childId != null && childId.isNotEmpty) {
      unawaited(
        _resolvedUsageUploadService.uploadIfNeeded(childId: childId),
      );
    }
  }

  void _startRemoteCommandLoop() {
    if (_remoteCommandTimer != null) {
      return;
    }
    unawaited(_processPendingRemoteCommands());
    _remoteCommandTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_processPendingRemoteCommands()),
    );
  }

  Future<void> _processPendingRemoteCommands() async {
    try {
      await _resolvedRemoteCommandService.processPendingCommands();
    } catch (_) {
      // Best-effort command processing while child screen is active.
    }
  }

  Future<void> _syncChildDeviceNotificationToken() async {
    final childId = _childId?.trim();
    final parentId = _parentId?.trim();
    if (childId == null ||
        childId.isEmpty ||
        parentId == null ||
        parentId.isEmpty) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      // Widget tests may render child shell without Firebase initialization.
      return;
    }

    Future<void> writeToken(String rawToken) async {
      final token = rawToken.trim();
      if (token.isEmpty) {
        debugPrint('[ChildStatus] FCM token empty; skipping token sync.');
        return;
      }
      final deviceId = await _resolvedPairingService.getOrCreateDeviceId();
      final deviceRef = _firestore
          .collection('children')
          .doc(childId)
          .collection('devices')
          .doc(deviceId);
      await deviceRef.set(
        <String, dynamic>{
          'parentId': parentId,
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint(
        '[ChildStatus] Child FCM token synced: '
        'children/$childId/devices/$deviceId',
      );
    }

    try {
      final token = await NotificationService().getToken();
      if (token != null) {
        await writeToken(token);
      } else {
        debugPrint(
          '[ChildStatus] FCM token unavailable at startup; will retry on refresh.',
        );
      }
    } catch (error) {
      debugPrint('[ChildStatus] Initial FCM token sync failed: $error');
    }

    try {
      await _childTokenRefreshSubscription?.cancel();
      _childTokenRefreshSubscription =
          NotificationService().onTokenRefresh.listen((nextToken) {
        unawaited(writeToken(nextToken));
      }, onError: (Object error) {
        debugPrint('[ChildStatus] FCM token refresh listener failed: $error');
      });
    } catch (error) {
      debugPrint('[ChildStatus] Unable to attach FCM token listener: $error');
    }
  }

  void _ensureAccessRequestSubscription() {
    final parentId = _parentId?.trim();
    final childId = _childId?.trim();
    if (parentId == null ||
        parentId.isEmpty ||
        childId == null ||
        childId.isEmpty) {
      if (_accessRequestsSubscription != null) {
        _accessRequestsSubscription?.cancel();
        _accessRequestsSubscription = null;
        _accessRequestsSubscriptionKey = null;
      }
      return;
    }

    final nextKey = '$parentId|$childId';
    if (_accessRequestsSubscriptionKey == nextKey &&
        _accessRequestsSubscription != null) {
      return;
    }

    _accessRequestsSubscription?.cancel();
    _accessRequestsSubscription = _firestore
        .collection('parents')
        .doc(parentId)
        .collection('access_requests')
        .where('childId', isEqualTo: childId)
        .limit(50)
        .snapshots()
        .listen((_) {
      final latestChild = _lastKnownChild;
      if (latestChild == null) {
        return;
      }
      unawaited(
        _ensureProtectionApplied(
          latestChild,
          manualMode: _lastManualModeOverride,
          forceRecheck: true,
        ),
      );
    });
    _accessRequestsSubscriptionKey = nextKey;
  }

  void _ensureChildProfileSubscription() {
    final childId = _childId?.trim();
    if (childId == null || childId.isEmpty) {
      _childProfileSubscription?.cancel();
      _childProfileSubscription = null;
      _childProfileSubscriptionKey = null;
      return;
    }

    if (_childProfileSubscriptionKey == childId &&
        _childProfileSubscription != null) {
      return;
    }

    _childProfileSubscription?.cancel();
    _childProfileSubscription = _firestore
        .collection('children')
        .doc(childId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) {
        unawaited(_handleMissingChildProfile());
        unawaited(_attemptPairingRecovery());
        return;
      }
      final rawData = doc.data() ?? const <String, dynamic>{};
      _handledMissingChildProfile = false;
      final manualMode = _manualModeFromRaw(rawData['manualMode']);
      _lastManualModeOverride = manualMode;
      final parentIdFromDoc = (rawData['parentId'] as String?)?.trim();
      if ((_parentId == null || _parentId!.isEmpty) &&
          parentIdFromDoc != null &&
          parentIdFromDoc.isNotEmpty &&
          mounted) {
        setState(() {
          _parentId = parentIdFromDoc;
        });
      }
      final child = ChildProfile.fromFirestore(doc);
      _lastKnownChild = child;
      unawaited(_drainPendingPolicyEvents());
      unawaited(
        _ensureProtectionApplied(
          child,
          manualMode: manualMode,
        ),
      );
    }, onError: (Object error) {
      final isPermissionError = error is FirebaseException &&
          (error.code == 'permission-denied' ||
              error.code == 'unauthenticated');
      if (isPermissionError) {
        unawaited(_handleMissingChildProfile());
        unawaited(_attemptPairingRecovery());
      }
    });
    _childProfileSubscriptionKey = childId;
  }

  void _ensurePolicyEventSubscription() {
    final childId = _childId?.trim();
    if (childId == null || childId.isEmpty) {
      _policyEventsSubscription?.cancel();
      _policyEventsSubscription = null;
      _policyEventsSubscriptionKey = null;
      _policyEventEpochFloorMs = null;
      _pendingPolicyEvents.clear();
      _processedPolicyEventIds.clear();
      return;
    }

    final nextKey = childId;
    if (_policyEventsSubscriptionKey == nextKey &&
        _policyEventsSubscription != null) {
      return;
    }

    _policyEventsSubscription?.cancel();
    _policyEventEpochFloorMs = DateTime.now().millisecondsSinceEpoch - 5000;
    _pendingPolicyEvents.clear();
    _processedPolicyEventIds.clear();
    _policyEventsSubscription = _firestore
        .collection('children')
        .doc(childId)
        .collection('policy_events')
        .where(
          'eventEpochMs',
          isGreaterThanOrEqualTo: _policyEventEpochFloorMs,
        )
        .orderBy('eventEpochMs')
        .limitToLast(500)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          continue;
        }
        final docId = change.doc.id;
        if (_processedPolicyEventIds.contains(docId)) {
          continue;
        }
        _processedPolicyEventIds.add(docId);
        final event = _policyEventFromRaw(change.doc.data());
        if (event == null) {
          continue;
        }
        final floor = _policyEventEpochFloorMs;
        if (floor != null && event.eventEpochMs < floor) {
          continue;
        }
        debugPrint(
          '[ChildStatus] policy_event doc=${change.doc.id} '
          'epochMs=${event.eventEpochMs} '
          'cats=${event.blockedCategories.length} '
          'domains=${event.blockedDomains.length}',
        );
        final baseChild = _lastKnownChild;
        if (baseChild == null) {
          debugPrint(
            '[ChildStatus] policy_event queued (missing base child) '
            'doc=${change.doc.id}',
          );
          _pendingPolicyEvents.addLast(event);
          continue;
        }
        debugPrint(
          '[ChildStatus] policy_event applying now doc=${change.doc.id}',
        );
        unawaited(_applyPolicyEvent(baseChild, event));
      }
    }, onError: (Object error) {
      debugPrint('[ChildStatus] policy_events listener error: $error');
    });
    _policyEventsSubscriptionKey = nextKey;
  }

  _PolicyEventSnapshot? _policyEventFromRaw(Map<String, dynamic>? rawData) {
    if (rawData == null) {
      return null;
    }
    final categories = normalizeCategoryIds(
      _readStringList(rawData['blockedCategories']),
    );
    final domains = _readStringList(rawData['blockedDomains']);
    final manualMode = _manualModeFromRaw(rawData['manualMode']);
    final pausedUntil = _parseNullableDateTime(rawData['pausedUntil']);
    final eventEpochMs = _readInt(rawData['eventEpochMs']);
    return _PolicyEventSnapshot(
      blockedCategories: categories,
      blockedDomains: domains,
      manualMode: manualMode,
      pausedUntil: pausedUntil,
      eventEpochMs: eventEpochMs,
    );
  }

  Future<void> _applyPolicyEvent(
    ChildProfile baseChild,
    _PolicyEventSnapshot event,
  ) async {
    debugPrint(
      '[ChildStatus] _applyPolicyEvent '
      'cats=${event.blockedCategories.length} domains=${event.blockedDomains.length}',
    );
    final nextChild = baseChild.copyWith(
      policy: baseChild.policy.copyWith(
        blockedCategories: event.blockedCategories,
        blockedDomains: event.blockedDomains,
      ),
      pausedUntil: event.pausedUntil,
    );
    _lastKnownChild = nextChild;
    _lastManualModeOverride = event.manualMode;
    await _ensureProtectionApplied(
      nextChild,
      manualMode: event.manualMode,
      forceRecheck: true,
    );
  }

  Future<void> _drainPendingPolicyEvents() async {
    final baseChild = _lastKnownChild;
    if (baseChild == null || _pendingPolicyEvents.isEmpty) {
      return;
    }
    debugPrint(
      '[ChildStatus] draining queued policy events count=${_pendingPolicyEvents.length}',
    );
    var current = baseChild;
    while (_pendingPolicyEvents.isNotEmpty) {
      final event = _pendingPolicyEvents.removeFirst();
      final nextChild = current.copyWith(
        policy: current.policy.copyWith(
          blockedCategories: event.blockedCategories,
          blockedDomains: event.blockedDomains,
        ),
        pausedUntil: event.pausedUntil,
      );
      _lastKnownChild = nextChild;
      _lastManualModeOverride = event.manualMode;
      await _ensureProtectionApplied(
        nextChild,
        manualMode: event.manualMode,
        forceRecheck: true,
      );
      current = nextChild;
    }
  }

  List<String> _readStringList(Object? rawValue) {
    if (rawValue is! List) {
      return const <String>[];
    }
    return rawValue
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  int _readInt(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return 0;
  }

  Future<void> _refreshApprovedExceptionState(String childId) async {
    final parentId = _parentId?.trim();
    if (parentId == null || parentId.isEmpty) {
      _activeApprovedExceptionDomains = const <String>{};
      _nextApprovedExceptionExpiry = null;
      return;
    }

    final result = await Future.wait<Object?>(
      <Future<Object?>>[
        _firestoreService.getActiveApprovedExceptionDomains(
          parentId: parentId,
          childId: childId,
        ),
        _firestoreService.getNextApprovedExceptionExpiry(
          parentId: parentId,
          childId: childId,
        ),
      ],
    );

    final domains = result[0] as List<String>? ?? const <String>[];
    final nextExpiry = result[1] as DateTime?;
    _activeApprovedExceptionDomains = domains
        .map((domain) => domain.trim().toLowerCase())
        .where((domain) => domain.isNotEmpty)
        .toSet();
    _nextApprovedExceptionExpiry = nextExpiry;
  }

  Future<void> _ensureProtectionApplied(
    ChildProfile child, {
    _ManualModeOverride? manualMode,
    bool forceRecheck = false,
  }) async {
    final now = DateTime.now();
    final resolvedManualMode = manualMode ?? _lastManualModeOverride;
    final effectiveRules = _buildEffectiveProtectionRules(
      child: child,
      now: now,
      manualMode: resolvedManualMode,
    );
    final categories = effectiveRules.categories.toList()..sort();
    final domains = effectiveRules.domains.toList()..sort();
    final policySignature = '${categories.join('|')}::${domains.join('|')}';
    _scheduleNextProtectionRecheck(
      child: child,
      manualMode: resolvedManualMode,
      now: now,
      nextApprovedExceptionExpiry: _nextApprovedExceptionExpiry,
    );

    if (!forceRecheck &&
        _lastAppliedPolicySignature != null &&
        _lastAppliedPolicySignature!.startsWith('$policySignature::') &&
        !_isApplyingProtectionRules &&
        _pendingProtectionApplies.isEmpty) {
      return;
    }

    _enqueueProtectionApply(
      _QueuedProtectionApply(
        child: child,
        manualMode: resolvedManualMode,
        categories: categories,
        domains: domains,
        policySignature: policySignature,
        forceRecheck: forceRecheck,
      ),
    );
    await _drainProtectionApplyQueue();
  }

  void _enqueueProtectionApply(_QueuedProtectionApply next) {
    if (!next.forceRecheck && _pendingProtectionApplies.isNotEmpty) {
      final last = _pendingProtectionApplies.last;
      if (!last.forceRecheck && last.policySignature == next.policySignature) {
        return;
      }
    }
    _pendingProtectionApplies.addLast(next);
  }

  Future<void> _drainProtectionApplyQueue() async {
    if (_isApplyingProtectionRules) {
      debugPrint('[ChildStatus] drainProtection skipped (already applying)');
      return;
    }
    debugPrint(
      '[ChildStatus] drainProtection start queue=${_pendingProtectionApplies.length}',
    );
    _isApplyingProtectionRules = true;
    while (_pendingProtectionApplies.isNotEmpty) {
      final next = _pendingProtectionApplies.removeFirst();
      final applied = await _applyProtectionRules(next);
      if (!applied) {
        _pendingProtectionApplies.addFirst(next);
        _scheduleProtectionRetry();
        break;
      }
      if (_pendingProtectionApplies.isNotEmpty) {
        // Keep each applied state observable under rapid-fire parent edits.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    _isApplyingProtectionRules = false;
  }

  Future<bool> _applyProtectionRules(_QueuedProtectionApply next) async {
    try {
      try {
        await _refreshApprovedExceptionState(next.child.id);
      } catch (_) {
        // Access-request sync is best-effort; baseline policy still applies.
        _activeApprovedExceptionDomains = const <String>{};
        _nextApprovedExceptionExpiry = null;
      }
      final temporaryAllowedDomains = _activeApprovedExceptionDomains.toList()
        ..sort();
      final signature =
          '${next.policySignature}::${temporaryAllowedDomains.join('|')}';
      _scheduleNextProtectionRecheck(
        child: next.child,
        manualMode: next.manualMode,
        now: DateTime.now(),
        nextApprovedExceptionExpiry: _nextApprovedExceptionExpiry,
      );
      if (!next.forceRecheck && _lastAppliedPolicySignature == signature) {
        return true;
      }
      debugPrint(
        '[ChildStatus] applying rules force=${next.forceRecheck} '
        'cats=${next.categories.length} domains=${next.domains.length} '
        'allowed=${temporaryAllowedDomains.length}',
      );

      final syncedCategories = _canUseBlocklistSync()
          ? _mapPolicyCategoriesToBlocklists(next.categories)
          : <BlocklistCategory>{};

      // Auto-start VPN if protection rules exist but VPN isn't running.
      final hasRules = next.categories.isNotEmpty || next.domains.isNotEmpty;
      final vpnRunning = await _vpnService.isVpnRunning();
      if (hasRules && !vpnRunning) {
        await _vpnService.startVpn(
          blockedCategories: next.categories,
          blockedDomains: next.domains,
        );
      }

      final applied = await _replaceVpnRules(
        blockedCategories: next.categories,
        blockedDomains: next.domains,
        temporaryAllowedDomains: temporaryAllowedDomains,
      );
      if (!applied) {
        debugPrint('[ChildStatus] updateFilterRules returned false');
        _scheduleProtectionRetry();
        return false;
      }
      debugPrint('[ChildStatus] updateFilterRules applied successfully');
      if (syncedCategories.isNotEmpty) {
        unawaited(
          _syncBlocklistsInBackground(
            syncedCategories.toList(growable: false),
          ),
        );
      }
      _lastAppliedPolicySignature = signature;
      _schedulePolicyApplyHeartbeat();
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[ChildStatus] Failed to apply protection rules: $error\n$stackTrace',
      );
      _scheduleProtectionRetry();
      // Keep child UI functional even if sync fails.
      return false;
    }
  }

  Future<bool> _replaceVpnRules({
    required List<String> blockedCategories,
    required List<String> blockedDomains,
    required List<String> temporaryAllowedDomains,
  }) async {
    final cleared = await _vpnService.updateFilterRules(
      blockedCategories: const <String>[],
      blockedDomains: const <String>[],
      temporaryAllowedDomains: const <String>[],
    );
    if (!cleared) {
      debugPrint('[ChildStatus] clear-before-apply updateFilterRules failed');
      return false;
    }
    return _vpnService.updateFilterRules(
      blockedCategories: blockedCategories,
      blockedDomains: blockedDomains,
      temporaryAllowedDomains: temporaryAllowedDomains,
    );
  }

  void _scheduleProtectionRetry() {
    if (_protectionRetryScheduled) {
      return;
    }
    _protectionRetryScheduled = true;
    _protectionRetryTimer?.cancel();
    _protectionRetryTimer = Timer(const Duration(seconds: 5), () {
      _protectionRetryScheduled = false;
      if (!mounted) {
        return;
      }
      unawaited(_drainProtectionApplyQueue());
    });
  }

  void _schedulePolicyApplyHeartbeat() {
    final now = DateTime.now();
    final last = _lastPolicyApplyHeartbeatAt;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastPolicyApplyHeartbeatAt = now;
    unawaited(_sendHeartbeatOnce());
  }

  Future<void> _syncBlocklistsInBackground(
    List<BlocklistCategory> categories,
  ) async {
    try {
      await _resolvedBlocklistSyncService.syncAll(
        categories,
        forceRefresh: false,
      );
    } catch (_) {
      // Blocklist refresh should never block real-time protection.
    }
  }

  _EffectiveProtectionRules _buildEffectiveProtectionRules({
    required ChildProfile child,
    required DateTime now,
    required _ManualModeOverride? manualMode,
  }) {
    final categories =
        normalizeCategoryIds(child.policy.blockedCategories).toSet();
    final domains = child.policy.blockedDomains
        .map((domain) => domain.trim().toLowerCase())
        .where((domain) => domain.isNotEmpty)
        .toSet();

    final pauseActive =
        child.pausedUntil != null && child.pausedUntil!.isAfter(now);
    if (pauseActive) {
      categories.add(_blockAllCategory);
      _augmentDomainsFromCategories(
        categories: categories,
        domains: domains,
      );
      return _EffectiveProtectionRules(
          categories: categories, domains: domains);
    }

    final activeManualMode = _activeManualMode(manualMode, now);
    if (activeManualMode != null) {
      switch (activeManualMode.mode) {
        case 'bedtime':
          categories.add(_blockAllCategory);
          break;
        case 'homework':
          categories.addAll(_distractingCategories);
          break;
        case 'free':
          // Explicit free mode keeps only baseline policy blocks.
          break;
      }
      _augmentDomainsFromCategories(
        categories: categories,
        domains: domains,
      );
      return _EffectiveProtectionRules(
          categories: categories, domains: domains);
    }

    final activeSchedule = _activeSchedule(child.policy.schedules, now);
    if (activeSchedule != null) {
      switch (activeSchedule.action) {
        case ScheduleAction.blockAll:
          categories.add(_blockAllCategory);
          break;
        case ScheduleAction.blockDistracting:
          categories.addAll(_distractingCategories);
          break;
        case ScheduleAction.allowAll:
          break;
      }
    }

    _augmentDomainsFromCategories(
      categories: categories,
      domains: domains,
    );
    return _EffectiveProtectionRules(categories: categories, domains: domains);
  }

  void _augmentDomainsFromCategories({
    required Set<String> categories,
    required Set<String> domains,
  }) {
    if (categories.contains('social') ||
        categories.contains('social-networks')) {
      domains.addAll(SocialMediaDomains.all);
    }

    for (final category in categories) {
      final fallbackDomains = _categoryDomainFallbacks[category];
      if (fallbackDomains == null || fallbackDomains.isEmpty) {
        continue;
      }
      domains.addAll(
        fallbackDomains
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty),
      );
    }
  }

  _ManualModeOverride? _activeManualMode(
    _ManualModeOverride? manualMode,
    DateTime now,
  ) {
    if (manualMode == null) {
      return null;
    }
    return manualMode.isActiveAt(now) ? manualMode : null;
  }

  void _scheduleNextProtectionRecheck({
    required ChildProfile child,
    required _ManualModeOverride? manualMode,
    required DateTime now,
    DateTime? nextApprovedExceptionExpiry,
  }) {
    _protectionBoundaryTimer?.cancel();
    _protectionBoundaryTimer = null;
    _scheduleNextScheduleWarning(
      schedules: child.policy.schedules,
      now: now,
    );

    final candidates = <DateTime>[];
    final pausedUntil = child.pausedUntil;
    if (pausedUntil != null && pausedUntil.isAfter(now)) {
      candidates.add(pausedUntil);
    }

    final activeManual = _activeManualMode(manualMode, now);
    final manualExpiry = activeManual?.expiresAt;
    if (manualExpiry != null && manualExpiry.isAfter(now)) {
      candidates.add(manualExpiry);
    }

    final activeSchedule = _activeSchedule(child.policy.schedules, now);
    if (activeSchedule != null) {
      final scheduleEnd = _scheduleWindowForReference(activeSchedule, now).end;
      if (scheduleEnd.isAfter(now)) {
        candidates.add(scheduleEnd);
      }
    }

    final nextSchedule = _nextScheduleStart(child.policy.schedules, now);
    if (nextSchedule != null && nextSchedule.start.isAfter(now)) {
      candidates.add(nextSchedule.start);
    }

    if (nextApprovedExceptionExpiry != null &&
        nextApprovedExceptionExpiry.isAfter(now)) {
      candidates.add(nextApprovedExceptionExpiry);
    }

    if (candidates.isEmpty) {
      return;
    }

    candidates.sort((a, b) => a.compareTo(b));
    final nextBoundary = candidates.first;
    if (!nextBoundary.isAfter(now)) {
      return;
    }

    final delay = nextBoundary.difference(now) + const Duration(seconds: 1);
    _protectionBoundaryTimer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      final latestChild = _lastKnownChild;
      if (latestChild == null) {
        return;
      }
      unawaited(
        _ensureProtectionApplied(
          latestChild,
          manualMode: _lastManualModeOverride,
          forceRecheck: true,
        ),
      );
    });
  }

  void _scheduleNextScheduleWarning({
    required List<Schedule> schedules,
    required DateTime now,
  }) {
    _scheduleWarningTimer?.cancel();
    _scheduleWarningTimer = null;

    final nextSchedule = _nextScheduleStart(schedules, now);
    if (nextSchedule == null) {
      return;
    }

    final scheduleStart = nextSchedule.start;
    if (!scheduleStart.isAfter(now)) {
      return;
    }
    if (_lastWarnedScheduleStartAt != null &&
        _lastWarnedScheduleStartAt!.isAtSameMomentAs(scheduleStart)) {
      return;
    }

    final warningAt = scheduleStart.subtract(const Duration(minutes: 5));
    final delay =
        warningAt.isAfter(now) ? warningAt.difference(now) : Duration.zero;
    _scheduleWarningTimer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      if (_lastWarnedScheduleStartAt != null &&
          _lastWarnedScheduleStartAt!.isAtSameMomentAs(scheduleStart)) {
        return;
      }
      _lastWarnedScheduleStartAt = scheduleStart;
      unawaited(
        _showScheduleStartWarning(
          schedule: nextSchedule.schedule,
          startAt: scheduleStart,
        ),
      );
    });
  }

  Future<void> _showScheduleStartWarning({
    required Schedule schedule,
    required DateTime startAt,
  }) async {
    final modeName = _modeNameForSchedule(schedule);
    final formattedStart = DateFormat('h:mm a').format(startAt);
    final title = '$modeName starts in 5 minutes';
    final body = 'Get ready. $modeName begins at $formattedStart.';
    await NotificationService().showLocalNotification(
      title: title,
      body: body,
      route: '/child/status',
    );
  }

  bool _canUseBlocklistSync() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Set<BlocklistCategory> _mapPolicyCategoriesToBlocklists(
    List<String> policyCategories,
  ) {
    final mapped = <BlocklistCategory>{};
    for (final rawCategory in policyCategories) {
      final category = normalizeCategoryId(rawCategory);
      switch (category) {
        case 'social-networks':
          mapped.add(BlocklistCategory.social);
          break;
        case 'ads':
          mapped.add(BlocklistCategory.ads);
          break;
        case 'adult-content':
          mapped.add(BlocklistCategory.adult);
          break;
        case 'gambling':
          mapped.add(BlocklistCategory.gambling);
          break;
        case 'malware':
          mapped.add(BlocklistCategory.malware);
          break;
      }
    }
    return mapped;
  }

  _ManualModeOverride? _manualModeFromRaw(Object? rawValue) {
    if (rawValue is! Map) {
      return null;
    }
    final map = rawValue.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final mode = (map['mode'] as String?)?.trim().toLowerCase();
    if (mode == null || mode.isEmpty) {
      return null;
    }

    final expiresAt = _parseNullableDateTime(map['expiresAt']);
    final setAt = _parseNullableDateTime(map['setAt']);
    return _ManualModeOverride(
      mode: mode,
      expiresAt: expiresAt,
      setAt: setAt,
    );
  }

  DateTime? _parseNullableDateTime(Object? rawValue) {
    if (rawValue is Timestamp) {
      return rawValue.toDate();
    }
    if (rawValue is DateTime) {
      return rawValue;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingContext) {
      return const Center(child: CircularProgressIndicator());
    }

    final childId = _childId;
    if (childId == null || childId.isEmpty) {
      _scheduleSetupRedirect();
      return _buildMissingState(
        context,
        message: 'Setup is incomplete. Ask your parent for help.',
      );
    }
    _ensureAccessRequestSubscription();
    _ensureChildProfileSubscription();
    _ensurePolicyEventSubscription();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('children').doc(childId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final isPermissionError = error is FirebaseException &&
              (error.code == 'permission-denied' ||
                  error.code == 'unauthenticated');
          if (isPermissionError) {
            unawaited(_handleMissingChildProfile());
            unawaited(_attemptPairingRecovery());
            return _buildMissingState(
              context,
              message:
                  'This phone is no longer paired. Ask your parent to reconnect setup.',
            );
          }
          return _buildMissingState(
            context,
            message:
                'Could not load child profile. Tap Restart setup and reconnect.',
          );
        }
        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          unawaited(_handleMissingChildProfile());
          unawaited(_attemptPairingRecovery());
          return _buildMissingState(
            context,
            message:
                'Child profile not found. Ask your parent to reconnect setup.',
          );
        }
        final rawData = doc.data() ?? const <String, dynamic>{};
        _handledMissingChildProfile = false;
        final manualMode = _manualModeFromRaw(rawData['manualMode']);
        _lastManualModeOverride = manualMode;
        final parentIdFromDoc = (rawData['parentId'] as String?)?.trim();
        if ((_parentId == null || _parentId!.isEmpty) &&
            parentIdFromDoc != null &&
            parentIdFromDoc.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _parentId = parentIdFromDoc;
            });
          });
        }
        final child = ChildProfile.fromFirestore(doc);
        _lastKnownChild = child;
        unawaited(_drainPendingPolicyEvents());
        unawaited(
          _ensureProtectionApplied(
            child,
            manualMode: manualMode,
          ),
        );
        return _buildContent(
          context,
          child,
          manualMode: manualMode,
        );
      },
    );
  }

  Future<void> _attemptPairingRecovery() async {
    if (_recoveringPairing) {
      return;
    }
    _recoveringPairing = true;
    try {
      final recovered = await _resolvedPairingService.recoverPairingFromCloud();
      if (!mounted || recovered == null) {
        return;
      }
      setState(() {
        _parentId = recovered.parentId;
        _childId = recovered.childId;
      });
    } finally {
      _recoveringPairing = false;
    }
  }

  Future<void> _handleMissingChildProfile() async {
    if (_handledMissingChildProfile) {
      return;
    }
    _handledMissingChildProfile = true;
    _pendingProtectionApplies.clear();
    _isApplyingProtectionRules = false;
    _policyEventsSubscription?.cancel();
    _policyEventsSubscription = null;
    _childProfileSubscription?.cancel();
    _childProfileSubscription = null;
    _childProfileSubscriptionKey = null;
    _policyEventsSubscriptionKey = null;
    _pendingPolicyEvents.clear();
    _processedPolicyEventIds.clear();
    _lastAppliedPolicySignature = null;
    _lastPolicyApplyHeartbeatAt = null;
    _activeApprovedExceptionDomains = const <String>{};
    _nextApprovedExceptionExpiry = null;

    try {
      await _vpnService.updateFilterRules(
        blockedCategories: const <String>[],
        blockedDomains: const <String>[],
        temporaryAllowedDomains: const <String>[],
      );
    } catch (_) {
      // Best-effort cleanup.
    }

    try {
      await _vpnService.stopVpn();
    } catch (_) {
      // Best-effort cleanup.
    }

    try {
      await _resolvedPairingService.clearLocalPairing();
    } catch (_) {
      // Best-effort cleanup.
    }

    try {
      await NotificationService().showLocalNotification(
        title: 'Protection turned off',
        body:
            'This phone is no longer paired. Ask your parent to reconnect setup.',
        route: '/child/setup',
      );
    } catch (_) {
      // Best-effort user visibility.
    }
  }

  Widget _buildMissingState(BuildContext context, {required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () async {
                await _resolvedPairingService.clearLocalPairing();
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pushReplacementNamed('/child/setup');
              },
              child: const Text('Restart setup'),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleSetupRedirect() {
    if (_redirectingToSetup || !mounted) {
      return;
    }
    _redirectingToSetup = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacementNamed('/child/setup');
    });
  }

  Widget _buildPrivateDnsWarning() {
    return FutureBuilder<VpnStatus>(
      future: _vpnService.getStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final status = snapshot.data!;
        if (!status.privateDnsActive) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            border: Border.all(color: Colors.amber.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.amber.shade800, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Private DNS is blocking protection',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your device uses Private DNS which bypasses TrustBridge protection. '
                      'Ask your parent to turn off Private DNS in Settings → Network.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 32,
                      child: OutlinedButton.icon(
                        onPressed: () => _vpnService.openPrivateDnsSettings(),
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text(
                          'Open DNS Settings',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: BorderSide(color: Colors.amber.shade700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ChildProfile child, {
    required _ManualModeOverride? manualMode,
  }) {
    final now = DateTime.now();
    final pausedUntil = child.pausedUntil;
    final pauseActive = pausedUntil != null && pausedUntil.isAfter(now);
    final pausedUntilValue = pausedUntil;
    final activeManualMode = _activeManualMode(manualMode, now);
    final activeSchedule = activeManualMode == null
        ? _activeSchedule(child.policy.schedules, now)
        : null;
    final activeScheduleWindow = activeSchedule == null
        ? null
        : _scheduleWindowForReference(activeSchedule, now);
    final modeConfig = activeManualMode == null
        ? _modeConfig(activeSchedule)
        : _manualModeConfig(activeManualMode.mode);
    final modeActiveUntil =
        activeManualMode?.expiresAt ?? activeScheduleWindow?.end;
    final nextModeStart = _nextScheduleStart(child.policy.schedules, now);
    final progress = activeManualMode == null
        ? _scheduleProgress(
            activeSchedule,
            now,
            window: activeScheduleWindow,
          )
        : (_manualModeProgress(activeManualMode, now) ??
            _scheduleProgress(
              activeSchedule,
              now,
              window: activeScheduleWindow,
            ));
    final blockedApps = _blockedAppsForEffectiveRules(
      child: child,
      pauseActive: pauseActive,
      activeSchedule: activeSchedule,
      activeManualMode: activeManualMode,
    );
    final hasParentContext = (_parentId?.isNotEmpty ?? false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Hi, ${child.nickname} 👋',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 14),
        _buildPrivateDnsWarning(),
        if (hasParentContext)
          _buildApprovalBanner(
            context: context,
            parentId: _parentId ?? '',
            childId: child.id,
          ),
        if (hasParentContext) const SizedBox(height: 12),
        if (pauseActive && pausedUntilValue != null)
          _buildPausedCard(context, pausedUntilValue)
        else
          ModeDisplayCard(
            modeName: modeConfig.name,
            modeEmoji: modeConfig.emoji,
            activeUntil: modeActiveUntil,
            cardColor: modeConfig.color,
            progress: progress,
            subtitle: modeConfig.subtitle,
          ),
        const SizedBox(height: 14),
        BlockedAppsList(
          blockedAppKeys: blockedApps,
          onAppTap: (appName) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RequestAccessScreen(
                  prefilledAppName: appName,
                  parentId: _parentId,
                  childId: child.id,
                  childNickname: child.nickname,
                  firestore: _firestore,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        if (pauseActive && pausedUntilValue != null)
          Text(
            'Free time starts at ${DateFormat('h:mm a').format(pausedUntilValue)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          )
        else if (activeManualMode != null && modeActiveUntil != null)
          Text(
            'Free time starts at ${DateFormat('h:mm a').format(modeActiveUntil)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          )
        else if (activeSchedule == null && nextModeStart != null)
          Text(
            '${_modeNameForSchedule(nextModeStart.schedule)} starts at ${DateFormat('h:mm a').format(nextModeStart.start)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          )
        else if (activeSchedule != null)
          Text(
            'Free time starts at ${DateFormat('h:mm a').format(activeScheduleWindow?.end ?? _scheduleEndDate(activeSchedule, now))} 🎮',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RequestAccessScreen(
                    parentId: _parentId,
                    childId: child.id,
                    childNickname: child.nickname,
                    firestore: _firestore,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.volunteer_activism),
            label: const Text('Ask for access'),
          ),
        ),
      ],
    );
  }

  Widget _buildPausedCard(BuildContext context, DateTime pausedUntil) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Internet is paused ⏸️',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your parent paused internet access.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Resumes at ${DateFormat('h:mm a').format(pausedUntil)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalBanner({
    required BuildContext context,
    required String parentId,
    required String childId,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('parents')
          .doc(parentId)
          .collection('access_requests')
          .where('childId', isEqualTo: childId)
          .limit(25)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        AccessRequest? latestApproved;
        for (final doc in docs) {
          final request = AccessRequest.fromFirestore(doc);
          if (request.effectiveStatus(now: DateTime.now()) ==
              RequestStatus.approved) {
            if (latestApproved == null ||
                request.requestedAt.isAfter(latestApproved.requestedAt)) {
              latestApproved = request;
            }
          }
        }

        if (latestApproved == null) {
          return const SizedBox.shrink();
        }

        final durationLabel = latestApproved.duration.label;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '✅ ${latestApproved.appOrSite} approved for $durationLabel',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w700,
                ),
          ),
        );
      },
    );
  }

  ({String name, String emoji, Color color, String subtitle}) _modeConfig(
    Schedule? schedule,
  ) {
    if (schedule == null) {
      return (
        name: 'Free Time',
        emoji: '🎮',
        color: Colors.green,
        subtitle: 'No restrictions right now',
      );
    }
    switch (schedule.type) {
      case ScheduleType.homework:
      case ScheduleType.school:
        return (
          name: 'Study Mode',
          emoji: '📚',
          color: Colors.blue,
          subtitle: 'Stay focused and finish strong.',
        );
      case ScheduleType.bedtime:
        return (
          name: 'Bedtime Mode',
          emoji: '🌙',
          color: Colors.indigo,
          subtitle: 'Wind down and recharge for tomorrow.',
        );
      case ScheduleType.custom:
        return (
          name: 'Focus Mode',
          emoji: '🎯',
          color: Colors.blueGrey,
          subtitle: 'A custom family focus window is active.',
        );
    }
  }

  ({String name, String emoji, Color color, String subtitle}) _manualModeConfig(
    String mode,
  ) {
    switch (mode) {
      case 'homework':
        return (
          name: 'Study Mode',
          emoji: '📚',
          color: Colors.blue,
          subtitle: 'Your parent enabled homework focus mode.',
        );
      case 'bedtime':
        return (
          name: 'Bedtime Mode',
          emoji: '🌙',
          color: Colors.indigo,
          subtitle: 'Your parent enabled bedtime lock mode.',
        );
      case 'free':
        return (
          name: 'Free Time',
          emoji: '🎮',
          color: Colors.green,
          subtitle: 'No restrictions right now',
        );
      default:
        return (
          name: 'Focus Mode',
          emoji: '🎯',
          color: Colors.blueGrey,
          subtitle: 'Temporary protection mode is active.',
        );
    }
  }

  String _modeNameForSchedule(Schedule schedule) {
    switch (schedule.type) {
      case ScheduleType.homework:
      case ScheduleType.school:
        return 'Study mode';
      case ScheduleType.bedtime:
        return 'Bedtime mode';
      case ScheduleType.custom:
        return 'Focus mode';
    }
  }

  List<String> _blockedAppsForEffectiveRules({
    required ChildProfile child,
    required bool pauseActive,
    required Schedule? activeSchedule,
    required _ManualModeOverride? activeManualMode,
  }) {
    final apps = <String>{};
    final categories = child.policy.blockedCategories
        .map((category) => category.trim().toLowerCase())
        .toSet();
    final domains = child.policy.blockedDomains
        .map((domain) => domain.trim().toLowerCase())
        .where((domain) => domain.isNotEmpty)
        .toSet();

    if (pauseActive) {
      categories.add(_blockAllCategory);
    } else if (activeManualMode != null) {
      if (activeManualMode.mode == 'homework') {
        categories.addAll(_distractingCategories);
      } else if (activeManualMode.mode == 'bedtime') {
        categories.add(_blockAllCategory);
      }
    } else if (activeSchedule != null) {
      switch (activeSchedule.action) {
        case ScheduleAction.blockAll:
          categories.add(_blockAllCategory);
          break;
        case ScheduleAction.blockDistracting:
          categories.addAll(_distractingCategories);
          break;
        case ScheduleAction.allowAll:
          break;
      }
    }

    if (categories.contains(_blockAllCategory) ||
        categories.contains('social') ||
        categories.contains('social-networks') ||
        categories.intersection(_distractingCategories).isNotEmpty) {
      apps.addAll(SocialMediaDomains.byApp.keys);
    }

    for (final domain in domains) {
      final app = SocialMediaDomains.appForDomain(domain);
      if (app != null) {
        apps.add(app);
      }
    }

    return apps.toList()..sort();
  }

  double? _manualModeProgress(_ManualModeOverride mode, DateTime now) {
    final expiresAt = mode.expiresAt;
    final setAt = mode.setAt;
    if (expiresAt == null || setAt == null) {
      return null;
    }
    final totalMs = expiresAt.difference(setAt).inMilliseconds;
    if (totalMs <= 0) {
      return null;
    }
    final elapsedMs = now.difference(setAt).inMilliseconds.clamp(0, totalMs);
    return elapsedMs / totalMs;
  }

  Schedule? _activeSchedule(List<Schedule> schedules, DateTime now) {
    final today = Day.fromDateTime(now);
    final yesterday = Day.fromDateTime(now.subtract(const Duration(days: 1)));
    for (final schedule in schedules) {
      if (!schedule.enabled) {
        continue;
      }

      if (schedule.days.contains(today)) {
        final start = _scheduleStartDate(schedule, now);
        final end = _scheduleEndDate(schedule, now);
        if ((now.isAfter(start) || now.isAtSameMomentAs(start)) &&
            now.isBefore(end)) {
          return schedule;
        }
      }

      if (_crossesMidnight(schedule) && schedule.days.contains(yesterday)) {
        final previousDay = now.subtract(const Duration(days: 1));
        final start = _scheduleStartDate(schedule, previousDay);
        final end = _scheduleEndDate(schedule, previousDay);
        if ((now.isAfter(start) || now.isAtSameMomentAs(start)) &&
            now.isBefore(end)) {
          return schedule;
        }
      }
    }
    return null;
  }

  ({Schedule schedule, DateTime start})? _nextScheduleStart(
    List<Schedule> schedules,
    DateTime now,
  ) {
    ({Schedule schedule, DateTime start})? next;
    for (final schedule in schedules) {
      if (!schedule.enabled) {
        continue;
      }
      for (var dayOffset = 0; dayOffset <= 7; dayOffset++) {
        final candidateDay = now.add(Duration(days: dayOffset));
        final day = Day.fromDateTime(candidateDay);
        if (!schedule.days.contains(day)) {
          continue;
        }
        final start = _scheduleStartDate(schedule, candidateDay);
        if (!start.isAfter(now)) {
          continue;
        }
        if (next == null || start.isBefore(next.start)) {
          next = (schedule: schedule, start: start);
        }
      }
    }
    return next;
  }

  double _scheduleProgress(
    Schedule? schedule,
    DateTime now, {
    ({DateTime start, DateTime end})? window,
  }) {
    if (schedule == null) {
      return 0;
    }
    final resolvedWindow = window ?? _scheduleWindowForReference(schedule, now);
    final start = resolvedWindow.start;
    final end = resolvedWindow.end;
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    final elapsed = now.difference(start).inMilliseconds.clamp(0, total);
    return elapsed / total;
  }

  bool _crossesMidnight(Schedule schedule) {
    final start = _parseTimeOfDay(schedule.startTime);
    final end = _parseTimeOfDay(schedule.endTime);
    final startMinutes = start.$1 * 60 + start.$2;
    final endMinutes = end.$1 * 60 + end.$2;
    return endMinutes <= startMinutes;
  }

  DateTime _scheduleStartDate(Schedule schedule, DateTime base) {
    final parts = schedule.startTime.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  DateTime _scheduleEndDate(Schedule schedule, DateTime base) {
    final parts = schedule.endTime.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    var end = DateTime(base.year, base.month, base.day, hour, minute);
    final start = _scheduleStartDate(schedule, base);
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    return end;
  }

  ({DateTime start, DateTime end}) _scheduleWindowForReference(
    Schedule schedule,
    DateTime reference,
  ) {
    if (!_crossesMidnight(schedule)) {
      return (
        start: _scheduleStartDate(schedule, reference),
        end: _scheduleEndDate(schedule, reference),
      );
    }

    final endTime = _parseTimeOfDay(schedule.endTime);
    final endToday = DateTime(
      reference.year,
      reference.month,
      reference.day,
      endTime.$1,
      endTime.$2,
    );
    if (reference.isBefore(endToday)) {
      final previousDay = reference.subtract(const Duration(days: 1));
      return (
        start: _scheduleStartDate(schedule, previousDay),
        end: _scheduleEndDate(schedule, previousDay),
      );
    }

    return (
      start: _scheduleStartDate(schedule, reference),
      end: _scheduleEndDate(schedule, reference),
    );
  }

  (int, int) _parseTimeOfDay(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (hour, minute);
  }
}

class _EffectiveProtectionRules {
  const _EffectiveProtectionRules({
    required this.categories,
    required this.domains,
  });

  final Set<String> categories;
  final Set<String> domains;
}

class _QueuedProtectionApply {
  const _QueuedProtectionApply({
    required this.child,
    required this.manualMode,
    required this.categories,
    required this.domains,
    required this.policySignature,
    required this.forceRecheck,
  });

  final ChildProfile child;
  final _ManualModeOverride? manualMode;
  final List<String> categories;
  final List<String> domains;
  final String policySignature;
  final bool forceRecheck;
}

class _PolicyEventSnapshot {
  const _PolicyEventSnapshot({
    required this.blockedCategories,
    required this.blockedDomains,
    required this.manualMode,
    required this.pausedUntil,
    required this.eventEpochMs,
  });

  final List<String> blockedCategories;
  final List<String> blockedDomains;
  final _ManualModeOverride? manualMode;
  final DateTime? pausedUntil;
  final int eventEpochMs;
}

class _ManualModeOverride {
  const _ManualModeOverride({
    required this.mode,
    this.expiresAt,
    this.setAt,
  });

  final String mode;
  final DateTime? expiresAt;
  final DateTime? setAt;

  bool isActiveAt(DateTime now) {
    if (expiresAt == null) {
      return true;
    }
    return expiresAt!.isAfter(now);
  }
}
