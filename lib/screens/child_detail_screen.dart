import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/screens/edit_child_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class ChildDetailScreen extends StatelessWidget {
  const ChildDetailScreen({
    super.key,
    required this.child,
  });

  final ChildProfile child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 700;
    final backgroundColor =
        isDark ? const Color(0xFF101A22) : const Color(0xFFF5F7F8);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(child.nickname),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Child',
            onPressed: () async {
              await _openEditScreen(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onPressed: () {
              _showMoreOptions(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(isTablet ? 24 : 16, 8, isTablet ? 24 : 16, 32),
        children: [
          _buildInfoCard(context),
          const SizedBox(height: 16),
          _buildPolicySummaryCard(context),
          const SizedBox(height: 16),
          _buildBlockedCategoriesCard(context),
          const SizedBox(height: 16),
          _buildSchedulesCard(context),
          const SizedBox(height: 16),
          _buildDevicesCard(context),
          const SizedBox(height: 16),
          _buildQuickActions(context),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: _getAvatarColor(child.ageBand),
              child: Text(
                child.nickname.isEmpty ? '?' : child.nickname[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              child.nickname,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Chip(
              label: Text('Age: ${child.ageBand.value}'),
              avatar: Icon(_getAgeBandIcon(child.ageBand), size: 16),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  'Added ${_formatDate(child.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicySummaryCard(BuildContext context) {
    final categoriesCount = child.policy.blockedCategories.length;
    final schedulesCount = child.policy.schedules.length;
    final safeSearchEnabled = child.policy.safeSearchEnabled;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Protection Overview',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 520;
                final rowChildren = [
                  Expanded(
                    child: _buildMetricBox(
                      context,
                      icon: Icons.block,
                      label: 'Categories\nBlocked',
                      value: '$categoriesCount',
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricBox(
                      context,
                      icon: Icons.schedule,
                      label: 'Time\nRestrictions',
                      value: '$schedulesCount',
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricBox(
                      context,
                      icon: Icons.search,
                      label: 'Safe\nSearch',
                      value: safeSearchEnabled ? 'ON' : 'OFF',
                      color: safeSearchEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                ];

                if (wide) {
                  return Row(children: rowChildren);
                }

                return Column(
                  children: [
                    _buildMetricBox(
                      context,
                      icon: Icons.block,
                      label: 'Categories Blocked',
                      value: '$categoriesCount',
                      color: Colors.red,
                    ),
                    const SizedBox(height: 10),
                    _buildMetricBox(
                      context,
                      icon: Icons.schedule,
                      label: 'Time Restrictions',
                      value: '$schedulesCount',
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 10),
                    _buildMetricBox(
                      context,
                      icon: Icons.search,
                      label: 'Safe Search',
                      value: safeSearchEnabled ? 'ON' : 'OFF',
                      color: safeSearchEnabled ? Colors.green : Colors.grey,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                  height: 1.15,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedCategoriesCard(BuildContext context) {
    final categories = child.policy.blockedCategories;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.block, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Blocked Content',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              Text(
                'No categories blocked yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories
                    .map(
                      (category) => Chip(
                        label: Text(_formatCategoryName(category)),
                        avatar: Icon(
                          Icons.block,
                          size: 16,
                          color: Colors.red.shade700,
                        ),
                        backgroundColor: Colors.red.shade50,
                        side: BorderSide(color: Colors.red.shade200),
                        labelStyle: TextStyle(color: Colors.red.shade900),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulesCard(BuildContext context) {
    final schedules = child.policy.schedules;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Time Restrictions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (schedules.isEmpty)
              Text(
                'No schedules configured.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else
              ...schedules.map(
                (schedule) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getScheduleIcon(schedule.type),
                            size: 18,
                            color: Colors.orange.shade700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                schedule.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${schedule.startTime} - ${schedule.endTime}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                _formatDays(schedule.days),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          schedule.enabled ? Icons.check_circle : Icons.cancel,
                          color: schedule.enabled ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_outlined, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Devices',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Device management coming in Week 5.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 460;
            if (wide) {
              return Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await _openEditScreen(context);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Profile'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showDeleteConfirmation(context),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await _openEditScreen(context);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Profile'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showDeleteConfirmation(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.pause_circle_outline),
                title: Text('Pause Device'),
                subtitle: Text('Coming in Week 7'),
                enabled: false,
              ),
              const ListTile(
                leading: Icon(Icons.history),
                title: Text('View Activity Log'),
                subtitle: Text('Coming in Week 8'),
                enabled: false,
              ),
              const ListTile(
                leading: Icon(Icons.settings_outlined),
                title: Text('Advanced Settings'),
                subtitle: Text('Coming in Week 4'),
                enabled: false,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Close'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openEditScreen(BuildContext context) async {
    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditChildScreen(child: child),
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (didUpdate == true) {
      Navigator.of(context).pop();
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
                'Are you sure you want to delete ${child.nickname}\'s profile?',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'This action cannot be undone',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('The following will be deleted:'),
                    const SizedBox(height: 4),
                    const Text('- Child profile'),
                    const Text('- Content filters'),
                    const Text('- Time restrictions'),
                    const Text('- All settings'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'This will not affect other children or your account.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
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
      builder: (_) {
        return const AlertDialog(
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
        );
      },
    );

    try {
      final authService = AuthService();
      final firestoreService = FirestoreService();
      final user = authService.currentUser;
      if (user == null) {
        throw Exception('Not logged in');
      }

      await firestoreService.deleteChild(
        parentId: user.uid,
        childId: child.id,
      );

      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${child.nickname}\'s profile has been deleted'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Delete Failed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Failed to delete child profile:'),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please try again or contact support if the problem persists.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  Color _getAvatarColor(AgeBand ageBand) {
    switch (ageBand) {
      case AgeBand.young:
        return Colors.blue;
      case AgeBand.middle:
        return Colors.green;
      case AgeBand.teen:
        return Colors.orange;
    }
  }

  IconData _getAgeBandIcon(AgeBand ageBand) {
    switch (ageBand) {
      case AgeBand.young:
        return Icons.child_care;
      case AgeBand.middle:
        return Icons.school;
      case AgeBand.teen:
        return Icons.face;
    }
  }

  IconData _getScheduleIcon(ScheduleType type) {
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

    return days.map((d) => d.name.substring(0, 3).toUpperCase()).join(', ');
  }

  String _formatCategoryName(String category) {
    return category
        .split('-')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays <= 0) {
      return 'today';
    }
    if (difference.inDays == 1) {
      return 'yesterday';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    }

    return DateFormat('MMM d, yyyy').format(date);
  }
}
