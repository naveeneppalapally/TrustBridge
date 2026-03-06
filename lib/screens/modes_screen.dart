import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/responsive.dart';
import '../models/child_profile.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/skeleton_loaders.dart';

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
  List<ChildProfile>? _lastChildrenSnapshot;

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
    R.init(context);
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please sign in first.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button row
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
            // Title
            Padding(
              padding: EdgeInsets.fromLTRB(R.sp(20), R.sp(4), R.sp(20), 0),
              child: Text('Modes', style: AppTextStyles.displayMedium()),
            ),
            const SizedBox(height: 12),
            // Content
            Expanded(
              child: StreamBuilder<List<ChildProfile>>(
                stream: _resolvedFirestoreService.getChildrenStream(parentId),
                initialData: _lastChildrenSnapshot ??
                    _resolvedFirestoreService.getCachedChildren(parentId),
                builder: (context, snapshot) {
                  final children = snapshot.data ?? const <ChildProfile>[];
                  if (snapshot.hasData) {
                    _lastChildrenSnapshot = children;
                  }
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      children.isEmpty) {
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        R.sp(20),
                        0,
                        R.sp(20),
                        R.sp(24),
                      ),
                      children: const <Widget>[
                        SkeletonCard(height: 54),
                        SizedBox(height: 12),
                        SkeletonCard(height: 76),
                        SizedBox(height: 10),
                        SkeletonCard(height: 76),
                        SizedBox(height: 10),
                        SkeletonCard(height: 76),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Modes are unavailable right now.',
                        style: AppTextStyles.body(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }

                  if (children.isEmpty) {
                    return Center(
                      child: Text(
                        'Add a child profile first.',
                        style: AppTextStyles.body(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  final selectedChild = _resolveSelectedChild(children);
                  if (selectedChild == null) {
                    return Center(
                      child: Text(
                        'Choose a child to continue.',
                        style: AppTextStyles.body(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }

                  final activeMode = _activeMode(selectedChild, DateTime.now());
                  final modeSummary = _modeSummary(activeMode);
                  final modeWarning =
                      _modeConflictWarning(selectedChild, activeMode);

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      R.sp(20),
                      0,
                      R.sp(20),
                      R.sp(24),
                    ),
                    children: [
                      // Child selector chips
                      if (children.length > 1)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: children.map((child) {
                              final selected = child.id ==
                                  (_selectedChildId ?? selectedChild.id);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedChildId = child.id;
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primaryDim
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.surfaceBorder,
                                        width: selected ? 1 : 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      child.nickname,
                                      style: AppTextStyles.label(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(growable: false),
                          ),
                        ),
                      if (children.length > 1) const SizedBox(height: 16),
                      // Mode cards
                      ..._ModeType.values.map(
                        (mode) {
                          final isActive = mode == activeMode;
                          return GestureDetector(
                            onTap: _saving
                                ? null
                                : () => _setMode(
                                      parentId: parentId,
                                      child: selectedChild,
                                      mode: mode,
                                    ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.primaryDim
                                    : AppColors.surfaceRaised,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isActive
                                      ? AppColors.primary
                                      : AppColors.surfaceBorder,
                                  width: isActive ? 1 : 0.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Left accent bar
                                  Container(
                                    width: 3,
                                    height: 36,
                                    margin: const EdgeInsets.only(right: 14),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _modeLabel(mode),
                                          style: AppTextStyles.headingMedium(
                                            color: isActive
                                                ? AppColors.primary
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _modeSummary(mode),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.bodySmall(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.success,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        modeSummary,
                        style: AppTextStyles.bodySmall(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (modeWarning != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.warningDim,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            modeWarning,
                            style: AppTextStyles.bodySmall(
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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
      final ownedChild = await _resolvedFirestoreService.getChild(
        parentId: parentId,
        childId: child.id,
      );
      if (ownedChild == null) {
        throw StateError('child_access_revoked');
      }

      switch (mode) {
        case _ModeType.freePlay:
          await _resolvedFirestoreService.setChildPause(
            parentId: parentId,
            childId: ownedChild.id,
            pausedUntil: null,
          );
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: ownedChild.id,
            mode: 'free',
          );
          break;
        case _ModeType.homework:
          await _resolvedFirestoreService.setChildPause(
            parentId: parentId,
            childId: ownedChild.id,
            pausedUntil: null,
          );
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: ownedChild.id,
            mode: 'homework',
          );
          break;
        case _ModeType.bedtime:
          await _resolvedFirestoreService.setChildPause(
            parentId: parentId,
            childId: ownedChild.id,
            pausedUntil: null,
          );
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: ownedChild.id,
            mode: 'bedtime',
          );
          break;
        case _ModeType.lockdown:
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: ownedChild.id,
            mode: null,
          );
          await _resolvedFirestoreService.setChildPause(
            parentId: parentId,
            childId: ownedChild.id,
            pausedUntil: DateTime.now().add(const Duration(hours: 8)),
          );
          break;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_modeFailureMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _modeFailureMessage(Object error) {
    if (error is StateError &&
        error.message.toString().contains('child_access_revoked')) {
      return 'This child profile is no longer linked. Refresh children or pair again.';
    }
    if (error is FirebaseException) {
      final code = error.code.trim().toLowerCase();
      if (code == 'permission-denied' || code == 'permission_denied') {
        return 'Permission denied. Refresh children or pair again.';
      }
      if (code == 'unauthenticated') {
        return 'Session expired. Please sign in again.';
      }
    }
    final text = error.toString().toLowerCase();
    if (text.contains('permission_denied') ||
        text.contains('permission-denied')) {
      return 'Permission denied. Refresh children or pair again.';
    }
    return 'Could not switch mode right now.';
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
