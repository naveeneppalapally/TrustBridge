import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/category_ids.dart';
import '../core/utils/responsive.dart';
import '../models/child_profile.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
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
  ChildProfile? _latestChildForActions;

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
          children: [
            // Custom back button + title row
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
                  const Spacer(),
                  PopupMenuButton<_ChildControlMenuAction>(
                    icon: const Icon(
                      Icons.more_vert,
                      color: AppColors.textSecondary,
                    ),
                    onSelected: (action) => _handleMenuAction(
                      action: action,
                      parentId: parentId,
                    ),
                    itemBuilder: (context) => const [
                      PopupMenuItem<_ChildControlMenuAction>(
                        value: _ChildControlMenuAction.deleteProfile,
                        child: Text('Delete child profile'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: StreamBuilder<ChildProfile?>(
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Child controls are unavailable right now.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }
                  final child = snapshot.data;
                  if (child == null &&
                      snapshot.connectionState == ConnectionState.waiting) {
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        R.sp(20),
                        R.sp(8),
                        R.sp(20),
                        R.sp(24),
                      ),
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'This child profile is no longer available.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }
                  _latestChildForActions = child;
                  final now = DateTime.now();
                  final activeMode = _activeMode(child, now);
                  final modeSummary = _modeSummary(activeMode);
                  final conflictWarning =
                      _modeConflictWarning(child, activeMode);

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      R.sp(20),
                      R.sp(4),
                      R.sp(20),
                      R.sp(24),
                    ),
                    children: [
                      Text(
                        child.nickname,
                        style: AppTextStyles.displayMedium(),
                      ),
                      const SizedBox(height: 16),
                      _buildProtectionSection(
                        child: child,
                        activeMode: activeMode,
                        modeSummary: modeSummary,
                        conflictWarning: conflictWarning,
                        parentId: parentId,
                      ),
                      const SizedBox(height: 16),
                      _buildBlockedSection(
                        child: child,
                        parentId: parentId,
                        activeMode: activeMode,
                      ),
                      const SizedBox(height: 16),
                      _buildScheduleSection(
                        child: child,
                        parentId: parentId,
                      ),
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

  Widget _buildProtectionSection({
    required ChildProfile child,
    required _ModeType activeMode,
    required String modeSummary,
    required String? conflictWarning,
    required String parentId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Minimal protection toggle row
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: R.sp(16),
            vertical: R.sp(12),
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: child.protectionEnabled
                      ? AppColors.success
                      : AppColors.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  child.protectionEnabled
                      ? 'Protection is ON'
                      : 'Protection is OFF',
                  style: AppTextStyles.headingMedium(
                    color: child.protectionEnabled
                        ? AppColors.success
                        : AppColors.danger,
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
        const SizedBox(height: 16),
        // Mode selector — horizontal chips
        Text(
          'MODES',
          style: AppTextStyles.labelCaps(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _ModeType.values.map((mode) {
              final selected = mode == activeMode;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: _saving
                      ? null
                      : () => _setMode(
                            parentId: parentId,
                            child: child,
                            mode: mode,
                          ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                          selected ? AppColors.primaryDim : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.surfaceBorder,
                        width: selected ? 1 : 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(
                          _modeLabel(mode),
                          style: AppTextStyles.label(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          modeSummary,
          style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
        ),
        if (conflictWarning != null) ...[
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
              conflictWarning,
              style: AppTextStyles.bodySmall(color: AppColors.warning),
            ),
          ),
        ],
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "WHAT'S BLOCKED",
          style: AppTextStyles.labelCaps(color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        if (!protectionEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Protection is off. No categories are enforced right now.',
              style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
            ),
          )
        else if (modeForcedCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Some categories are locked by ${_modeLabel(activeMode)} mode.',
              style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
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
          return Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: EdgeInsets.symmetric(
              horizontal: R.sp(14),
              vertical: R.sp(10),
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.surfaceBorder,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        toggle.label,
                        style: AppTextStyles.body(),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: AppTextStyles.bodySmall(
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  onChanged: _saving || !protectionEnabled || blockedByMode
                      ? null
                      : (value) => _setSimpleCategory(
                            parentId: parentId,
                            child: child,
                            categoryId: toggle.id,
                            enabled: value,
                          ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
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
          child: Text(
            'Advanced App Blocking →',
            style: AppTextStyles.label(color: AppColors.primary),
          ),
        ),
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SCHEDULE',
          style: AppTextStyles.labelCaps(color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        if (todaysSchedules.isEmpty)
          Text(
            'No schedule for today. Use a quick preset below to get started.',
            style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
          )
        else
          ...todaysSchedules.map(
            (schedule) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vertical accent line
                  Container(
                    width: 3,
                    height: 40,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          schedule.name,
                          style: AppTextStyles.body(),
                        ),
                        Text(
                          '${_formatTime(schedule.startTime)} – ${_formatTime(schedule.endTime)} · ${_scheduleActionLabel(schedule.action)}',
                          style: AppTextStyles.bodySmall(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SchedulePresetChip(
              icon: Icons.bedtime_rounded,
              label: 'Bedtime',
              onTap: _saving
                  ? null
                  : () => _applySchedulePreset(
                        parentId: parentId,
                        child: child,
                        preset: Schedule.bedtime(
                          startTime: '21:30',
                          endTime: '07:00',
                        ),
                      ),
            ),
            _SchedulePresetChip(
              icon: Icons.menu_book_rounded,
              label: 'Homework',
              onTap: _saving
                  ? null
                  : () => _applySchedulePreset(
                        parentId: parentId,
                        child: child,
                        preset: Schedule(
                          id: '',
                          name: 'Homework',
                          type: ScheduleType.homework,
                          days: const [
                            Day.monday,
                            Day.tuesday,
                            Day.wednesday,
                            Day.thursday,
                            Day.friday,
                          ],
                          startTime: '16:00',
                          endTime: '18:00',
                          action: ScheduleAction.blockDistracting,
                        ),
                      ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
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
          child: Text(
            'Edit Schedule →',
            style: AppTextStyles.label(color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  Future<void> _applySchedulePreset({
    required String parentId,
    required ChildProfile child,
    required Schedule preset,
  }) async {
    if (_saving) {
      return;
    }
    final schedules = List<Schedule>.from(child.policy.schedules);
    final existingIndex = schedules.indexWhere((s) => s.type == preset.type);
    final generatedId =
        'preset_${preset.type.name}_${DateTime.now().millisecondsSinceEpoch}';
    final normalizedPreset = Schedule(
      id: existingIndex >= 0
          ? schedules[existingIndex].id
          : (preset.id.trim().isEmpty ? generatedId : preset.id),
      name: preset.name,
      type: preset.type,
      days: preset.days,
      startTime: preset.startTime,
      endTime: preset.endTime,
      enabled: true,
      action: preset.action,
    );

    if (existingIndex >= 0) {
      schedules[existingIndex] = normalizedPreset;
    } else {
      schedules.add(normalizedPreset);
    }

    final updatedChild = child.copyWith(
      policy: child.policy.copyWith(schedules: schedules),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${preset.name} preset applied.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not apply schedule preset.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _handleMenuAction({
    required _ChildControlMenuAction action,
    required String parentId,
  }) async {
    switch (action) {
      case _ChildControlMenuAction.deleteProfile:
        await _confirmAndDeleteChild(parentId: parentId);
        break;
    }
  }

  Future<void> _confirmAndDeleteChild({
    required String parentId,
  }) async {
    final child = _latestChildForActions;
    if (child == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Child profile is not loaded yet.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete child profile?'),
            content: Text(
              'This will remove ${child.nickname} and disconnect linked devices. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    setState(() {
      _saving = true;
    });
    try {
      await _resolvedFirestoreService.deleteChild(
        parentId: parentId,
        childId: child.id,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${child.nickname} deleted.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete child profile.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
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

enum _ChildControlMenuAction {
  deleteProfile,
}

class _SchedulePresetChip extends StatelessWidget {
  const _SchedulePresetChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.label(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
