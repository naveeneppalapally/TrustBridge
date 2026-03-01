import 'dart:async';

import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/skeleton_loaders.dart';
import 'add_child_screen.dart';
import 'child_control_screen.dart';

class ChildrenHomeScreen extends StatefulWidget {
  const ChildrenHomeScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<ChildrenHomeScreen> createState() => _ChildrenHomeScreenState();
}

class _ChildrenHomeScreenState extends State<ChildrenHomeScreen> {
  static const Duration _policyAckProtectedWindow = Duration(minutes: 30);
  static const Duration _vpnDiagnosticsFreshnessWindow = Duration(minutes: 3);

  AuthService? _authService;
  FirestoreService? _firestoreService;
  bool _updatingPause = false;
  List<ChildProfile> _lastChildrenSnapshot = const <ChildProfile>[];
  Map<String, DeviceStatusSnapshot> _lastStatusSnapshotByDeviceId =
      const <String, DeviceStatusSnapshot>{};
  final Map<String, StreamSubscription<dynamic>> _policyAckSubscriptionsByChildId =
      <String, StreamSubscription<dynamic>>{};
  final Map<String, _ChildPolicyAckSnapshot> _latestPolicyAckByChildId =
      <String, _ChildPolicyAckSnapshot>{};
  String _policyAckSubscriptionFingerprint = '';
  final Map<String, StreamSubscription<dynamic>>
      _vpnDiagnosticsSubscriptionsByChildId =
      <String, StreamSubscription<dynamic>>{};
  final Map<String, _ChildVpnDiagnosticsSnapshot>
      _latestVpnDiagnosticsByChildId = <String, _ChildVpnDiagnosticsSnapshot>{};
  String _vpnDiagnosticsSubscriptionFingerprint = '';

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  String? get _parentId {
    final override = widget.parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return _resolvedAuthService.currentUser?.uid;
  }

  @override
  void dispose() {
    for (final subscription in _policyAckSubscriptionsByChildId.values) {
      subscription.cancel();
    }
    _policyAckSubscriptionsByChildId.clear();
    for (final subscription in _vpnDiagnosticsSubscriptionsByChildId.values) {
      subscription.cancel();
    }
    _vpnDiagnosticsSubscriptionsByChildId.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view your children.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Children'),
        actions: [
          IconButton(
            key: const Key('children_home_add_child_button'),
            tooltip: 'Add Child',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: _openAddChild,
          ),
        ],
      ),
      body: StreamBuilder<List<ChildProfile>>(
        stream: _resolvedFirestoreService.getChildrenStream(parentId),
        initialData: _lastChildrenSnapshot.isNotEmpty
            ? _lastChildrenSnapshot
            : _resolvedFirestoreService.getCachedChildren(parentId),
        builder: (context, snapshot) {
          final streamChildren = snapshot.data ?? const <ChildProfile>[];
          if (streamChildren.isNotEmpty) {
            _lastChildrenSnapshot = streamChildren;
          }

          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Children are unavailable right now. Please try again.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final rawChildren = streamChildren.isNotEmpty
              ? streamChildren
              : _lastChildrenSnapshot;
          final children = _dedupeChildren(rawChildren);
          _ensurePolicyAckSubscriptions(children);
          _ensureVpnDiagnosticsSubscriptions(children);
          if (children.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: const [
                SkeletonChildCard(),
                SizedBox(height: 12),
                SkeletonChildCard(),
              ],
            );
          }
          if (children.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.family_restroom, size: 56),
                    const SizedBox(height: 12),
                    const Text(
                      'No children added yet.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add a child to start protection controls.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _openAddChild,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Child'),
                    ),
                  ],
                ),
              ),
            );
          }

          final childIdByDeviceId = <String, String>{
            for (final child in children)
              for (final rawDeviceId in child.deviceIds)
                if (rawDeviceId.trim().isNotEmpty) rawDeviceId.trim(): child.id,
          };
          final deviceIds = childIdByDeviceId.keys.toList(growable: false);

          return StreamBuilder<Map<String, DeviceStatusSnapshot>>(
            stream: _resolvedFirestoreService.watchDeviceStatuses(
              deviceIds,
              parentId: parentId,
              childIdByDeviceId: childIdByDeviceId,
            ),
            initialData: _lastStatusSnapshotByDeviceId,
            builder: (context, statusSnapshot) {
              final statusByDeviceId =
                  statusSnapshot.data ?? _lastStatusSnapshotByDeviceId;
              if (statusByDeviceId.isNotEmpty) {
                _lastStatusSnapshotByDeviceId = statusByDeviceId;
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                itemBuilder: (context, index) {
                  final child = children[index];
                  final live = _liveStatus(child, statusByDeviceId);
                  return _ChildOverviewCard(
                    child: child,
                    protectedNow: live.protectedNow,
                    modeLabel: live.modeLabel,
                    statusLabel: live.statusLabel,
                    pauseBusy: _updatingPause,
                    onPausePressed: () => _togglePause(child, parentId),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChildControlScreen(
                            childId: child.id,
                            initialChild: child,
                            authService: widget.authService,
                            firestoreService: widget.firestoreService,
                            parentIdOverride: widget.parentIdOverride,
                          ),
                        ),
                      );
                    },
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: children.length,
              );
            },
          );
        },
      ),
    );
  }

  _ChildLiveStatus _liveStatus(
    ChildProfile child,
    Map<String, DeviceStatusSnapshot> statusByDeviceId,
  ) {
    DateTime? freshestSeen;
    bool vpnActive = false;

    for (final rawDeviceId in child.deviceIds) {
      final deviceId = rawDeviceId.trim();
      if (deviceId.isEmpty) {
        continue;
      }
      final snapshot = statusByDeviceId[deviceId];
      if (snapshot == null) {
        continue;
      }
      final candidate = snapshot.lastSeen ?? snapshot.updatedAt;
      if (candidate != null &&
          (freshestSeen == null || candidate.isAfter(freshestSeen))) {
        freshestSeen = candidate;
      }
      if (snapshot.vpnActive) {
        vpnActive = true;
      }
    }

    final now = DateTime.now();
    final online =
        freshestSeen != null && now.difference(freshestSeen).inMinutes <= 10;
    final latestAck = _latestPolicyAckByChildId[child.id];
    final ackSupportsProtection = latestAck != null &&
        now.difference(latestAck.sortTime) <= _policyAckProtectedWindow &&
        latestAck.vpnRunning &&
        !latestAck.hasFailureStatus;
    final diagnostics = _latestVpnDiagnosticsByChildId[child.id];
    final diagnosticsSupportProtection = diagnostics != null &&
        now.difference(diagnostics.updatedAt) <= _vpnDiagnosticsFreshnessWindow &&
        diagnostics.vpnRunning;
    final protectedNow = online &&
        (vpnActive || diagnosticsSupportProtection || ackSupportsProtection);

    final statusLabel = !online
        ? 'Offline'
        : (protectedNow ? 'Protected right now' : 'Not protected right now');

    return _ChildLiveStatus(
      protectedNow: protectedNow,
      modeLabel: _modeLabelForNow(child, now),
      statusLabel: statusLabel,
    );
  }

  void _ensurePolicyAckSubscriptions(List<ChildProfile> children) {
    final childIds = children
        .map((child) => child.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    final nextFingerprint = childIds.join('|');
    if (nextFingerprint == _policyAckSubscriptionFingerprint) {
      return;
    }
    _policyAckSubscriptionFingerprint = nextFingerprint;

    final nextChildIdSet = childIds.toSet();
    final staleChildIds = _policyAckSubscriptionsByChildId.keys
        .where((childId) => !nextChildIdSet.contains(childId))
        .toList(growable: false);

    for (final childId in staleChildIds) {
      _policyAckSubscriptionsByChildId.remove(childId)?.cancel();
      _latestPolicyAckByChildId.remove(childId);
    }

    for (final childId in childIds) {
      if (_policyAckSubscriptionsByChildId.containsKey(childId)) {
        continue;
      }
      final subscription = _resolvedFirestoreService.firestore
          .collection('children')
          .doc(childId)
          .collection('policy_apply_acks')
          .snapshots()
          .listen(
        (snapshot) {
          if (!mounted) {
            return;
          }
          _ChildPolicyAckSnapshot? newest;
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (data.isEmpty) {
              continue;
            }
            final candidate = _ChildPolicyAckSnapshot.fromMap(data);
            if (candidate == null) {
              continue;
            }
            if (newest == null || candidate.sortTime.isAfter(newest.sortTime)) {
              newest = candidate;
            }
          }

          final existing = _latestPolicyAckByChildId[childId];
          if (newest == null) {
            if (existing != null) {
              setState(() {
                _latestPolicyAckByChildId.remove(childId);
              });
            }
            return;
          }
          if (existing == newest) {
            return;
          }
          setState(() {
            _latestPolicyAckByChildId[childId] = newest!;
          });
        },
        onError: (_, __) {
          if (!mounted) {
            return;
          }
          if (_latestPolicyAckByChildId.containsKey(childId)) {
            setState(() {
              _latestPolicyAckByChildId.remove(childId);
            });
          }
        },
      );
      _policyAckSubscriptionsByChildId[childId] = subscription;
    }
  }

  void _ensureVpnDiagnosticsSubscriptions(List<ChildProfile> children) {
    final childIds = children
        .map((child) => child.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    final nextFingerprint = childIds.join('|');
    if (nextFingerprint == _vpnDiagnosticsSubscriptionFingerprint) {
      return;
    }
    _vpnDiagnosticsSubscriptionFingerprint = nextFingerprint;

    final nextChildIdSet = childIds.toSet();
    final staleChildIds = _vpnDiagnosticsSubscriptionsByChildId.keys
        .where((childId) => !nextChildIdSet.contains(childId))
        .toList(growable: false);

    for (final childId in staleChildIds) {
      _vpnDiagnosticsSubscriptionsByChildId.remove(childId)?.cancel();
      _latestVpnDiagnosticsByChildId.remove(childId);
    }

    for (final childId in childIds) {
      if (_vpnDiagnosticsSubscriptionsByChildId.containsKey(childId)) {
        continue;
      }
      final subscription = _resolvedFirestoreService.firestore
          .collection('children')
          .doc(childId)
          .collection('vpn_diagnostics')
          .doc('current')
          .snapshots()
          .listen(
        (snapshot) {
          if (!mounted) {
            return;
          }
          final data = snapshot.data();
          final nextValue = (data == null || data.isEmpty)
              ? null
              : _ChildVpnDiagnosticsSnapshot.fromMap(data);
          final existing = _latestVpnDiagnosticsByChildId[childId];
          if (nextValue == null) {
            if (existing != null) {
              setState(() {
                _latestVpnDiagnosticsByChildId.remove(childId);
              });
            }
            return;
          }
          if (existing == nextValue) {
            return;
          }
          setState(() {
            _latestVpnDiagnosticsByChildId[childId] = nextValue;
          });
        },
        onError: (_, __) {
          if (!mounted) {
            return;
          }
          if (_latestVpnDiagnosticsByChildId.containsKey(childId)) {
            setState(() {
              _latestVpnDiagnosticsByChildId.remove(childId);
            });
          }
        },
      );
      _vpnDiagnosticsSubscriptionsByChildId[childId] = subscription;
    }
  }

  void _openAddChild() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddChildScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  List<ChildProfile> _dedupeChildren(List<ChildProfile> children) {
    if (children.length <= 1) {
      return children;
    }

    final bestByKey = <String, ChildProfile>{};
    for (final child in children) {
      final key =
          '${child.nickname.trim().toLowerCase()}::${child.ageBand.value}';
      final existing = bestByKey[key];
      if (existing == null) {
        bestByKey[key] = child;
        continue;
      }
      if (_childIdentityPriority(child) > _childIdentityPriority(existing)) {
        bestByKey[key] = child;
      }
    }

    final deduped = bestByKey.values.toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return deduped;
  }

  int _childIdentityPriority(ChildProfile child) {
    final linkedDeviceCount = child.deviceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .length;
    var score = linkedDeviceCount * 1000000;
    score += child.protectionEnabled ? 100000 : 0;
    score += child.updatedAt.millisecondsSinceEpoch ~/ 1000;
    return score;
  }

  String _modeLabelForNow(ChildProfile child, DateTime now) {
    final pausedUntil = child.pausedUntil;
    if (pausedUntil != null && pausedUntil.isAfter(now)) {
      return 'Lockdown';
    }

    final manualMode =
        (child.manualMode?['mode'] as String?)?.trim().toLowerCase();
    final manualExpires = child.manualMode?['expiresAt'];
    final manualExpiresAt = manualExpires is DateTime ? manualExpires : null;
    if (manualMode != null && manualMode.isNotEmpty) {
      if (manualExpiresAt != null && !manualExpiresAt.isAfter(now)) {
        // Expired manual mode; fall back to schedule.
      } else {
        switch (manualMode) {
          case 'homework':
            return 'Homework';
          case 'bedtime':
            return 'Bedtime';
          case 'free':
            return 'Free Play';
          default:
            return 'Focus';
        }
      }
    }

    final activeSchedule = _activeSchedule(child.policy.schedules, now);
    if (activeSchedule == null) {
      return 'Free Play';
    }
    switch (activeSchedule.action) {
      case ScheduleAction.blockAll:
        return 'Bedtime';
      case ScheduleAction.blockDistracting:
        return 'Homework';
      case ScheduleAction.allowAll:
        return 'Free Play';
    }
  }

  Schedule? _activeSchedule(List<Schedule> schedules, DateTime now) {
    for (final schedule in schedules) {
      if (!schedule.enabled) {
        continue;
      }
      final window = _scheduleWindowForReference(schedule, now);
      if (!now.isBefore(window.start) && now.isBefore(window.end)) {
        return schedule;
      }
    }
    return null;
  }

  ({DateTime start, DateTime end}) _scheduleWindowForReference(
    Schedule schedule,
    DateTime reference,
  ) {
    final endSameDay = _crossesMidnight(schedule.startTime, schedule.endTime);
    final todayStart = _scheduleStartDate(schedule, reference);
    final todayEnd = _scheduleEndDate(schedule, reference);
    final yesterday = reference.subtract(const Duration(days: 1));
    final yesterdayStart = _scheduleStartDate(schedule, yesterday);
    final yesterdayEnd = _scheduleEndDate(schedule, yesterday);

    final todayAllowed = schedule.days.contains(Day.fromDateTime(reference));
    final yesterdayAllowed =
        schedule.days.contains(Day.fromDateTime(yesterday));

    if (endSameDay && yesterdayAllowed && reference.isBefore(todayEnd)) {
      return (start: yesterdayStart, end: yesterdayEnd);
    }

    if (todayAllowed) {
      return (start: todayStart, end: todayEnd);
    }

    if (endSameDay && yesterdayAllowed) {
      return (start: yesterdayStart, end: yesterdayEnd);
    }

    return (start: todayStart, end: todayEnd);
  }

  bool _crossesMidnight(String start, String end) {
    final (startHour, startMinute) = _parseTimeOfDay(start);
    final (endHour, endMinute) = _parseTimeOfDay(end);
    if (endHour > startHour) {
      return false;
    }
    if (endHour == startHour && endMinute > startMinute) {
      return false;
    }
    return true;
  }

  DateTime _scheduleStartDate(Schedule schedule, DateTime reference) {
    final (hour, minute) = _parseTimeOfDay(schedule.startTime);
    return DateTime(
      reference.year,
      reference.month,
      reference.day,
      hour,
      minute,
    );
  }

  DateTime _scheduleEndDate(Schedule schedule, DateTime reference) {
    final (hour, minute) = _parseTimeOfDay(schedule.endTime);
    final candidate = DateTime(
      reference.year,
      reference.month,
      reference.day,
      hour,
      minute,
    );
    if (_crossesMidnight(schedule.startTime, schedule.endTime) &&
        !candidate.isAfter(_scheduleStartDate(schedule, reference))) {
      return candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  (int, int) _parseTimeOfDay(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (hour, minute);
  }

  Future<void> _togglePause(ChildProfile child, String parentId) async {
    if (_updatingPause) {
      return;
    }

    final now = DateTime.now();
    final paused = child.pausedUntil != null && child.pausedUntil!.isAfter(now);
    setState(() {
      _updatingPause = true;
    });
    try {
      await _resolvedFirestoreService.setChildPause(
        parentId: parentId,
        childId: child.id,
        pausedUntil: paused ? null : now.add(const Duration(hours: 8)),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paused
                ? 'Internet resumed for ${child.nickname}.'
                : 'Internet paused for ${child.nickname}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update internet pause right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingPause = false;
        });
      }
    }
  }
}

class _ChildOverviewCard extends StatelessWidget {
  const _ChildOverviewCard({
    required this.child,
    required this.protectedNow,
    required this.modeLabel,
    required this.statusLabel,
    required this.pauseBusy,
    required this.onPausePressed,
    required this.onTap,
  });

  final ChildProfile child;
  final bool protectedNow;
  final String modeLabel;
  final String statusLabel;
  final bool pauseBusy;
  final VoidCallback onPausePressed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final paused = child.pausedUntil != null && child.pausedUntil!.isAfter(now);
    final statusColor =
        protectedNow ? Colors.green.shade700 : Colors.orange.shade700;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                child.nickname,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                statusLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mode: $modeLabel',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: pauseBusy ? null : onPausePressed,
                  icon: Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  label:
                      Text(paused ? 'Resume Internet' : 'Pause Internet Now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildLiveStatus {
  const _ChildLiveStatus({
    required this.protectedNow,
    required this.modeLabel,
    required this.statusLabel,
  });

  final bool protectedNow;
  final String modeLabel;
  final String statusLabel;
}

class _ChildPolicyAckSnapshot {
  const _ChildPolicyAckSnapshot({
    required this.appliedAt,
    required this.updatedAt,
    required this.applyStatus,
    required this.vpnRunning,
  });

  final DateTime? appliedAt;
  final DateTime? updatedAt;
  final String applyStatus;
  final bool vpnRunning;

  DateTime get sortTime =>
      updatedAt ?? appliedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasFailureStatus {
    final normalized = applyStatus.trim().toLowerCase();
    return normalized == 'failed' ||
        normalized == 'error' ||
        normalized == 'mismatch';
  }

  static _ChildPolicyAckSnapshot? fromMap(Map<String, dynamic> data) {
    final applyStatus = (data['applyStatus'] as String?)?.trim();
    if (applyStatus == null || applyStatus.isEmpty) {
      return null;
    }
    return _ChildPolicyAckSnapshot(
      appliedAt: _toDateTime(data['appliedAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      applyStatus: applyStatus,
      vpnRunning: data['vpnRunning'] == true,
    );
  }

  static DateTime? _toDateTime(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      final epochMs = value.toInt();
      if (epochMs <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(epochMs);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    final dynamic raw = value;
    try {
      final DateTime? timestampValue = raw?.toDate();
      return timestampValue;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _ChildPolicyAckSnapshot &&
        other.appliedAt == appliedAt &&
        other.updatedAt == updatedAt &&
        other.applyStatus == applyStatus &&
        other.vpnRunning == vpnRunning;
  }

  @override
  int get hashCode => Object.hash(
        appliedAt,
        updatedAt,
        applyStatus,
        vpnRunning,
      );
}

class _ChildVpnDiagnosticsSnapshot {
  const _ChildVpnDiagnosticsSnapshot({
    required this.updatedAt,
    required this.vpnRunning,
  });

  final DateTime updatedAt;
  final bool vpnRunning;

  static _ChildVpnDiagnosticsSnapshot? fromMap(Map<String, dynamic> data) {
    final updatedAt = _ChildPolicyAckSnapshot._toDateTime(data['updatedAt']);
    if (updatedAt == null) {
      return null;
    }
    return _ChildVpnDiagnosticsSnapshot(
      updatedAt: updatedAt,
      vpnRunning: data['vpnRunning'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _ChildVpnDiagnosticsSnapshot &&
        other.updatedAt == updatedAt &&
        other.vpnRunning == vpnRunning;
  }

  @override
  int get hashCode => Object.hash(updatedAt, vpnRunning);
}
