import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/access_request.dart';
import '../models/active_mode.dart';
import '../models/child_profile.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/expiry_label_utils.dart';
import 'child_request_screen.dart';
import 'child_requests_screen.dart';

class ChildStatusScreen extends StatefulWidget {
  const ChildStatusScreen({
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
  State<ChildStatusScreen> createState() => _ChildStatusScreenState();
}

class _ChildStatusScreenState extends State<ChildStatusScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  Stream<List<AccessRequest>>? _childRequestsStream;
  String? _childRequestsParentId;
  String? _childRequestsChildId;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  void _ensureChildRequestsStream() {
    final parentId = _resolveParentId()?.trim();
    final childId = widget.child.id;

    if (parentId == null || parentId.isEmpty) {
      _childRequestsStream = null;
      _childRequestsParentId = null;
      _childRequestsChildId = null;
      return;
    }

    if (_childRequestsStream != null &&
        _childRequestsParentId == parentId &&
        _childRequestsChildId == childId) {
      return;
    }

    _childRequestsParentId = parentId;
    _childRequestsChildId = childId;
    _childRequestsStream = _resolvedFirestoreService.getChildRequestsStream(
      parentId: parentId,
      childId: childId,
    );
  }

  String? _resolveParentId() {
    final override = widget.parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    try {
      return _resolvedAuthService.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  ActiveMode get _activeMode {
    final schedule = _activeSchedule;
    if (schedule == null) {
      return ActiveMode.freeTime;
    }

    switch (schedule.type) {
      case ScheduleType.bedtime:
        return ActiveMode.bedtime;
      case ScheduleType.school:
        return ActiveMode.school;
      case ScheduleType.homework:
        return ActiveMode.homework;
      case ScheduleType.custom:
        return ActiveMode.custom;
    }
  }

  Schedule? get _activeSchedule {
    final now = TimeOfDay.now();
    final today = Day.values[DateTime.now().weekday - 1];

    for (final schedule in widget.child.policy.schedules) {
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

  _ModeTimerData? _timerDataForActiveSchedule() {
    final schedule = _activeSchedule;
    if (schedule == null) {
      return null;
    }

    final now = DateTime.now();
    final window = _resolveScheduleWindow(schedule, now);
    final total = window.end.difference(window.start);
    if (total.inSeconds <= 0) {
      return null;
    }

    final remaining = window.end.isAfter(now)
        ? window.end.difference(now)
        : Duration.zero;
    return _ModeTimerData(
      remaining: remaining,
      total: total,
    );
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

    final crossesMidnight =
        (startTime.hour * 60 + startTime.minute) >
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

  @override
  Widget build(BuildContext context) {
    _ensureChildRequestsStream();
    final mode = _activeMode;
    final timer = _timerDataForActiveSchedule();
    final modeColor = _modeColor(mode);
    final blockedCategories = widget.child.policy.blockedCategories;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(context, modeColor),
            const SizedBox(height: 16),
            _buildTimerHeroCard(context, mode, modeColor, timer),
            const SizedBox(height: 16),
            _buildBlockedSection(context, blockedCategories),
            const SizedBox(height: 16),
            if (_childRequestsStream != null) ...[
              _buildActiveAccessSection(context),
              const SizedBox(height: 16),
            ],
            _buildRequestButton(context),
            const SizedBox(height: 12),
            _buildRequestUpdatesButton(context),
            const SizedBox(height: 16),
            _buildMotivationCard(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color modeColor) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: modeColor.withValues(alpha: 0.60),
              width: 2,
            ),
            color: modeColor.withValues(alpha: 0.12),
          ),
          child: Center(
            child: Text(
              widget.child.nickname[0].toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: modeColor,
                fontSize: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '$greeting, ${widget.child.nickname}!',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.shield_outlined,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildTimerHeroCard(
    BuildContext context,
    ActiveMode mode,
    Color modeColor,
    _ModeTimerData? timer,
  ) {
    final modeLabel = _modeLabel(mode);
    final remainingText =
        timer == null ? 'Free Time' : _formatDuration(timer.remaining);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: modeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: modeColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$modeLabel MODE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: modeColor,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              key: const Key('child_status_timer_ring'),
              width: 200,
              height: 200,
              child: CustomPaint(
                painter: _CircularTimerRingPainter(
                  progress: timer?.remainingProgress ?? 0,
                  color: modeColor,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        remainingText,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timer == null ? 'NO TIMER' : 'REMAINING',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[700],
                    ),
                children: [
                  const TextSpan(text: 'Until '),
                  const TextSpan(
                    text: 'Free Time',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: timer == null ? ' is active now. Keep it up!' : ' begins. Keep it up!'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedSection(BuildContext context, List<String> categories) {
    return Card(
      key: const Key('child_status_blocked_section'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "What's blocked?",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
              ],
            ),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              Text(
                'No blocked categories right now.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    categories.map((category) => _buildCategoryChip(category)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String category) {
    final color = _categoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_categoryIcon(category), size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            _formatCategoryName(category),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.lock, size: 13, color: color),
        ],
      ),
    );
  }

  Widget _buildActiveAccessSection(BuildContext context) {
    final childRequestsStream = _childRequestsStream;
    if (childRequestsStream == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>(
        'child_requests_${_childRequestsParentId ?? 'none'}_${_childRequestsChildId ?? 'none'}',
      ),
      stream: childRequestsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final activeRequests = _activeApprovedRequests(snapshot.data!);
        if (activeRequests.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          key: const Key('child_status_active_access_card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Access available now',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Approved by your parent. Make good use of it.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 12),
                ...activeRequests.take(3).map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildActiveAccessRow(context, request),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveAccessRow(BuildContext context, AccessRequest request) {
    final parentReply = request.parentReply?.trim();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.appOrSite,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _accessWindowLabel(request.expiresAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.green[800],
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (parentReply != null && parentReply.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Parent note: $parentReply',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestButton(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        key: const Key('child_status_request_access_button'),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChildRequestScreen(
                child: widget.child,
                authService: widget.authService,
                firestoreService: widget.firestoreService,
                parentIdOverride: widget.parentIdOverride,
              ),
            ),
          );
        },
        icon: const Icon(Icons.send_rounded),
        label: const Text(
          'Ask for Access',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildRequestUpdatesButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('child_status_request_updates_button'),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChildRequestsScreen(
                child: widget.child,
                authService: widget.authService,
                firestoreService: widget.firestoreService,
                parentIdOverride: widget.parentIdOverride,
              ),
            ),
          );
        },
        icon: const Icon(Icons.history),
        label: const Text('Request Updates'),
      ),
    );
  }

  Widget _buildMotivationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Focused effort leads to faster rewards. You're doing great, ${widget.child.nickname}!",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[800],
                  ),
            ),
          ),
        ],
      ),
    );
  }

  List<AccessRequest> _activeApprovedRequests(List<AccessRequest> requests) {
    final now = DateTime.now();
    final active = requests.where((request) {
      if (request.effectiveStatus(now: now) != RequestStatus.approved) {
        return false;
      }
      return true;
    }).toList();

    active.sort((a, b) {
      final aExpires = a.expiresAt;
      final bExpires = b.expiresAt;
      if (aExpires == null && bExpires == null) {
        return b.requestedAt.compareTo(a.requestedAt);
      }
      if (aExpires == null) {
        return 1;
      }
      if (bExpires == null) {
        return -1;
      }
      return aExpires.compareTo(bExpires);
    });
    return active;
  }

  String _accessWindowLabel(DateTime? expiresAt) {
    if (expiresAt == null) {
      return 'No fixed expiry (until schedule ends)';
    }
    return buildExpiryRelativeLabel(expiresAt);
  }

  String _modeLabel(ActiveMode mode) {
    switch (mode) {
      case ActiveMode.freeTime:
        return 'FREE TIME';
      case ActiveMode.homework:
        return 'HOMEWORK';
      case ActiveMode.bedtime:
        return 'BEDTIME';
      case ActiveMode.school:
        return 'SCHOOL';
      case ActiveMode.custom:
        return 'CUSTOM';
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

  Color _modeColor(ActiveMode mode) {
    switch (mode) {
      case ActiveMode.freeTime:
        return const Color(0xFF10B981);
      case ActiveMode.homework:
        return const Color(0xFF3B82F6);
      case ActiveMode.bedtime:
        return const Color(0xFF8B5CF6);
      case ActiveMode.school:
        return const Color(0xFFF59E0B);
      case ActiveMode.custom:
        return const Color(0xFF6B7280);
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'social-networks':
        return const Color(0xFF3B82F6);
      case 'games':
        return const Color(0xFF10B981);
      case 'streaming':
        return const Color(0xFFEF4444);
      case 'adult-content':
        return const Color(0xFFF59E0B);
      case 'gambling':
        return const Color(0xFF8B5CF6);
      case 'dating':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'social-networks':
        return Icons.people;
      case 'games':
        return Icons.sports_esports;
      case 'streaming':
        return Icons.play_circle;
      case 'adult-content':
        return Icons.warning_amber_rounded;
      case 'gambling':
        return Icons.casino;
      case 'dating':
        return Icons.favorite;
      default:
        return Icons.block;
    }
  }

  String _formatCategoryName(String category) {
    return category
        .split('-')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

class _ModeTimerData {
  const _ModeTimerData({
    required this.remaining,
    required this.total,
  });

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

class _CircularTimerRingPainter extends CustomPainter {
  const _CircularTimerRingPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;

    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularTimerRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
