import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class ModesScreen extends StatefulWidget {
  const ModesScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<ModesScreen> createState() => _ModesScreenState();
}

class _ModesScreenState extends State<ModesScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  String? _selectedChildId;
  bool _saving = false;

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
        appBar: AppBar(title: const Text('Modes')),
        body: const Center(child: Text('Please sign in first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Modes')),
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
                  'Modes are unavailable right now. Please try again.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final children = snapshot.data ?? const <ChildProfile>[];
          if (children.isEmpty) {
            return const Center(child: Text('Add a child profile first.'));
          }
          final selectedChild = _resolveSelectedChild(children);
          if (selectedChild == null) {
            return const Center(child: Text('Choose a child to continue.'));
          }

          final activeMode = _activeMode(selectedChild, DateTime.now());
          final modeSummary = _modeSummary(activeMode);
          final modeWarning = _modeConflictWarning(selectedChild, activeMode);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedChildId ?? selectedChild.id,
                decoration: const InputDecoration(
                  labelText: 'Selected child',
                  border: OutlineInputBorder(),
                ),
                items: children
                    .map(
                      (child) => DropdownMenuItem<String>(
                        value: child.id,
                        child: Text(child.nickname),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedChildId = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              ..._ModeType.values.map(
                (mode) => Card(
                  child: ListTile(
                    title: Text(
                      _modeLabel(mode),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(_modeSummary(mode)),
                    trailing: mode == activeMode
                        ? const Chip(label: Text('Active'))
                        : null,
                    onTap: _saving
                        ? null
                        : () => _setMode(
                              parentId: parentId,
                              child: selectedChild,
                              mode: mode,
                            ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                modeSummary,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Rule order: Lockdown pause > Mode override > Category toggles > App toggles.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (modeWarning != null) ...[
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
                    modeWarning,
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  ChildProfile? _resolveSelectedChild(List<ChildProfile> children) {
    final selectedId = _selectedChildId?.trim();
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final child in children) {
        if (child.id == selectedId) {
          return child;
        }
      }
    }
    if (children.isEmpty) {
      return null;
    }
    final fallback = children.first;
    if (_selectedChildId != fallback.id) {
      _selectedChildId = fallback.id;
    }
    return fallback;
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

    for (final schedule in child.policy.schedules) {
      if (!schedule.enabled || !schedule.days.contains(Day.fromDateTime(now))) {
        continue;
      }
      final start = _scheduleDate(schedule.startTime, now);
      final end = _scheduleEndDate(schedule, now);
      if (!now.isBefore(start) && now.isBefore(end)) {
        if (schedule.action == ScheduleAction.blockAll) {
          return _ModeType.bedtime;
        }
        if (schedule.action == ScheduleAction.blockDistracting) {
          return _ModeType.homework;
        }
      }
    }

    return _ModeType.freePlay;
  }

  DateTime _scheduleDate(String time, DateTime now) {
    final parts = time.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  DateTime _scheduleEndDate(Schedule schedule, DateTime now) {
    final start = _scheduleDate(schedule.startTime, now);
    var end = _scheduleDate(schedule.endTime, now);
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    return end;
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
}

enum _ModeType {
  freePlay,
  homework,
  bedtime,
  lockdown,
}
