import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
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
    _days = (schedule?.days ?? const {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Editor'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'ROUTINE TYPE',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 10),
          _buildRoutineTypeRow(),
          const SizedBox(height: 18),
          _buildTimeCard(),
          const SizedBox(height: 18),
          Text(
            'DAYS',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 10),
          _buildDaySelector(),
          const SizedBox(height: 18),
          Text(
            'RESTRICTION LEVEL',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 10),
          _buildRestrictionCard(
            key: const Key('schedule_block_distractions_card'),
            title: 'Block Distractions',
            subtitle:
                'Social media, games, and streaming apps are restricted during this routine.',
            action: ScheduleAction.blockDistracting,
          ),
          const SizedBox(height: 10),
          _buildRestrictionCard(
            key: const Key('schedule_block_all_card'),
            title: 'Block Everything',
            subtitle:
                'Total lockout. Only emergency calls and essential apps stay available.',
            action: ScheduleAction.blockAll,
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            key: const Key('schedule_remind_toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind child 5m before'),
            value: _remindBefore,
            onChanged: (value) => setState(() => _remindBefore = value),
          ),
          const SizedBox(height: 10),
          _buildSummaryCard(context),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              key: const Key('schedule_save_button'),
              onPressed: _isLoading ? null : _saveChanges,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save Routine',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
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

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: types
            .map(
              (type) => Expanded(
                child: GestureDetector(
                  key: Key('schedule_type_${type.name}'),
                  onTap: () => setState(() {
                    _type = type;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _type == type ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _typeLabel(type),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight:
                            _type == type ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildTimeCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                  color: Colors.grey.withValues(alpha: 0.30),
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
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeSlot({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: Day.values.map((day) {
        final selected = _days.contains(day);
        return InkWell(
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
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? const Color(0xFF207CF8) : Colors.transparent,
              border: Border.all(
                color: selected
                    ? const Color(0xFF207CF8)
                    : Colors.grey.withValues(alpha: 0.50),
              ),
            ),
            child: Center(
              child: Text(
                _dayLabel(day),
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildRestrictionCard({
    required Key key,
    required String title,
    required String subtitle,
    required ScheduleAction action,
  }) {
    final selected = _action == action;
    return InkWell(
      key: key,
      onTap: () => setState(() => _action = action),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                selected ? const Color(0xFF207CF8) : Colors.grey.withValues(alpha: 0.40),
            width: selected ? 2 : 1,
          ),
          color: selected ? const Color(0x1A207CF8) : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              action == ScheduleAction.blockAll
                  ? Icons.block
                  : Icons.shield_outlined,
              color: selected ? const Color(0xFF207CF8) : Colors.grey[700],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[700],
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Color(0xFF207CF8)),
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
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'ROUTINE SUMMARY · $dayText, ${_formatTime(_startTime)} - ${_formatTime(_endTime)} · ${_actionLabel(_action)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'ACTIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
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

      final updatedPolicy = widget.child.policy.copyWith(
        schedules: schedules,
      );
      final updatedChild = widget.child.copyWith(policy: updatedPolicy);

      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );

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
    final startMinutes =
        (int.tryParse(startParts[0]) ?? 0) * 60 + (int.tryParse(startParts[1]) ?? 0);
    final endMinutes =
        (int.tryParse(endParts[0]) ?? 0) * 60 + (int.tryParse(endParts[1]) ?? 0);

    var diff = endMinutes - startMinutes;
    if (diff <= 0) {
      diff += 24 * 60;
    }

    final hours = diff ~/ 60;
    final mins = diff % 60;
    return '${hours}h ${mins.toString().padLeft(2, '0')}m';
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
        return 'Block Everything';
      case ScheduleAction.blockDistracting:
        return 'Block Distractions';
      case ScheduleAction.allowAll:
        return 'Allow All';
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
        return 'M';
      case Day.tuesday:
        return 'T';
      case Day.wednesday:
        return 'W';
      case Day.thursday:
        return 'T';
      case Day.friday:
        return 'F';
      case Day.saturday:
        return 'S';
      case Day.sunday:
        return 'S';
    }
  }
}
