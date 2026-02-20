import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../models/schedule.dart';

enum ChildModeState {
  freeTime,
  focusMode,
  bedtime,
  school,
}

class ChildCard extends StatelessWidget {
  const ChildCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onPauseInternet,
    this.onResumeInternet,
    this.onLocate,
    this.deviceName,
    this.usageMinutesOverride,
    this.usageLimitMinutesOverride,
    this.deviceHealthStatusLabel,
    this.deviceHealthStatusColor,
  });

  final ChildProfile child;
  final VoidCallback onTap;
  final VoidCallback? onPauseInternet;
  final VoidCallback? onResumeInternet;
  final VoidCallback? onLocate;
  final String? deviceName;
  final int? usageMinutesOverride;
  final int? usageLimitMinutesOverride;
  final String? deviceHealthStatusLabel;
  final Color? deviceHealthStatusColor;

  bool _isPausedNow() {
    final pausedUntil = child.pausedUntil;
    return pausedUntil != null && pausedUntil.isAfter(DateTime.now());
  }

  bool _isOnline() {
    return child.deviceIds.isNotEmpty;
  }

  ChildModeState _activeModeState() {
    final now = TimeOfDay.now();
    final today = Day.fromDateTime(DateTime.now());
    for (final schedule in child.policy.schedules) {
      if (!schedule.enabled) {
        continue;
      }
      if (!schedule.days.contains(today)) {
        continue;
      }
      if (!_isTimeInRange(now, schedule.startTime, schedule.endTime)) {
        continue;
      }

      switch (schedule.type) {
        case ScheduleType.bedtime:
          return ChildModeState.bedtime;
        case ScheduleType.school:
          return ChildModeState.school;
        case ScheduleType.homework:
        case ScheduleType.custom:
          return ChildModeState.focusMode;
      }
    }
    return ChildModeState.freeTime;
  }

  bool _isTimeInRange(TimeOfDay current, String start, String end) {
    try {
      final startParts = start.split(':');
      final endParts = end.split(':');
      if (startParts.length != 2 || endParts.length != 2) {
        return false;
      }

      final startMinutes =
          int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      final currentMinutes = current.hour * 60 + current.minute;

      if (startMinutes > endMinutes) {
        return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
      }
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } catch (_) {
      return false;
    }
  }

  int _dailyLimitMinutes() {
    final override = usageLimitMinutesOverride;
    if (override != null && override > 0) {
      return override;
    }

    switch (child.ageBand) {
      case AgeBand.young:
        return 120;
      case AgeBand.middle:
        return 150;
      case AgeBand.teen:
        return 180;
    }
  }

  int _usageMinutes() {
    final override = usageMinutesOverride;
    if (override != null && override >= 0) {
      return override;
    }

    final limit = _dailyLimitMinutes();
    if (_isPausedNow()) {
      return (limit * 0.35).round();
    }
    return _isOnline() ? (limit * 0.58).round() : (limit * 0.42).round();
  }

  String _formatDuration(int totalMinutes) {
    final safeMinutes = totalMinutes < 0 ? 0 : totalMinutes;
    final hours = safeMinutes ~/ 60;
    final minutes = safeMinutes % 60;
    if (hours == 0) {
      return '${minutes}m';
    }
    return '${hours}h ${minutes}m';
  }

  ({String label, Color color}) _modeMeta(ChildModeState mode) {
    switch (mode) {
      case ChildModeState.freeTime:
        return (label: 'Free Time', color: const Color(0xFF22C55E));
      case ChildModeState.focusMode:
        return (label: 'Focus Mode', color: const Color(0xFFF59E0B));
      case ChildModeState.bedtime:
        return (label: 'Bedtime', color: const Color(0xFF8B5CF6));
      case ChildModeState.school:
        return (label: 'School', color: const Color(0xFF3B82F6));
    }
  }

  String _resolvedDeviceName() {
    if (deviceName != null && deviceName!.trim().isNotEmpty) {
      return deviceName!.trim();
    }
    if (child.deviceIds.isNotEmpty) {
      return child.deviceIds.first;
    }
    return 'No linked device';
  }

  Color _avatarColor() {
    switch (child.ageBand) {
      case AgeBand.young:
        return const Color(0xFF38BDF8);
      case AgeBand.middle:
        return const Color(0xFF22C55E);
      case AgeBand.teen:
        return const Color(0xFFF97316);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paused = _isPausedNow();
    final online = _isOnline();
    final mode = _activeModeState();
    final modeMeta = _modeMeta(mode);
    final usageMinutes = _usageMinutes();
    final usageLimitMinutes = _dailyLimitMinutes();
    final usageRatio = usageLimitMinutes == 0
        ? 0.0
        : (usageMinutes / usageLimitMinutes).clamp(0.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: _avatarColor(),
                        child: Text(
                          child.nickname.isEmpty
                              ? '?'
                              : child.nickname[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color:
                                online ? const Color(0xFF00A86B) : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).cardColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          child.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          key: const Key('child_card_mode_badge'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: modeMeta.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '● ${modeMeta.label}',
                            style: TextStyle(
                              color: modeMeta.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          paused ? 'Internet paused' : 'Now: ${modeMeta.label}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade500,
                                  ),
                        ),
                        if (deviceHealthStatusLabel != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: (deviceHealthStatusColor ?? Colors.orange)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              deviceHealthStatusLabel!,
                              style: TextStyle(
                                color: deviceHealthStatusColor ?? Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: online
                              ? const Color(0xFF22C55E).withValues(alpha: 0.14)
                              : Colors.grey.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          online ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            color: online
                                ? const Color(0xFF22C55E)
                                : Colors.grey.shade700,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _resolvedDeviceName(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'TIME USAGE',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '${_formatDuration(usageMinutes)} / ${_formatDuration(usageLimitMinutes)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${(usageRatio * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: usageRatio,
                  backgroundColor: Colors.blue.withValues(alpha: 0.14),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF1E88E5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      key: Key(
                        paused
                            ? 'child_card_resume_button'
                            : 'child_card_pause_button',
                      ),
                      onPressed: paused ? onResumeInternet : onPauseInternet,
                      icon: Icon(
                        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        size: 18,
                      ),
                      label: Text(paused ? 'Resume' : 'Pause Internet'),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFF1E88E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('child_card_locate_button'),
                      onPressed: onLocate,
                      icon: const Icon(Icons.near_me_outlined, size: 18),
                      label: const Text('Locate'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
