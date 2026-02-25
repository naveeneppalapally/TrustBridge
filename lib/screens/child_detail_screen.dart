import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/screens/add_child_device_screen.dart';
import 'package:trustbridge_app/screens/child_activity_log_screen.dart';
import 'package:trustbridge_app/screens/child_devices_screen.dart';
import 'package:trustbridge_app/screens/edit_child_screen.dart';
import 'package:trustbridge_app/screens/policy_overview_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/utils/app_lock_guard.dart';
import 'package:trustbridge_app/utils/spring_animation.dart';
import 'package:trustbridge_app/widgets/empty_state.dart';

class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({
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
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  late ChildProfile _child;
  AuthService? _authService;
  FirestoreService? _firestoreService;
  _QuickMode? _quickModeOverride;
  final Set<String> _pressedQuickActions = <String>{};

  AuthService get _resolvedAuthService =>
      _authService ??= widget.authService ?? AuthService();

  FirestoreService get _resolvedFirestoreService =>
      _firestoreService ??= widget.firestoreService ?? FirestoreService();

  String? get _resolvedParentId =>
      widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _child = widget.child;
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF2F6FB);

    final quickMode = _currentQuickMode;
    final timerData = _timerDataForMode(quickMode);
    final modeColor = _quickModeColor(quickMode);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _buildHeader(context),
            const SizedBox(height: 14),
            _buildStatusCard(context, quickMode, modeColor),
            const SizedBox(height: 14),
            _buildTimerCard(context, quickMode, modeColor, timerData),
            const SizedBox(height: 14),
            _buildQuickActionsGrid(context, quickMode),
            const SizedBox(height: 14),
            _buildTodayActivityCard(context),
            const SizedBox(height: 14),
            _buildActiveSchedulesCard(context),
            const SizedBox(height: 14),
            _buildDevicesCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHILD PROFILE',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _child.nickname,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
              ),
            ],
          ),
        ),
        PopupMenuButton<_HeaderAction>(
          key: const Key('child_detail_overflow_menu'),
          tooltip: 'More options',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (action) async {
            switch (action) {
              case _HeaderAction.edit:
                await _openEditScreen(context);
                break;
              case _HeaderAction.activity:
                await _openActivityLog(context);
                break;
              case _HeaderAction.policy:
                await _openPolicyOverview(context);
                break;
              case _HeaderAction.delete:
                _showDeleteConfirmation(context);
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem<_HeaderAction>(
              value: _HeaderAction.edit,
              child: Text('Edit Profile'),
            ),
            PopupMenuItem<_HeaderAction>(
              value: _HeaderAction.activity,
              child: Text('View Activity Log'),
            ),
            PopupMenuItem<_HeaderAction>(
              value: _HeaderAction.policy,
              child: Text('Manage Policy'),
            ),
            PopupMenuItem<_HeaderAction>(
              value: _HeaderAction.delete,
              child: Text('Delete Profile'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    _QuickMode mode,
    Color modeColor,
  ) {
    return Container(
      key: const Key('child_detail_status_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDEE5EF)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: _avatarColor(_child.ageBand),
            child: Text(
              _child.nickname.isEmpty ? '?' : _child.nickname[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode == _QuickMode.pauseAll
                      ? 'Pause All Active'
                      : '${_quickModeLabel(mode)} Mode',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _modeSubtitle(mode),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                      ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'ACTIVE',
              style: TextStyle(
                color: modeColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerCard(
    BuildContext context,
    _QuickMode mode,
    Color modeColor,
    _ModeTimerData? timerData,
  ) {
    final hasTimer = timerData != null && timerData.remaining > Duration.zero;
    final remainingLabel =
        hasTimer ? _formatDuration(timerData.remaining) : 'Until changed';
    final progress = timerData?.remainingProgress ?? 0.0;

    return Card(
      key: const Key('child_detail_timer_ring'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_quickModeIcon(mode), color: modeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Mode: ${_quickModeLabel(mode)}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _modeSubtitle(mode),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: modeColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: modeColor.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 18, color: modeColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasTimer ? 'Remaining: $remainingLabel' : remainingLabel,
                      style: TextStyle(
                        color: modeColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasTimer) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: modeColor.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(modeColor),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _modeQuote(mode),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context, _QuickMode activeMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mode Remote',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'One mode is active at a time. Tap any button to switch now.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[700],
              ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          key: const Key('child_detail_quick_actions_grid'),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.22,
          children: [
            _buildQuickActionTile(
              context,
              id: 'pause',
              label: 'Pause All',
              icon: Icons.pause_circle_outline,
              color: const Color(0xFFEF4444),
              subtitle: 'Block internet everywhere for a timer.',
              selected: activeMode == _QuickMode.pauseAll,
              onTap: () async => _showPauseDurationPicker(context),
            ),
            _buildQuickActionTile(
              context,
              id: 'homework',
              label: 'Homework',
              icon: Icons.menu_book_rounded,
              color: const Color(0xFF3B82F6),
              subtitle: 'Block social, chat, streaming, and games.',
              selected: activeMode == _QuickMode.homework,
              onTap: () => _setQuickMode(context, _QuickMode.homework),
            ),
            _buildQuickActionTile(
              context,
              id: 'bedtime',
              label: 'Bedtime',
              icon: Icons.nightlight_round,
              color: const Color(0xFF8B5CF6),
              subtitle: 'Lock internet except approved access.',
              selected: activeMode == _QuickMode.bedtime,
              onTap: () => _setQuickMode(context, _QuickMode.bedtime),
            ),
            _buildQuickActionTile(
              context,
              id: 'free_play',
              label: 'Free Play',
              icon: Icons.celebration_outlined,
              color: const Color(0xFF10B981),
              subtitle: 'Use your normal app/category toggles.',
              selected: activeMode == _QuickMode.freePlay,
              onTap: () => _setQuickMode(context, _QuickMode.freePlay),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionTile(
    BuildContext context, {
    required String id,
    required String label,
    required IconData icon,
    required Color color,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isPressed = _pressedQuickActions.contains(id);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onHighlightChanged: (pressed) {
        setState(() {
          if (pressed) {
            _pressedQuickActions.add(id);
          } else {
            _pressedQuickActions.remove(id);
          }
        });
      },
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: SpringAnimation.springCurve,
        scale: isPressed ? 0.97 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? color.withValues(alpha: 0.18) : Colors.white,
            border: Border.all(
              color: selected ? color : const Color(0xFFD8E1EE),
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 23),
                  const Spacer(),
                  if (selected)
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                      height: 1.25,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                selected ? 'ACTIVE' : 'TAP TO ACTIVATE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? color : Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayActivityCard(BuildContext context) {
    const rows = <_ActivityRowData>[
      _ActivityRowData(
        label: 'Education',
        value: '1h 05m',
        progress: 0.48,
        color: Color(0xFF3B82F6),
      ),
      _ActivityRowData(
        label: 'Entertainment',
        value: '45m',
        progress: 0.33,
        color: Color(0xFFF59E0B),
      ),
      _ActivityRowData(
        label: 'Social',
        value: '25m',
        progress: 0.19,
        color: Color(0xFF10B981),
      ),
    ];

    return Card(
      key: const Key('child_detail_activity_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Today\'s Activity - Total: 2h 15m screen time',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                  ),
                ),
                const Icon(Icons.bar_chart_rounded, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            ...rows.map((row) => _buildActivityRow(context, row)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityRow(BuildContext context, _ActivityRowData row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(
                row.value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: row.progress,
            color: row.color,
            backgroundColor: row.color.withValues(alpha: 0.16),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSchedulesCard(BuildContext context) {
    final schedules = _child.policy.schedules;

    return Card(
      key: const Key('child_detail_schedules_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Active Schedules',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _openPolicyOverview(context),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (schedules.isEmpty)
              EmptyState(
                icon: const Text('\u{1F4C6}'),
                title: 'No schedules yet',
                subtitle: 'Add a bedtime or school schedule.',
                actionLabel: 'Add Schedule',
                onAction: () => _openPolicyOverview(context),
              )
            else
              ...schedules.map(
                (schedule) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildScheduleRow(context, schedule),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRow(BuildContext context, Schedule schedule) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE5F1)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _scheduleColor(schedule.type).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _scheduleIcon(schedule.type),
              size: 18,
              color: _scheduleColor(schedule.type),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatScheduleTime(schedule.startTime)} - ${_formatScheduleTime(schedule.endTime)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: schedule.enabled,
            onChanged: (value) => _toggleSchedule(context, schedule, value),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesCard(BuildContext context) {
    final devices = _child.deviceIds;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openManageDevices(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.devices_outlined, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Devices',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openPairDeviceScreen(context),
                    child: const Text('Pair Phone'),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey.shade600),
                ],
              ),
              const SizedBox(height: 10),
              if (devices.isEmpty)
                Text(
                  'No linked devices. Tap to add a device ID.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                )
              else ...[
                Text(
                  '${devices.length} ${devices.length == 1 ? 'device' : 'devices'} linked',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                ...devices.take(3).map(
                      (deviceId) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.smartphone,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                deviceId,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontFamily: 'monospace'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _QuickMode get _currentQuickMode {
    if (_quickModeOverride != null) {
      return _quickModeOverride!;
    }

    final now = DateTime.now();
    final pausedUntil = _child.pausedUntil;
    if (pausedUntil != null && pausedUntil.isAfter(now)) {
      return _QuickMode.pauseAll;
    }

    final manualMode = _activeManualModeValue(now);
    switch (manualMode) {
      case 'bedtime':
        return _QuickMode.bedtime;
      case 'homework':
        return _QuickMode.homework;
      case 'free':
        return _QuickMode.freePlay;
    }

    final active = _activeSchedule;
    if (active == null) {
      return _QuickMode.freePlay;
    }

    switch (active.type) {
      case ScheduleType.homework:
      case ScheduleType.school:
        return _QuickMode.homework;
      case ScheduleType.bedtime:
        return _QuickMode.bedtime;
      case ScheduleType.custom:
        return _QuickMode.freePlay;
    }
  }

  String? _activeManualModeValue(DateTime now) {
    final rawMode = _child.manualMode;
    if (rawMode == null || rawMode.isEmpty) {
      return null;
    }
    final mode = (rawMode['mode'] as String?)?.trim().toLowerCase();
    if (mode == null || mode.isEmpty) {
      return null;
    }
    final expiresAt = _asDateTime(rawMode['expiresAt']);
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      return null;
    }
    return mode;
  }

  DateTime? _asDateTime(Object? rawValue) {
    if (rawValue is DateTime) {
      return rawValue;
    }
    return null;
  }

  Schedule? get _activeSchedule {
    final now = TimeOfDay.now();
    final today = Day.values[DateTime.now().weekday - 1];

    for (final schedule in _child.policy.schedules) {
      if (!schedule.enabled) {
        continue;
      }
      if (!schedule.days.contains(today)) {
        continue;
      }
      if (_isTimeInRange(now, schedule.startTime, schedule.endTime)) {
        return schedule;
      }
    }
    return null;
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

  _ModeTimerData? _timerDataForMode(_QuickMode mode) {
    final now = DateTime.now();

    if (mode == _QuickMode.pauseAll) {
      final pausedUntil = _child.pausedUntil;
      if (pausedUntil == null || !pausedUntil.isAfter(now)) {
        return null;
      }
      final remaining = pausedUntil.difference(now);
      final total =
          remaining.inSeconds <= 0 ? const Duration(seconds: 1) : remaining;
      return _ModeTimerData(remaining: remaining, total: total);
    }

    final rawManualMode = _child.manualMode;
    final activeManualMode = _activeManualModeValue(now);
    final manualExpiresAt = _asDateTime(rawManualMode?['expiresAt']);
    final manualSetAt = _asDateTime(rawManualMode?['setAt']);
    if (activeManualMode != null &&
        activeManualMode == _manualModeNameForQuickMode(mode) &&
        manualExpiresAt != null &&
        manualExpiresAt.isAfter(now)) {
      final remaining = manualExpiresAt.difference(now);
      final totalStart = manualSetAt ?? now;
      final computedTotal = manualExpiresAt.difference(totalStart);
      final total = computedTotal.inSeconds <= 0 ? remaining : computedTotal;
      return _ModeTimerData(remaining: remaining, total: total);
    }

    final schedule = _activeSchedule;
    if (schedule == null) {
      return null;
    }
    final window = _resolveScheduleWindow(schedule, now);
    final total = window.end.difference(window.start);
    if (total.inSeconds <= 0) {
      return null;
    }
    final remaining =
        window.end.isAfter(now) ? window.end.difference(now) : Duration.zero;
    return _ModeTimerData(remaining: remaining, total: total);
  }

  String _manualModeNameForQuickMode(_QuickMode mode) {
    switch (mode) {
      case _QuickMode.homework:
        return 'homework';
      case _QuickMode.bedtime:
        return 'bedtime';
      case _QuickMode.freePlay:
        return 'free';
      case _QuickMode.pauseAll:
        return '';
    }
  }

  ({DateTime start, DateTime end}) _resolveScheduleWindow(
    Schedule schedule,
    DateTime now,
  ) {
    final startTime = _parseTime(schedule.startTime);
    final endTime = _parseTime(schedule.endTime);

    DateTime start = DateTime(
      now.year,
      now.month,
      now.day,
      startTime.hour,
      startTime.minute,
    );
    DateTime end = DateTime(
      now.year,
      now.month,
      now.day,
      endTime.hour,
      endTime.minute,
    );

    final crossesMidnight = (startTime.hour * 60 + startTime.minute) >
        (endTime.hour * 60 + endTime.minute);

    if (!crossesMidnight) {
      return (start: start, end: end);
    }

    if (now.isBefore(end)) {
      start = start.subtract(const Duration(days: 1));
    } else {
      end = end.add(const Duration(days: 1));
    }

    return (start: start, end: end);
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _setQuickMode(BuildContext context, _QuickMode mode) async {
    final parentId = _resolvedParentId;
    if (parentId == null) {
      _showMessage(context, 'Not logged in');
      return;
    }
    if (mode == _QuickMode.pauseAll) {
      await _showPauseDurationPicker(context);
      return;
    }

    final previousOverride = _quickModeOverride;
    setState(() {
      _quickModeOverride = mode;
    });

    try {
      // One active remote mode at a time: clear pause before switching mode.
      await _resolvedFirestoreService.setChildPause(
        parentId: parentId,
        childId: _child.id,
        pausedUntil: null,
      );

      switch (mode) {
        case _QuickMode.homework:
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: _child.id,
            mode: 'homework',
          );
          break;
        case _QuickMode.bedtime:
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: _child.id,
            mode: 'bedtime',
          );
          break;
        case _QuickMode.freePlay:
          await _resolvedFirestoreService.setChildManualMode(
            parentId: parentId,
            childId: _child.id,
            mode: 'free',
          );
          break;
        case _QuickMode.pauseAll:
          return;
      }

      final refreshed = await _resolvedFirestoreService.getChild(
        parentId: parentId,
        childId: _child.id,
      );
      if (mounted) {
        setState(() {
          if (refreshed != null) {
            _child = refreshed;
          }
          _quickModeOverride = null;
        });
      }

      if (!context.mounted) {
        return;
      }
      _showMessage(
        context,
        '${_quickModeLabel(mode)} mode is now live on the child device.',
        success: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _quickModeOverride = previousOverride;
      });
      _showMessage(context, 'Unable to apply quick mode: $error');
    }
  }

  Future<void> _toggleSchedule(
    BuildContext context,
    Schedule schedule,
    bool enabled,
  ) async {
    final parentId = _resolvedParentId;
    if (parentId == null) {
      _showMessage(context, 'Not logged in');
      return;
    }

    final oldSchedules = _child.policy.schedules;
    final updatedSchedules = oldSchedules
        .map(
          (item) => item.id == schedule.id
              ? Schedule(
                  id: item.id,
                  name: item.name,
                  type: item.type,
                  days: item.days,
                  startTime: item.startTime,
                  endTime: item.endTime,
                  enabled: enabled,
                  action: item.action,
                )
              : item,
        )
        .toList(growable: false);

    final updatedChild = _child.copyWith(
      policy: _child.policy.copyWith(schedules: updatedSchedules),
    );

    setState(() {
      _child = updatedChild;
    });

    try {
      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );
      if (!context.mounted) {
        return;
      }
      _showMessage(
        context,
        enabled ? 'Schedule enabled' : 'Schedule disabled',
        success: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _child = _child.copyWith(
          policy: _child.policy.copyWith(schedules: oldSchedules),
        );
      });
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Unable to update schedule: $error');
    }
  }

  Future<void> _openEditScreen(BuildContext context) async {
    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditChildScreen(
          child: _child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (didUpdate == true) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openPolicyOverview(BuildContext context) async {
    await guardedNavigate(
      context,
      () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PolicyOverviewScreen(
              child: _child,
              authService: widget.authService,
              firestoreService: widget.firestoreService,
              parentIdOverride: widget.parentIdOverride,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openManageDevices(BuildContext context) async {
    final updatedChild = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => ChildDevicesScreen(
          child: _child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );

    if (!context.mounted || updatedChild == null) {
      return;
    }

    setState(() {
      _child = updatedChild;
    });
  }

  Future<void> _openPairDeviceScreen(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddChildDeviceScreen(child: _child),
      ),
    );
  }

  Future<void> _openActivityLog(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildActivityLogScreen(child: _child),
      ),
    );
  }

  Future<void> _showPauseDurationPicker(BuildContext context) async {
    final duration = await showModalBottomSheet<Duration>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Pause Internet For',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('15 minutes'),
                onTap: () =>
                    Navigator.of(context).pop(const Duration(minutes: 15)),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('30 minutes'),
                onTap: () =>
                    Navigator.of(context).pop(const Duration(minutes: 30)),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('1 hour'),
                onTap: () =>
                    Navigator.of(context).pop(const Duration(hours: 1)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (duration == null || !context.mounted) {
      return;
    }

    await _pauseInternetForDuration(context, duration);
  }

  Future<void> _pauseInternetForDuration(
    BuildContext context,
    Duration duration,
  ) async {
    final parentId = _resolvedParentId;
    if (parentId == null) {
      _showMessage(context, 'Not logged in');
      return;
    }

    final pausedUntil = DateTime.now().add(duration);

    try {
      // Pause is treated as a dedicated quick mode, so clear manual override.
      await _resolvedFirestoreService.setChildManualMode(
        parentId: parentId,
        childId: _child.id,
        mode: null,
      );
      await _resolvedFirestoreService.setChildPause(
        parentId: parentId,
        childId: _child.id,
        pausedUntil: pausedUntil,
      );
      final refreshed = await _resolvedFirestoreService.getChild(
        parentId: parentId,
        childId: _child.id,
      );
      if (!context.mounted) {
        return;
      }
      if (refreshed != null) {
        setState(() {
          _child = refreshed;
          _quickModeOverride = null;
        });
      }
      _showMessage(
        context,
        'Internet paused until ${_formatTime(pausedUntil)}',
        success: true,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Unable to pause internet: $error');
    }
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red.shade700),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Delete Child Profile'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete ${_child.nickname}\'s profile?',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This action cannot be undone',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text('The following will be deleted:'),
                    SizedBox(height: 4),
                    Text('- Child profile'),
                    Text('- Content filters'),
                    Text('- Time restrictions'),
                    Text('- All settings'),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteChild(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete Profile'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteChild(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Deleting...'),
          ],
        ),
      ),
    );

    try {
      final parentId = _resolvedParentId;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      await _resolvedFirestoreService.deleteChild(
        parentId: parentId,
        childId: _child.id,
      );

      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_child.nickname}\'s profile has been deleted'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      _showMessage(context, 'Failed to delete child profile: $error');
    }
  }

  Color _avatarColor(AgeBand ageBand) {
    switch (ageBand) {
      case AgeBand.young:
        return const Color(0xFF3B82F6);
      case AgeBand.middle:
        return const Color(0xFF10B981);
      case AgeBand.teen:
        return const Color(0xFFF59E0B);
    }
  }

  Color _scheduleColor(ScheduleType type) {
    switch (type) {
      case ScheduleType.homework:
      case ScheduleType.school:
        return const Color(0xFF3B82F6);
      case ScheduleType.bedtime:
        return const Color(0xFF8B5CF6);
      case ScheduleType.custom:
        return const Color(0xFF10B981);
    }
  }

  IconData _scheduleIcon(ScheduleType type) {
    switch (type) {
      case ScheduleType.homework:
      case ScheduleType.school:
        return Icons.menu_book_rounded;
      case ScheduleType.bedtime:
        return Icons.nightlight_round;
      case ScheduleType.custom:
        return Icons.event_available_rounded;
    }
  }

  Color _quickModeColor(_QuickMode mode) {
    switch (mode) {
      case _QuickMode.pauseAll:
        return const Color(0xFFEF4444);
      case _QuickMode.homework:
        return const Color(0xFF3B82F6);
      case _QuickMode.bedtime:
        return const Color(0xFF8B5CF6);
      case _QuickMode.freePlay:
        return const Color(0xFF10B981);
    }
  }

  IconData _quickModeIcon(_QuickMode mode) {
    switch (mode) {
      case _QuickMode.pauseAll:
        return Icons.pause_circle_outline;
      case _QuickMode.homework:
        return Icons.menu_book_rounded;
      case _QuickMode.bedtime:
        return Icons.nightlight_round;
      case _QuickMode.freePlay:
        return Icons.celebration_outlined;
    }
  }

  String _quickModeLabel(_QuickMode mode) {
    switch (mode) {
      case _QuickMode.pauseAll:
        return 'Pause All';
      case _QuickMode.homework:
        return 'Homework';
      case _QuickMode.bedtime:
        return 'Bedtime';
      case _QuickMode.freePlay:
        return 'Free Play';
    }
  }

  String _modeSubtitle(_QuickMode mode) {
    switch (mode) {
      case _QuickMode.pauseAll:
        return 'Internet is paused everywhere until the timer ends.';
      case _QuickMode.homework:
        return 'Social, chat, streaming, and games are blocked.';
      case _QuickMode.bedtime:
        return 'All internet is locked except approved access.';
      case _QuickMode.freePlay:
        return 'Quick overrides are off; app/category toggles decide access.';
    }
  }

  String _modeQuote(_QuickMode mode) {
    switch (mode) {
      case _QuickMode.pauseAll:
        return 'Switch to another mode anytime using the buttons below.';
      case _QuickMode.homework:
        return 'Tap Bedtime for full lock, or Free Play to restore normal access.';
      case _QuickMode.bedtime:
        return 'Tap Free Play when bedtime is over.';
      case _QuickMode.freePlay:
        return 'All quick modes are off. Turn on one button to enforce instantly.';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours <= 0) {
      return '${minutes}m';
    }
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }

  String _formatScheduleTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return value;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return value;
    }
    final date = DateTime(2026, 1, 1, hour, minute);
    return DateFormat('h:mm a').format(date);
  }

  String _formatTime(DateTime dateTime) =>
      DateFormat('h:mm a').format(dateTime);

  void _showMessage(
    BuildContext context,
    String message, {
    bool success = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : null,
      ),
    );
  }
}

class _ModeTimerData {
  const _ModeTimerData({required this.remaining, required this.total});

  final Duration remaining;
  final Duration total;

  double get remainingProgress {
    if (total.inMilliseconds <= 0) {
      return 0;
    }
    final ratio = remaining.inMilliseconds / total.inMilliseconds;
    return ratio.clamp(0.0, 1.0).toDouble();
  }
}

class _ActivityRowData {
  const _ActivityRowData({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  final String label;
  final String value;
  final double progress;
  final Color color;
}

enum _QuickMode { pauseAll, homework, bedtime, freePlay }

enum _HeaderAction { edit, activity, policy, delete }
