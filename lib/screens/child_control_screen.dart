import 'dart:async';

import 'package:flutter/material.dart';

import '../config/category_ids.dart';
import '../models/child_profile.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/skeleton_loaders.dart';
import 'block_categories_screen.dart';
import 'schedule_creator_screen.dart';

class ChildControlScreen extends StatefulWidget {
  const ChildControlScreen({
    super.key,
    required this.childId,
    this.initialChild,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final String childId;
  final ChildProfile? initialChild;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<ChildControlScreen> createState() => _ChildControlScreenState();
}

class _ChildControlScreenState extends State<ChildControlScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  bool _saving = false;

  static const List<_SimpleCategoryToggle> _simpleToggles =
      <_SimpleCategoryToggle>[
    _SimpleCategoryToggle(id: 'social-networks', label: 'Social Media'),
    _SimpleCategoryToggle(id: 'games', label: 'Gaming'),
    _SimpleCategoryToggle(id: 'adult-content', label: 'Adult Content'),
    _SimpleCategoryToggle(id: 'streaming', label: 'Streaming'),
    _SimpleCategoryToggle(id: 'chat', label: 'Chat'),
  ];

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
      return Scaffold(
        appBar: AppBar(title: const Text('Child Controls')),
        body: const Center(child: Text('Please sign in first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Child Controls'),
      ),
      body: StreamBuilder<ChildProfile?>(
        stream: _resolvedFirestoreService.getChildStream(
          parentId: parentId,
          childId: widget.childId,
        ),
        initialData: widget.initialChild ??
            _resolvedFirestoreService.getCachedChild(
              parentId: parentId,
              childId: widget.childId,
            ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Child controls are unavailable right now. Please try again.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final child = snapshot.data;
          if (child == null &&
              snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: const [
                SkeletonCard(height: 220),
                SizedBox(height: 14),
                SkeletonCard(height: 280),
                SizedBox(height: 14),
                SkeletonCard(height: 180),
              ],
            );
          }
          if (child == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This child profile is no longer available.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final now = DateTime.now();
          final activeMode = _activeMode(child, now);
          final modeSummary = _modeSummary(activeMode);
          final conflictWarning = _modeConflictWarning(child, activeMode);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                child.nickname,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              _buildProtectionSection(
                child: child,
                activeMode: activeMode,
                modeSummary: modeSummary,
                conflictWarning: conflictWarning,
                parentId: parentId,
              ),
              const SizedBox(height: 14),
              _buildBlockedSection(
                child: child,
                parentId: parentId,
                activeMode: activeMode,
              ),
              const SizedBox(height: 14),
              _buildScheduleSection(
                child: child,
                parentId: parentId,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProtectionSection({
    required ChildProfile child,
    required _ModeType activeMode,
    required String modeSummary,
    required String? conflictWarning,
    required String parentId,
  }) {
    final protectionColor =
        child.protectionEnabled ? Colors.green.shade700 : Colors.red.shade700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Protection On/Off',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: protectionColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      child.protectionEnabled
                          ? 'Protection is ON'
                          : 'Protection is OFF',
                      style: TextStyle(
                        color: protectionColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: child.protectionEnabled,
                    onChanged: _saving
                        ? null
                        : (value) => _setProtectionEnabled(
                              parentId: parentId,
                              child: child,
                              enabled: value,
                            ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Modes',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _ModeType.values.map((mode) {
                final selected = mode == activeMode;
                return ChoiceChip(
                  label: Text(_modeLabel(mode)),
                  selected: selected,
                  onSelected: _saving
                      ? null
                      : (_) => _setMode(
                            parentId: parentId,
                            child: child,
                            mode: mode,
                          ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 10),
            Text(modeSummary),
            const SizedBox(height: 8),
            Text(
              'If settings conflict, your manual app/category change wins.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (conflictWarning != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Text(
                  conflictWarning,
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedSection({
    required ChildProfile child,
    required String parentId,
    required _ModeType activeMode,
  }) {
    final blockedCategories =
        normalizeCategoryIds(child.policy.blockedCategories).toSet();
    final modeForcedCategories = _modeForcedCategories(activeMode);
    final protectionEnabled = child.protectionEnabled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "What's Blocked",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (!protectionEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Protection is off. No categories are enforced right now.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            else if (modeForcedCategories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Some categories are locked by ${_modeLabel(activeMode)} mode.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ..._simpleToggles.map((toggle) {
              final blockedByToggle = blockedCategories.contains(toggle.id);
              final blockedByMode = modeForcedCategories.contains(toggle.id);
              final enabled =
                  protectionEnabled && (blockedByToggle || blockedByMode);
              final subtitle = blockedByMode
                  ? 'Blocked by ${_modeLabel(activeMode)} mode'
                  : null;
              return SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(toggle.label),
                subtitle: subtitle == null ? null : Text(subtitle),
                value: enabled,
                onChanged: _saving || !protectionEnabled || blockedByMode
                    ? null
                    : (value) => _setSimpleCategory(
                          parentId: parentId,
                          child: child,
                          categoryId: toggle.id,
                          enabled: value,
                        ),
              );
            }),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BlockCategoriesScreen(
                        child: child,
                        authService: widget.authService,
                        firestoreService: widget.firestoreService,
                        parentIdOverride: widget.parentIdOverride,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.apps_rounded),
                label: const Text('Advanced App Blocking'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleSection({
    required ChildProfile child,
    required String parentId,
  }) {
    final today = Day.fromDateTime(DateTime.now());
    final todaysSchedules = child.policy.schedules
        .where((schedule) => schedule.enabled && schedule.days.contains(today))
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schedule',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (todaysSchedules.isEmpty)
              const Text('No schedule for today.')
            else
              ...todaysSchedules.map(
                (schedule) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.timeline_rounded),
                  title: Text(schedule.name),
                  subtitle: Text(
                    '${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)}',
                  ),
                  trailing: Text(_scheduleActionLabel(schedule.action)),
                ),
              ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ScheduleCreatorScreen(
                        child: child,
                        authService: widget.authService,
                        firestoreService: widget.firestoreService,
                        parentIdOverride: widget.parentIdOverride,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_calendar_rounded),
                label: const Text('Add or Edit Schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setProtectionEnabled({
    required String parentId,
    required ChildProfile child,
    required bool enabled,
  }) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await _resolvedFirestoreService.setChildProtectionEnabled(
        parentId: parentId,
        childId: child.id,
        enabled: enabled,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'Protection turned on.' : 'Protection turned off.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update protection right now.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _setSimpleCategory({
    required String parentId,
    required ChildProfile child,
    required String categoryId,
    required bool enabled,
  }) async {
    if (_saving) {
      return;
    }
    final blocked =
        normalizeCategoryIds(child.policy.blockedCategories).toSet();
    if (enabled) {
      blocked.add(normalizeCategoryId(categoryId));
    } else {
      removeCategoryAndAliases(blocked, categoryId);
    }

    final updatedChild = child.copyWith(
      policy: child.policy.copyWith(
        blockedCategories: blocked.toList(growable: false),
      ),
    );

    setState(() {
      _saving = true;
    });
    try {
      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );
      if (!mounted) {
        return;
      }
      final label = _simpleToggleLabel(categoryId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '$label blocked. New blocks apply to new connections. '
                    'If a site is already open, close and reopen the browser.'
                : '$label unblocked.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update block toggle.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _simpleToggleLabel(String categoryId) {
    final normalized = normalizeCategoryId(categoryId);
    for (final toggle in _simpleToggles) {
      if (normalizeCategoryId(toggle.id) == normalized) {
        return toggle.label;
      }
    }
    return 'This category';
  }

  Future<void> _setMode({
    required String parentId,
    required ChildProfile child,
    required _ModeType mode,
  }) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      switch (mode) {
        case _ModeType.freePlay:
          await _resolvedFirestoreService.setChildPause(
            parentId: parentId,
            childId: child.id,
            pausedUntil: null,
          );
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: child.id,
            mode: 'free',
          );
          break;
        case _ModeType.homework:
          await _resolvedFirestoreService.setChildPause(
            parentId: parentId,
            childId: child.id,
            pausedUntil: null,
          );
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: child.id,
            mode: 'homework',
          );
          break;
        case _ModeType.bedtime:
          await _resolvedFirestoreService.setChildPause(
            parentId: parentId,
            childId: child.id,
            pausedUntil: null,
          );
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: child.id,
            mode: 'bedtime',
          );
          break;
        case _ModeType.lockdown:
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: child.id,
            mode: null,
          );
          await _resolvedFirestoreService.setChildPause(
            parentId: parentId,
            childId: child.id,
            pausedUntil: DateTime.now().add(const Duration(hours: 8)),
          );
          break;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not switch mode right now.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  _ModeType _activeMode(ChildProfile child, DateTime now) {
    final pausedUntil = child.pausedUntil;
    if (pausedUntil != null && pausedUntil.isAfter(now)) {
      return _ModeType.lockdown;
    }

    final rawManualMode =
        (child.manualMode?['mode'] as String?)?.trim().toLowerCase();
    final rawManualExpires = child.manualMode?['expiresAt'];
    final manualExpires =
        rawManualExpires is DateTime ? rawManualExpires : null;
    final manualActive = manualExpires == null || manualExpires.isAfter(now);
    if (manualActive && rawManualMode != null && rawManualMode.isNotEmpty) {
      switch (rawManualMode) {
        case 'homework':
          return _ModeType.homework;
        case 'bedtime':
          return _ModeType.bedtime;
        case 'free':
          return _ModeType.freePlay;
      }
    }

    final activeSchedule = _activeSchedule(child.policy.schedules, now);
    if (activeSchedule == null) {
      return _ModeType.freePlay;
    }
    switch (activeSchedule.action) {
      case ScheduleAction.blockAll:
        return _ModeType.bedtime;
      case ScheduleAction.blockDistracting:
        return _ModeType.homework;
      case ScheduleAction.allowAll:
        return _ModeType.freePlay;
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

  String _modeLabel(_ModeType mode) {
    switch (mode) {
      case _ModeType.freePlay:
        return 'Free Play';
      case _ModeType.homework:
        return 'Homework';
      case _ModeType.bedtime:
        return 'Bedtime';
      case _ModeType.lockdown:
        return 'Lockdown';
    }
  }

  String _modeSummary(_ModeType mode) {
    switch (mode) {
      case _ModeType.freePlay:
        return 'During Free Play: only your selected category and app toggles are blocked.';
      case _ModeType.homework:
        return 'During Homework Mode: Social Media blocked, Gaming blocked, Streaming blocked, Chat blocked.';
      case _ModeType.bedtime:
        return 'During Bedtime Mode: internet is heavily restricted for sleep hours.';
      case _ModeType.lockdown:
        return 'During Lockdown: internet is paused immediately on the child device.';
    }
  }

  Set<String> _modeForcedCategories(_ModeType mode) {
    switch (mode) {
      case _ModeType.freePlay:
        return const <String>{};
      case _ModeType.homework:
        return const <String>{
          'social-networks',
          'games',
          'streaming',
          'chat',
        };
      case _ModeType.bedtime:
      case _ModeType.lockdown:
        return _simpleToggles.map((toggle) => toggle.id).toSet();
    }
  }

  String? _modeConflictWarning(ChildProfile child, _ModeType mode) {
    final modeKey = switch (mode) {
      _ModeType.homework => 'homework',
      _ModeType.bedtime => 'bedtime',
      _ModeType.lockdown => 'bedtime',
      _ModeType.freePlay => 'free',
    };
    final override = child.policy.modeOverrides[modeKey];
    if (override == null) {
      return null;
    }

    final allowsInstagramService = override.forceAllowServices
        .map((value) => value.trim().toLowerCase())
        .contains('instagram');
    final allowsInstagramPackage = override.forceAllowPackages
        .map((value) => value.trim().toLowerCase())
        .contains('com.instagram.android');

    if (allowsInstagramService || allowsInstagramPackage) {
      return 'Instagram is allowed but it is in Social Media, which this mode blocks. '
          'App allow override wins, so Instagram stays allowed in this mode.';
    }
    return null;
  }

  String _formatTime(String value) {
    final (hour24, minute) = _parseTimeOfDay(value);
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minuteText = minute.toString().padLeft(2, '0');
    return '$hour12:$minuteText $suffix';
  }

  String _scheduleActionLabel(ScheduleAction action) {
    switch (action) {
      case ScheduleAction.blockAll:
        return 'Lockdown';
      case ScheduleAction.blockDistracting:
        return 'Homework';
      case ScheduleAction.allowAll:
        return 'Free';
    }
  }
}

enum _ModeType {
  freePlay,
  homework,
  bedtime,
  lockdown,
}

class _SimpleCategoryToggle {
  const _SimpleCategoryToggle({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}
