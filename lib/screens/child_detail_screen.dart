import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/screens/child_activity_log_screen.dart';
import 'package:trustbridge_app/screens/child_devices_screen.dart';
import 'package:trustbridge_app/screens/edit_child_screen.dart';
import 'package:trustbridge_app/screens/policy_overview_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class ChildDetailScreen extends StatelessWidget {
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

  AuthService get _resolvedAuthService => authService ?? AuthService();
  FirestoreService get _resolvedFirestoreService =>
      firestoreService ?? FirestoreService();
  String? get _resolvedParentId =>
      parentIdOverride ?? _resolvedAuthService.currentUser?.uid;

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
            if (_isPausedNow(child.pausedUntil)) ...[
              const SizedBox(height: 8),
              Chip(
                label: Text(
                  'Paused until ${_formatTime(child.pausedUntil!)}',
                ),
                avatar: const Icon(Icons.pause_circle_outline, size: 16),
                backgroundColor: Colors.red.shade50,
                side: BorderSide(color: Colors.red.shade200),
                labelStyle: TextStyle(color: Colors.red.shade900),
              ),
            ],
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
    final devices = child.deviceIds;
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
                  Icon(Icons.chevron_right, color: Colors.grey.shade600),
                ],
              ),
              const SizedBox(height: 12),
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
                if (devices.length > 3)
                  Text(
                    '+${devices.length - 3} more',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
              ],
            ],
          ),
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
              return Column(
                children: [
                  Row(
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
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openPolicyOverview(context),
                      icon: const Icon(Icons.policy_outlined),
                      label: const Text('Manage Policy'),
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
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openPolicyOverview(context),
                    icon: const Icon(Icons.policy_outlined),
                    label: const Text('Manage Policy'),
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
        final paused = _isPausedNow(child.pausedUntil);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(paused
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline),
                title: Text(paused ? 'Resume Internet' : 'Pause Internet'),
                subtitle: Text(
                  paused
                      ? 'Currently paused until ${_formatTime(child.pausedUntil!)}'
                      : 'Temporarily block internet access for this child',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  if (paused) {
                    await _resumeInternet(context);
                  } else {
                    await _showPauseDurationPicker(context);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('View Activity Log'),
                subtitle: const Text('Profile and policy timeline'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openActivityLog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Advanced Settings'),
                subtitle: const Text('Manage policy and safety controls'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openPolicyOverview(context);
                },
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
        builder: (_) => EditChildScreen(
          child: child,
          authService: authService,
          firestoreService: firestoreService,
          parentIdOverride: parentIdOverride,
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PolicyOverviewScreen(
          child: child,
          authService: authService,
          firestoreService: firestoreService,
          parentIdOverride: parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openManageDevices(BuildContext context) async {
    final updatedChild = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => ChildDevicesScreen(
          child: child,
          authService: authService,
          firestoreService: firestoreService,
          parentIdOverride: parentIdOverride,
        ),
      ),
    );
    if (!context.mounted || updatedChild == null) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChildDetailScreen(
          child: updatedChild,
          authService: authService,
          firestoreService: firestoreService,
          parentIdOverride: parentIdOverride,
        ),
      ),
    );
  }

  Future<void> _openActivityLog(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildActivityLogScreen(child: child),
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
                onTap: () => Navigator.of(context).pop(
                  const Duration(minutes: 15),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('30 minutes'),
                onTap: () => Navigator.of(context).pop(
                  const Duration(minutes: 30),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('1 hour'),
                onTap: () => Navigator.of(context).pop(
                  const Duration(hours: 1),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (duration == null) {
      return;
    }
    if (!context.mounted) {
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
    final updatedChild = child.copyWith(pausedUntil: pausedUntil);

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
        'Internet paused until ${_formatTime(pausedUntil)}',
        success: true,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChildDetailScreen(
            child: updatedChild,
            authService: authService,
            firestoreService: firestoreService,
            parentIdOverride: parentIdOverride,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Unable to pause internet: $error');
    }
  }

  Future<void> _resumeInternet(BuildContext context) async {
    final parentId = _resolvedParentId;
    if (parentId == null) {
      _showMessage(context, 'Not logged in');
      return;
    }

    final updatedChild = child.copyWith(clearPausedUntil: true);
    try {
      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Internet resumed', success: true);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChildDetailScreen(
            child: updatedChild,
            authService: authService,
            firestoreService: firestoreService,
            parentIdOverride: parentIdOverride,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, 'Unable to resume internet: $error');
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
      final parentId = _resolvedParentId;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      await _resolvedFirestoreService.deleteChild(
        parentId: parentId,
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

  bool _isPausedNow(DateTime? pausedUntil) {
    return pausedUntil != null && pausedUntil.isAfter(DateTime.now());
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

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
