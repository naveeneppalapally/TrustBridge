import 'package:flutter/material.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';
import 'package:trustbridge_app/core/utils/responsive.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/remote_command_service.dart';
import 'package:trustbridge_app/theme/app_text_styles.dart';
import 'package:trustbridge_app/theme/app_theme.dart';
import 'package:uuid/uuid.dart';

class ScheduleCreatorScreen extends StatefulWidget {
  const ScheduleCreatorScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<ScheduleCreatorScreen> createState() => _ScheduleCreatorScreenState();
}

class _ScheduleCreatorScreenState extends State<ScheduleCreatorScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;

  late ScheduleType _type;
  late ScheduleAction _action;
  late Set<Day> _days;
  late String _startTime;
  late String _endTime;
  bool _remindBefore = true;
  bool _isLoading = false;
  Schedule? _sourceSchedule;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  @override
  void initState() {
    super.initState();
    final schedule = widget.child.policy.schedules.isNotEmpty
        ? widget.child.policy.schedules.first
        : null;
    _sourceSchedule = schedule;
    _type = schedule?.type ?? ScheduleType.bedtime;
    _action = schedule?.action ?? ScheduleAction.blockDistracting;
    _days = (schedule?.days ??
            const {
              Day.monday,
              Day.tuesday,
              Day.wednesday,
              Day.thursday,
              Day.friday,
            })
        .toSet();
    _startTime = schedule?.startTime ?? '21:00';
    _endTime = schedule?.endTime ?? '07:30';
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(R.sp(8), R.sp(8), R.sp(8), 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(R.sp(20), R.sp(4), R.sp(20), 0),
              child: Text(
                'Edit Schedule',
                style: AppTextStyles.displayMedium(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  R.sp(20), 0, R.sp(20), R.sp(24),
                ),
                children: [
                  Text(
                    'Set when this rule should run. You can change this anytime.',
                    style: AppTextStyles.bodySmall(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'SCHEDULE TYPE',
                    style: AppTextStyles.labelCaps(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildRoutineTypeRow(),
                  const SizedBox(height: 10),
                  _buildRoutineDescriptionCard(),
                  const SizedBox(height: 18),
                  Text(
                    'TIME WINDOW',
                    style: AppTextStyles.labelCaps(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildTimeCard(),
                  const SizedBox(height: 18),
                  Text(
                    'REPEAT ON',
                    style: AppTextStyles.labelCaps(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildDaySelector(),
                  const SizedBox(height: 18),
                  Text(
                    'DURING THIS TIME',
                    style: AppTextStyles.labelCaps(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildRestrictionCard(
                    key: const Key('schedule_block_distractions_card'),
                    title: 'Homework Focus',
                    subtitle:
                        'Blocks social media, games, and streaming.\nCalls and communication stay available.',
                    action: ScheduleAction.blockDistracting,
                  ),
                  const SizedBox(height: 10),
                  _buildRestrictionCard(
                    key: const Key('schedule_block_all_card'),
                    title: 'Sleep Lock',
                    subtitle:
                        'Blocks internet and app access during this window.\nBest for bedtime.',
                    action: ScheduleAction.blockAll,
                  ),
                  const SizedBox(height: 10),
                  _buildRestrictionCard(
                    key: const Key('schedule_allow_all_card'),
                    title: 'Reminder Only',
                    subtitle:
                        'No blocks. Keeps this as a reminder schedule only.',
                    action: ScheduleAction.allowAll,
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    key: const Key('schedule_remind_toggle'),
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Remind 5 minutes before start',
                            style: AppTextStyles.body(),
                          ),
                        ),
                        Switch.adaptive(
                          value: _remindBefore,
                          onChanged: (value) =>
                              setState(() => _remindBefore = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildSummaryCard(context),
                  const SizedBox(height: 16),
                  GestureDetector(
                    key: const Key('schedule_save_button'),
                    onTap: _isLoading ? null : _saveChanges,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _isLoading
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.bg,
                                ),
                              )
                            : Text(
                                'Save Schedule',
                                style: AppTextStyles.headingMedium(
                                  color: AppColors.bg,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutineTypeRow() {
    final types = <ScheduleType>[
      ScheduleType.bedtime,
      ScheduleType.school,
      ScheduleType.homework,
      ScheduleType.custom,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((type) {
        return ChoiceChip(
          key: Key('schedule_type_${type.name}'),
          label: Text(_typeLabel(type)),
          selected: _type == type,
          onSelected: (_) => setState(() => _type = type),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildRoutineDescriptionCard() {
    return Container(
      key: const Key('schedule_routine_description_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryDim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        _typeDescription(_type),
        key: const Key('schedule_routine_description_text'),
        style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildDayPresetChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          label: const Text('Weekdays'),
          onPressed: () => _applyDayPreset(
            const {
              Day.monday,
              Day.tuesday,
              Day.wednesday,
              Day.thursday,
              Day.friday,
            },
          ),
        ),
        ActionChip(
          label: const Text('Weekend'),
          onPressed: () => _applyDayPreset(
            const {Day.saturday, Day.sunday},
          ),
        ),
        ActionChip(
          label: const Text('Every day'),
          onPressed: () => _applyDayPreset(Day.values.toSet()),
        ),
      ],
    );
  }

  void _applyDayPreset(Set<Day> days) {
    setState(() {
      _days = days.toSet();
    });
  }

  Widget _buildTimeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _timeSlot(
                  label: 'STARTS',
                  value: _formatTime(_startTime),
                  onTap: () => _pickTime(isStart: true),
                ),
              ),
              Container(
                width: 1,
                height: 56,
                color: AppColors.surfaceBorder,
              ),
              Expanded(
                child: _timeSlot(
                  label: 'ENDS',
                  value: _formatTime(_endTime),
                  onTap: () => _pickTime(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_durationBetween(_startTime, _endTime)} total',
              style: AppTextStyles.label(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeSlot({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: AppTextStyles.labelCaps(color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.heroNumber(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDayPresetChips(),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: Day.values.map((day) {
            final selected = _days.contains(day);
            return GestureDetector(
              key: Key('schedule_day_${day.name}'),
              onTap: () {
                setState(() {
                  if (selected) {
                    _days.remove(day);
                  } else {
                    _days.add(day);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryDim
                      : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.surfaceBorder,
                  ),
                ),
                child: Text(
                  _dayLabel(day),
                  style: AppTextStyles.label(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildRestrictionCard({
    required Key key,
    required String title,
    required String subtitle,
    required ScheduleAction action,
  }) {
    final selected = _action == action;
    return GestureDetector(
      key: key,
      onTap: () => setState(() => _action = action),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.surfaceBorder,
            width: selected ? 2 : 1,
          ),
          color: selected ? AppColors.primaryDim : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              action == ScheduleAction.blockAll
                  ? Icons.block
                  : action == ScheduleAction.allowAll
                      ? Icons.notifications_active_outlined
                      : Icons.shield_outlined,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.headingMedium(
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final dayText = _formatSelectedDays(_days);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUMMARY',
            style: AppTextStyles.labelCaps(color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          Text(
            '$dayText \u2022 ${_formatTime(_startTime)} to ${_formatTime(_endTime)}',
            style: AppTextStyles.body(),
          ),
          const SizedBox(height: 4),
          Text(
            'Rule: ${_actionLabel(_action)}',
            style: AppTextStyles.label(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = _parseTime(isStart ? _startTime : _endTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked == null || !mounted) {
      return;
    }
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isStart) {
        _startTime = hhmm;
      } else {
        _endTime = hhmm;
      }
    });
  }

  Future<void> _saveChanges() async {
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one day')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final parentId =
          widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      final updatedSchedule = Schedule(
        id: _sourceSchedule?.id ?? const Uuid().v4(),
        name: _typeLabel(_type),
        type: _type,
        days: _sortedDays(_days),
        startTime: _startTime,
        endTime: _endTime,
        enabled: true,
        action: _action,
      );

      final schedules = List<Schedule>.from(widget.child.policy.schedules);
      final existingIndex = schedules.indexWhere(
        (schedule) => schedule.id == updatedSchedule.id,
      );
      if (existingIndex >= 0) {
        schedules[existingIndex] = updatedSchedule;
      } else {
        final sameTypeIndex = schedules.indexWhere(
          (schedule) => schedule.type == updatedSchedule.type,
        );
        if (sameTypeIndex >= 0) {
          schedules[sameTypeIndex] = updatedSchedule;
        } else {
          schedules.add(updatedSchedule);
        }
      }

      final conflicts = _findScheduleConflicts(
        candidate: updatedSchedule,
        existingSchedules: schedules
            .where(
              (schedule) =>
                  schedule.id != updatedSchedule.id && schedule.enabled,
            )
            .toList(growable: false),
      );
      if (conflicts.isNotEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          final previewLines = conflicts.take(3).map((conflict) {
            return '${_dayName(conflict.day)} • ${conflict.scheduleName}';
          }).join('\n');
          final overflowLine = conflicts.length > 3
              ? '\n+${conflicts.length - 3} more overlap(s)'
              : '';
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Schedule conflict'),
              content: Text(
                'This schedule overlaps with another active schedule:\n'
                '$previewLines$overflowLine\n\n'
                'Adjust the time or disable the conflicting schedule first.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final updatedPolicy = widget.child.policy.copyWith(
        schedules: schedules,
      );
      final updatedChild = widget.child.copyWith(policy: updatedPolicy);

      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );

      if (RolloutFlags.policySyncTriggerRemoteCommand &&
          widget.child.deviceIds.isNotEmpty) {
        final remoteCommandService = RemoteCommandService();
        for (final deviceId in widget.child.deviceIds) {
          remoteCommandService.sendRestartVpnCommand(deviceId).catchError(
                (_) => '',
              );
        }
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schedules updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(updatedChild);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save Failed'),
          content: Text('Failed to update schedules: $error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  List<Day> _sortedDays(Set<Day> days) {
    final sorted = days.toList()
      ..sort((a, b) => Day.values.indexOf(a).compareTo(Day.values.indexOf(b)));
    return sorted;
  }

  String _formatSelectedDays(Set<Day> days) {
    if (days.length == Day.values.length) {
      return 'Every day';
    }
    const weekdays = {
      Day.monday,
      Day.tuesday,
      Day.wednesday,
      Day.thursday,
      Day.friday,
    };
    if (days.containsAll(weekdays) && days.length == weekdays.length) {
      return 'Mon-Fri';
    }
    return _sortedDays(days).map(_dayLabel).join(', ');
  }

  String _durationBetween(String start, String end) {
    final startParts = start.split(':');
    final endParts = end.split(':');
    if (startParts.length != 2 || endParts.length != 2) {
      return '--';
    }
    final startMinutes = (int.tryParse(startParts[0]) ?? 0) * 60 +
        (int.tryParse(startParts[1]) ?? 0);
    final endMinutes = (int.tryParse(endParts[0]) ?? 0) * 60 +
        (int.tryParse(endParts[1]) ?? 0);

    var diff = endMinutes - startMinutes;
    if (diff <= 0) {
      diff += 24 * 60;
    }

    final hours = diff ~/ 60;
    final mins = diff % 60;
    return '${hours}h ${mins.toString().padLeft(2, '0')}m';
  }

  List<_ScheduleConflict> _findScheduleConflicts({
    required Schedule candidate,
    required List<Schedule> existingSchedules,
  }) {
    final conflicts = <_ScheduleConflict>[];
    final candidateWindowsByDay = _windowsByDay(candidate);

    for (final schedule in existingSchedules) {
      final otherWindowsByDay = _windowsByDay(schedule);
      for (final day in Day.values) {
        final candidateWindows =
            candidateWindowsByDay[day] ?? const <_MinuteWindow>[];
        final otherWindows = otherWindowsByDay[day] ?? const <_MinuteWindow>[];
        if (candidateWindows.isEmpty || otherWindows.isEmpty) {
          continue;
        }

        final overlaps = candidateWindows.any((candidateWindow) {
          return otherWindows.any(
            (otherWindow) => _windowsOverlap(candidateWindow, otherWindow),
          );
        });
        if (overlaps) {
          conflicts.add(
            _ScheduleConflict(
              day: day,
              scheduleName: schedule.name,
            ),
          );
          break;
        }
      }
    }

    return conflicts;
  }

  Map<Day, List<_MinuteWindow>> _windowsByDay(Schedule schedule) {
    final result = <Day, List<_MinuteWindow>>{
      for (final day in Day.values) day: <_MinuteWindow>[],
    };
    final startMinutes = _toMinutes(schedule.startTime);
    final endMinutes = _toMinutes(schedule.endTime);

    for (final day in schedule.days) {
      if (endMinutes > startMinutes) {
        _appendWindow(result, day, startMinutes, endMinutes);
      } else {
        _appendWindow(result, day, startMinutes, 24 * 60);
        _appendWindow(result, _nextDay(day), 0, endMinutes);
      }
    }

    return result;
  }

  void _appendWindow(
    Map<Day, List<_MinuteWindow>> windowsByDay,
    Day day,
    int start,
    int end,
  ) {
    if (end <= start) {
      return;
    }
    windowsByDay[day]?.add(_MinuteWindow(start: start, end: end));
  }

  bool _windowsOverlap(_MinuteWindow left, _MinuteWindow right) {
    return left.start < right.end && right.start < left.end;
  }

  Day _nextDay(Day day) {
    final index = Day.values.indexOf(day);
    return Day.values[(index + 1) % Day.values.length];
  }

  int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) {
      return 0;
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return (hour * 60) + minute;
  }

  String _typeLabel(ScheduleType type) {
    switch (type) {
      case ScheduleType.bedtime:
        return 'Bedtime';
      case ScheduleType.school:
        return 'School';
      case ScheduleType.homework:
        return 'Study';
      case ScheduleType.custom:
        return 'Custom';
    }
  }

  String _actionLabel(ScheduleAction action) {
    switch (action) {
      case ScheduleAction.blockAll:
        return 'Sleep Lock';
      case ScheduleAction.blockDistracting:
        return 'Homework Focus';
      case ScheduleAction.allowAll:
        return 'Reminder Only';
    }
  }

  String _typeDescription(ScheduleType type) {
    switch (type) {
      case ScheduleType.bedtime:
        return 'Best for night time. Keeps internet use off during sleep hours.';
      case ScheduleType.school:
        return 'Good for class hours. Keeps attention on study activities.';
      case ScheduleType.homework:
        return 'Good for homework. Blocks distractions and supports focus.';
      case ScheduleType.custom:
        return 'Use custom when you want your own time window and rules.';
    }
  }

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) {
      return hhmm;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return hhmm;
    }
    final period = hour >= 12 ? 'PM' : 'AM';
    final normalizedHour = hour % 12 == 0 ? 12 : hour % 12;
    final minuteText = minute.toString().padLeft(2, '0');
    return '$normalizedHour:$minuteText $period';
  }

  String _dayLabel(Day day) {
    switch (day) {
      case Day.monday:
        return 'Mon';
      case Day.tuesday:
        return 'Tue';
      case Day.wednesday:
        return 'Wed';
      case Day.thursday:
        return 'Thu';
      case Day.friday:
        return 'Fri';
      case Day.saturday:
        return 'Sat';
      case Day.sunday:
        return 'Sun';
    }
  }

  String _dayName(Day day) {
    switch (day) {
      case Day.monday:
        return 'Monday';
      case Day.tuesday:
        return 'Tuesday';
      case Day.wednesday:
        return 'Wednesday';
      case Day.thursday:
        return 'Thursday';
      case Day.friday:
        return 'Friday';
      case Day.saturday:
        return 'Saturday';
      case Day.sunday:
        return 'Sunday';
    }
  }
}

class _MinuteWindow {
  const _MinuteWindow({
    required this.start,
    required this.end,
  });

  final int start;
  final int end;
}

class _ScheduleConflict {
  const _ScheduleConflict({
    required this.day,
    required this.scheduleName,
  });

  final Day day;
  final String scheduleName;
}
