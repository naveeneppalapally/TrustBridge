import 'dart:async';

import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
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
  AuthService? _authService;
  FirestoreService? _firestoreService;
  bool _updatingPause = false;

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
      ),
      body: StreamBuilder<List<ChildProfile>>(
        stream: _resolvedFirestoreService.getChildrenStream(parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
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

          final rawChildren = snapshot.data ?? const <ChildProfile>[];
          final children = _dedupeChildren(rawChildren);
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
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AddChildScreen(
                              authService: widget.authService,
                              firestoreService: widget.firestoreService,
                              parentIdOverride: widget.parentIdOverride,
                            ),
                          ),
                        );
                      },
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
            builder: (context, statusSnapshot) {
              final statusByDeviceId =
                  statusSnapshot.data ?? const <String, DeviceStatusSnapshot>{};

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
    final protectedNow = child.protectionEnabled && vpnActive;

    final statusLabel = !online
        ? 'Offline'
        : (protectedNow ? 'Protected right now' : 'Not protected right now');

    return _ChildLiveStatus(
      protectedNow: protectedNow,
      modeLabel: _modeLabelForNow(child, now),
      statusLabel: statusLabel,
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
