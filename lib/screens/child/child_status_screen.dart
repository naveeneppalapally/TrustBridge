import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/social_media_domains.dart';
import '../../models/access_request.dart';
import '../../models/child_profile.dart';
import '../../models/schedule.dart';
import '../../services/pairing_service.dart';
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

class _ChildStatusScreenState extends State<ChildStatusScreen> {
  late final FirebaseFirestore _firestore;
  PairingService? _pairingService;
  PairingService get _resolvedPairingService {
    _pairingService ??= PairingService();
    return _pairingService!;
  }

  String? _parentId;
  String? _childId;
  bool _loadingContext = true;

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseFirestore.instance;
    _parentId = widget.parentId?.trim();
    _childId = widget.childId?.trim();
    unawaited(_resolveContext());
  }

  Future<void> _resolveContext() async {
    if ((_parentId?.isNotEmpty ?? false) && (_childId?.isNotEmpty ?? false)) {
      if (mounted) {
        setState(() {
          _loadingContext = false;
        });
      }
      return;
    }
    final parentId = await _resolvedPairingService.getPairedParentId();
    final childId = await _resolvedPairingService.getPairedChildId();
    if (!mounted) {
      return;
    }
    setState(() {
      _parentId = _parentId ?? parentId;
      _childId = _childId ?? childId;
      _loadingContext = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingContext) {
      return const Center(child: CircularProgressIndicator());
    }

    final childId = _childId;
    if (childId == null || childId.isEmpty) {
      return _buildMissingState(
        context,
        message: 'Setup is incomplete. Ask your parent for help.',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('children').doc(childId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          return _buildMissingState(
            context,
            message: 'Child profile not found. Ask your parent to reconnect setup.',
          );
        }
        final child = ChildProfile.fromFirestore(doc);
        return _buildContent(context, child);
      },
    );
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

  Widget _buildContent(BuildContext context, ChildProfile child) {
    final now = DateTime.now();
    final pausedUntil = child.pausedUntil;
    final pauseActive = pausedUntil != null && pausedUntil.isAfter(now);
    final pausedUntilValue = pausedUntil;

    final activeSchedule = _activeSchedule(child.policy.schedules, now);
    final modeConfig = _modeConfig(activeSchedule);
    final nextModeStart = _nextScheduleStart(child.policy.schedules, now);
    final progress = _scheduleProgress(activeSchedule, now);
    final blockedApps = _blockedAppsForPolicy(child);
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
            activeUntil: activeSchedule == null
                ? null
                : _scheduleEndDate(activeSchedule, now),
            cardColor: modeConfig.color,
            progress: progress,
            subtitle: activeSchedule == null
                ? 'No restrictions right now'
                : modeConfig.subtitle,
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
        if (activeSchedule == null && nextModeStart != null)
          Text(
            '${_modeNameForSchedule(nextModeStart.schedule)} starts at ${DateFormat('h:mm a').format(nextModeStart.start)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          )
        else if (activeSchedule != null)
          Text(
            'Free time starts at ${DateFormat('h:mm a').format(_scheduleEndDate(activeSchedule, now))} 🎮',
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
          if (request.effectiveStatus(now: DateTime.now()) == RequestStatus.approved) {
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

  List<String> _blockedAppsForPolicy(ChildProfile child) {
    final apps = <String>{};
    final categories = child.policy.blockedCategories
        .map((category) => category.trim().toLowerCase())
        .toSet();

    if (categories.contains('social') || categories.contains('social-networks')) {
      apps.addAll(SocialMediaDomains.byApp.keys);
    }

    for (final domain in child.policy.blockedDomains) {
      final app = SocialMediaDomains.appForDomain(domain);
      if (app != null) {
        apps.add(app);
      }
    }

    return apps.toList()..sort();
  }

  Schedule? _activeSchedule(List<Schedule> schedules, DateTime now) {
    final day = Day.fromDateTime(now);
    for (final schedule in schedules) {
      if (!schedule.enabled || !schedule.days.contains(day)) {
        continue;
      }
      final start = _scheduleStartDate(schedule, now);
      final end = _scheduleEndDate(schedule, now);
      if ((now.isAfter(start) || now.isAtSameMomentAs(start)) &&
          now.isBefore(end)) {
        return schedule;
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

  double _scheduleProgress(Schedule? schedule, DateTime now) {
    if (schedule == null) {
      return 0;
    }
    final start = _scheduleStartDate(schedule, now);
    final end = _scheduleEndDate(schedule, now);
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    final elapsed = now.difference(start).inMilliseconds.clamp(0, total);
    return elapsed / total;
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
}
