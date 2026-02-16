import 'package:flutter/foundation.dart';
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

  late final List<Schedule> _initialSchedules;
  late List<Schedule> _schedules;

  bool _isLoading = false;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  bool get _hasChanges => !_scheduleListsEqual(_initialSchedules, _schedules);

  @override
  void initState() {
    super.initState();
    _initialSchedules = _cloneSchedules(widget.child.policy.schedules);
    _schedules = _cloneSchedules(widget.child.policy.schedules);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Creator'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveChanges,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'SAVE',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Custom'),
        tooltip: 'Add custom schedule',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Time Restrictions',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_schedules.length} ${_schedules.length == 1 ? 'schedule' : 'schedules'} configured',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 14),
          _buildTemplateActions(context),
          const SizedBox(height: 16),
          if (_schedules.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No schedules yet. Add a preset or create a custom schedule.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ),
            )
          else
            ..._schedules.asMap().entries.map(
                  (entry) => _buildScheduleCard(
                    context,
                    index: entry.key,
                    schedule: entry.value,
                  ),
                ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildTemplateActions(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Templates',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _addBedtimeTemplate,
                  icon: const Icon(Icons.bedtime, size: 16),
                  label: const Text('Add Bedtime'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _addSchoolTemplate,
                  icon: const Icon(Icons.school, size: 16),
                  label: const Text('Add School'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _addHomeworkTemplate,
                  icon: const Icon(Icons.menu_book, size: 16),
                  label: const Text('Add Homework'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(
    BuildContext context, {
    required int index,
    required Schedule schedule,
  }) {
    final color = schedule.enabled ? Colors.orange : Colors.grey;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_iconForType(schedule.type), color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)} • ${_formatDays(schedule.days)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: schedule.enabled,
                  onChanged: _isLoading
                      ? null
                      : (value) => _updateSchedule(
                            index,
                            _copySchedule(schedule, enabled: value),
                          ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_actionLabel(schedule.action)),
                ),
                const Spacer(),
                IconButton(
                  onPressed:
                      _isLoading ? null : () => _openEditor(schedule: schedule),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit schedule',
                ),
                IconButton(
                  onPressed: _isLoading ? null : () => _deleteSchedule(index),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete schedule',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addBedtimeTemplate() {
    final schedule = Schedule.bedtime(startTime: '21:30', endTime: '07:00');
    setState(() {
      _schedules = [..._schedules, schedule];
    });
  }

  void _addSchoolTemplate() {
    final schedule = Schedule.schoolTime(startTime: '09:00', endTime: '15:00');
    setState(() {
      _schedules = [..._schedules, schedule];
    });
  }

  void _addHomeworkTemplate() {
    final schedule = Schedule(
      id: const Uuid().v4(),
      name: 'Homework Time',
      type: ScheduleType.homework,
      days: const [
        Day.monday,
        Day.tuesday,
        Day.wednesday,
        Day.thursday,
        Day.friday,
      ],
      startTime: '18:00',
      endTime: '20:00',
      action: ScheduleAction.blockDistracting,
      enabled: true,
    );
    setState(() {
      _schedules = [..._schedules, schedule];
    });
  }

  Future<void> _openEditor({Schedule? schedule}) async {
    final result = await showModalBottomSheet<Schedule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScheduleEditorSheet(initial: schedule),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      if (schedule == null) {
        _schedules = [..._schedules, result];
      } else {
        final index = _schedules.indexWhere((item) => item.id == schedule.id);
        if (index != -1) {
          _schedules[index] = result;
        }
      }
    });
  }

  void _deleteSchedule(int index) {
    final schedule = _schedules[index];
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Schedule'),
          content: Text('Remove "${schedule.name}" from time restrictions?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _schedules = List<Schedule>.from(_schedules)..removeAt(index);
                });
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _updateSchedule(int index, Schedule updated) {
    setState(() {
      _schedules[index] = updated;
    });
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges) {
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

      final updatedPolicy = widget.child.policy.copyWith(
        schedules: _cloneSchedules(_schedules),
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
        builder: (context) {
          return AlertDialog(
            title: const Text('Save Failed'),
            content: Text('Failed to update schedules: $error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  List<Schedule> _cloneSchedules(List<Schedule> schedules) {
    return schedules.map(_copySchedule).toList();
  }

  Schedule _copySchedule(
    Schedule schedule, {
    String? name,
    ScheduleType? type,
    List<Day>? days,
    String? startTime,
    String? endTime,
    bool? enabled,
    ScheduleAction? action,
  }) {
    return Schedule(
      id: schedule.id,
      name: name ?? schedule.name,
      type: type ?? schedule.type,
      days: days ?? List<Day>.from(schedule.days),
      startTime: startTime ?? schedule.startTime,
      endTime: endTime ?? schedule.endTime,
      enabled: enabled ?? schedule.enabled,
      action: action ?? schedule.action,
    );
  }

  bool _scheduleListsEqual(List<Schedule> left, List<Schedule> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (!_scheduleEquals(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }

  bool _scheduleEquals(Schedule left, Schedule right) {
    return left.id == right.id &&
        left.name == right.name &&
        left.type == right.type &&
        listEquals(left.days, right.days) &&
        left.startTime == right.startTime &&
        left.endTime == right.endTime &&
        left.enabled == right.enabled &&
        left.action == right.action;
  }

  String _formatDays(List<Day> days) {
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
    if (days.toSet().containsAll(weekdays) && days.length == weekdays.length) {
      return 'Weekdays';
    }

    return days.map((day) => day.name.substring(0, 3).toUpperCase()).join(', ');
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

  IconData _iconForType(ScheduleType type) {
    switch (type) {
      case ScheduleType.bedtime:
        return Icons.bedtime;
      case ScheduleType.school:
        return Icons.school;
      case ScheduleType.homework:
        return Icons.menu_book;
      case ScheduleType.custom:
        return Icons.event;
    }
  }

  String _actionLabel(ScheduleAction action) {
    switch (action) {
      case ScheduleAction.blockAll:
        return 'Block all';
      case ScheduleAction.blockDistracting:
        return 'Block distracting';
      case ScheduleAction.allowAll:
        return 'Allow all';
    }
  }
}

class _ScheduleEditorSheet extends StatefulWidget {
  const _ScheduleEditorSheet({
    this.initial,
  });

  final Schedule? initial;

  @override
  State<_ScheduleEditorSheet> createState() => _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends State<_ScheduleEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  late ScheduleType _type;
  late ScheduleAction _action;
  late Set<Day> _days;
  late String _startTime;
  late String _endTime;
  late bool _enabled;

  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;

    _nameController =
        TextEditingController(text: initial?.name ?? 'Custom Time');
    _type = initial?.type ?? ScheduleType.custom;
    _action = initial?.action ?? ScheduleAction.blockDistracting;
    _days = initial?.days.toSet() ??
        {
          Day.monday,
          Day.tuesday,
          Day.wednesday,
          Day.thursday,
          Day.friday,
        };
    _startTime = initial?.startTime ?? '16:00';
    _endTime = initial?.endTime ?? '18:00';
    _enabled = initial?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.initial == null ? 'New Schedule' : 'Edit Schedule',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Schedule Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Enter a schedule name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<ScheduleType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Schedule Type',
                  border: OutlineInputBorder(),
                ),
                items: ScheduleType.values
                    .map(
                      (type) => DropdownMenuItem<ScheduleType>(
                        value: type,
                        child: Text(_typeLabel(type)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _type = value;
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<ScheduleAction>(
                initialValue: _action,
                decoration: const InputDecoration(
                  labelText: 'Action',
                  border: OutlineInputBorder(),
                ),
                items: ScheduleAction.values
                    .map(
                      (action) => DropdownMenuItem<ScheduleAction>(
                        value: action,
                        child: Text(_actionLabel(action)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _action = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(isStart: true),
                      icon: const Icon(Icons.schedule),
                      label: Text('Start: ${_formatTime(_startTime)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(isStart: false),
                      icon: const Icon(Icons.schedule),
                      label: Text('End: ${_formatTime(_endTime)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Days',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Day.values.map((day) {
                  final selected = _days.contains(day);
                  return FilterChip(
                    selected: selected,
                    label: Text(day.name.substring(0, 3).toUpperCase()),
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _days.add(day);
                        } else {
                          _days.remove(day);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              if (_submitted && _days.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Select at least one day',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                subtitle: const Text('Apply this schedule immediately'),
                value: _enabled,
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save Schedule'),
                ),
              ),
            ],
          ),
        ),
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
    setState(() {
      final hhmm =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      if (isStart) {
        _startTime = hhmm;
      } else {
        _endTime = hhmm;
      }
    });
  }

  void _save() {
    setState(() {
      _submitted = true;
    });
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_days.isEmpty) {
      return;
    }

    final sortedDays = _days.toList()
      ..sort((a, b) => Day.values.indexOf(a).compareTo(Day.values.indexOf(b)));
    final schedule = Schedule(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      type: _type,
      days: sortedDays,
      startTime: _startTime,
      endTime: _endTime,
      enabled: _enabled,
      action: _action,
    );

    Navigator.of(context).pop(schedule);
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

  String _typeLabel(ScheduleType type) {
    switch (type) {
      case ScheduleType.bedtime:
        return 'Bedtime';
      case ScheduleType.school:
        return 'School Time';
      case ScheduleType.homework:
        return 'Homework Time';
      case ScheduleType.custom:
        return 'Custom';
    }
  }

  String _actionLabel(ScheduleAction action) {
    switch (action) {
      case ScheduleAction.blockAll:
        return 'Block all';
      case ScheduleAction.blockDistracting:
        return 'Block distracting';
      case ScheduleAction.allowAll:
        return 'Allow all';
    }
  }
}
