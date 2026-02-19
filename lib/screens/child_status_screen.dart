import 'package:flutter/material.dart';

import '../models/access_request.dart';
import '../models/active_mode.dart';
import '../models/child_profile.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/expiry_label_utils.dart';
import 'child_requests_screen.dart';
import 'child_request_screen.dart';

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

class _ChildStatusScreenState extends State<ChildStatusScreen>
    with SingleTickerProviderStateMixin {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
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

  ActiveMode get _activeMode {
    final now = TimeOfDay.now();
    final today = Day.values[DateTime.now().weekday - 1];

    for (final schedule in widget.child.policy.schedules) {
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
          return ActiveMode.bedtime;
        case ScheduleType.school:
          return ActiveMode.school;
        case ScheduleType.homework:
          return ActiveMode.homework;
        case ScheduleType.custom:
          return ActiveMode.custom;
      }
    }

    return ActiveMode.freeTime;
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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureChildRequestsStream();
    final mode = _activeMode;
    final modeColor = _modeColor(mode);
    final pausedCategories = _activeMode == ActiveMode.freeTime
        ? <String>[]
        : widget.child.policy.blockedCategories;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 16),
            _buildGreeting(context),
            const SizedBox(height: 16),
            _buildHeroCard(context, mode, modeColor),
            const SizedBox(height: 16),
            if (_childRequestsStream != null) ...[
              _buildActiveAccessSection(context),
              const SizedBox(height: 16),
            ],
            if (pausedCategories.isNotEmpty) ...[
              _buildPausedCard(context, pausedCategories, mode),
              const SizedBox(height: 16),
            ],
            _buildRequestButton(context),
            const SizedBox(height: 16),
            _buildRequestUpdatesButton(context),
            const SizedBox(height: 16),
            _buildActivityFeed(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
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

  Widget _buildGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, ${widget.child.nickname}! 👋',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _formattedDate(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 24,
          backgroundColor: _modeColor(_activeMode).withValues(alpha: 0.18),
          child: Text(
            widget.child.nickname[0].toUpperCase(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _modeColor(_activeMode),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(
      BuildContext context, ActiveMode mode, Color modeColor) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            modeColor.withValues(alpha: 0.20),
            modeColor.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: modeColor.withValues(alpha: 0.30),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Text(
              mode.emoji,
              style: const TextStyle(fontSize: 64),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            mode.displayName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: modeColor,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            mode.explanation,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                ),
          ),
          const SizedBox(height: 18),
          _buildNextScheduleInfo(context, modeColor),
        ],
      ),
    );
  }

  Widget _buildNextScheduleInfo(BuildContext context, Color modeColor) {
    final nextChange = _getNextScheduleChange();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: modeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time, size: 18, color: modeColor),
          const SizedBox(width: 8),
          Text(
            nextChange,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: modeColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
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
                if (activeRequests.length > 3)
                  Text(
                    '+${activeRequests.length - 3} more active approvals',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
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

  Widget _buildPausedCard(
    BuildContext context,
    List<String> categories,
    ActiveMode mode,
  ) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paused right now',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'These are paused during ${mode.displayName.toLowerCase()} to help you focus 💪',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories
                  .map((category) => _buildCategoryChip(context, category))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(BuildContext context, String category) {
    final color = _categoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _categoryIcon(category),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            _formatCategoryName(category),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('child_status_request_access_button'),
        borderRadius: BorderRadius.circular(16),
        onTap: () {
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            children: [
              const Text('🙋', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ask for Access',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
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

  Widget _buildActivityFeed(BuildContext context) {
    final upcomingSchedules = widget.child.policy.schedules
        .where((schedule) => schedule.enabled)
        .toList();

    if (upcomingSchedules.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Schedule',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ...upcomingSchedules.take(3).map(
              (schedule) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildActivityCard(
                  context,
                  icon: _scheduleIcon(schedule.type),
                  title: schedule.name,
                  subtitle: '${schedule.startTime} - ${schedule.endTime}',
                  color: Colors.blue,
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildActivityCard(
    BuildContext context, {
    required String icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ],
      ),
    );
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
        return const Color(0xFF6B7280);
      case 'gambling':
        return const Color(0xFF8B5CF6);
      case 'dating':
        return const Color(0xFFEC4899);
      case 'weapons':
        return const Color(0xFF991B1B);
      case 'drugs':
        return const Color(0xFF92400E);
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
        return Icons.block;
      case 'gambling':
        return Icons.casino;
      case 'dating':
        return Icons.favorite;
      case 'weapons':
        return Icons.gpp_bad;
      case 'drugs':
        return Icons.medication;
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

  String _scheduleIcon(ScheduleType type) {
    switch (type) {
      case ScheduleType.bedtime:
        return '🌙';
      case ScheduleType.school:
        return '🏫';
      case ScheduleType.homework:
        return '📚';
      case ScheduleType.custom:
        return '⏰';
    }
  }

  String _getNextScheduleChange() {
    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final today = Day.values[DateTime.now().weekday - 1];

    if (_activeMode != ActiveMode.freeTime) {
      for (final schedule in widget.child.policy.schedules) {
        if (!schedule.enabled || !schedule.days.contains(today)) {
          continue;
        }
        if (_isTimeInRange(now, schedule.startTime, schedule.endTime)) {
          return 'Until ${schedule.endTime}';
        }
      }
      return 'Active now';
    }

    var nearestStartMinutes = 24 * 60 + 1;
    String? nearestMessage;
    for (final schedule in widget.child.policy.schedules) {
      if (!schedule.enabled || !schedule.days.contains(today)) {
        continue;
      }
      try {
        final parts = schedule.startTime.split(':');
        if (parts.length != 2) {
          continue;
        }
        final startMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        if (startMinutes > currentMinutes &&
            startMinutes < nearestStartMinutes) {
          nearestStartMinutes = startMinutes;
          nearestMessage = '${schedule.name} starts at ${schedule.startTime}';
        }
      } catch (_) {
        continue;
      }
    }
    return nearestMessage ?? 'No schedules coming up today';
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

  String _formattedDate() {
    final now = DateTime.now();
    const days = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}
