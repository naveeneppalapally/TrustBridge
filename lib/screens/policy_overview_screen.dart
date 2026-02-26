import 'package:flutter/material.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/schedule.dart';
import 'package:trustbridge_app/screens/age_preset_policy_screen.dart';
import 'package:trustbridge_app/screens/block_categories_screen.dart';
import 'package:trustbridge_app/screens/custom_domains_screen.dart';
import 'package:trustbridge_app/screens/nextdns_controls_screen.dart';
import 'package:trustbridge_app/screens/quick_modes_screen.dart';
import 'package:trustbridge_app/screens/schedule_creator_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/remote_command_service.dart';

class PolicyOverviewScreen extends StatefulWidget {
  const PolicyOverviewScreen({
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
  State<PolicyOverviewScreen> createState() => _PolicyOverviewScreenState();
}

class _PolicyOverviewScreenState extends State<PolicyOverviewScreen> {
  late ChildProfile _child;
  AuthService? _authService;
  FirestoreService? _firestoreService;
  bool _isSavingSafeSearch = false;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  String? get _parentId {
    return widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
  }

  @override
  void initState() {
    super.initState();
    _child = widget.child;
  }

  @override
  Widget build(BuildContext context) {
    final policy = _child.policy;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageWidth = MediaQuery.sizeOf(context).width;
    final isTablet = pageWidth >= 700;
    final backgroundColor =
        isDark ? const Color(0xFF101A22) : const Color(0xFFF5F7F8);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('${_child.nickname}\'s Policy'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(isTablet ? 24 : 16, 8, isTablet ? 24 : 16, 28),
        children: [
          Text(
            'Content & Time Controls',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage what ${_child.nickname} can access and when.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 20),
          _buildQuickStatsCard(context, policy),
          const SizedBox(height: 12),
          _buildAgePresetCard(context),
          const SizedBox(height: 12),
          _buildQuickModesCard(context, policy),
          const SizedBox(height: 12),
          _buildBlockedContentCard(context, policy),
          const SizedBox(height: 12),
          _buildTimeRestrictionsCard(context, policy),
          const SizedBox(height: 12),
          _buildSafeSearchCard(context, policy),
          const SizedBox(height: 12),
          _buildNextDnsControlsCard(context),
          const SizedBox(height: 12),
          _buildCustomDomainsCard(context, policy),
        ],
      ),
    );
  }

  Widget _buildQuickStatsCard(BuildContext context, Policy policy) {
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
              'Protection Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    context,
                    icon: Icons.block,
                    label: 'Categories\nBlocked',
                    value: '${policy.blockedCategories.length}',
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatBox(
                    context,
                    icon: Icons.schedule,
                    label: 'Time\nRules',
                    value: '${policy.schedules.length}',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatBox(
                    context,
                    icon: Icons.domain,
                    label: 'Custom\nDomains',
                    value: '${policy.blockedDomains.length}',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.2),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedContentCard(BuildContext context, Policy policy) {
    final count = policy.blockedCategories.length;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async => _openBlockCategories(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.block, color: Colors.red.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blocked Content Categories',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$count ${count == 1 ? 'category' : 'categories'} blocked',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey.shade600),
                ],
              ),
              if (count > 0) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: policy.blockedCategories.take(5).map((category) {
                    return Chip(
                      label: Text(_formatCategoryName(category)),
                      backgroundColor: Colors.red.shade50,
                      side: BorderSide(color: Colors.red.shade200),
                      labelStyle: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 12,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                if (count > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+${count - 5} more',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  'Tap to block content categories',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgePresetCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async => _openAgePreset(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.auto_fix_high, color: Colors.teal.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Age Preset',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Reapply recommended baseline for age ${_child.ageBand.value}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickModesCard(BuildContext context, Policy policy) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async => _openQuickModes(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.flash_on, color: Colors.indigo.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Modes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Apply one-tap presets for instant policy changes',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _quickModeChip(
                            '${policy.blockedCategories.length} categories'),
                        _quickModeChip('${policy.schedules.length} schedules'),
                        _quickModeChip(
                          policy.safeSearchEnabled
                              ? 'Safe Search ON'
                              : 'Safe Search OFF',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRestrictionsCard(BuildContext context, Policy policy) {
    final count = policy.schedules.length;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async => _openScheduleCreator(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.schedule, color: Colors.orange.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Time Restrictions',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$count ${count == 1 ? 'schedule' : 'schedules'} active',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey.shade600),
                ],
              ),
              if (count > 0) ...[
                const SizedBox(height: 12),
                ...policy.schedules.take(3).map(
                      (schedule) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              _getScheduleIcon(schedule.type),
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${schedule.name}: ${schedule.startTime} - ${schedule.endTime}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (count > 3)
                  Text(
                    '+${count - 3} more',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  'Tap to add time restrictions',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSafeSearchCard(BuildContext context, Policy policy) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: policy.safeSearchEnabled
                    ? Colors.green.shade100
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.search,
                color: policy.safeSearchEnabled
                    ? Colors.green.shade700
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safe Search',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isSavingSafeSearch
                        ? 'Updating safe search settings...'
                        : policy.safeSearchEnabled
                            ? 'Filters explicit results in search engines'
                            : 'Not enabled',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),
            _isSavingSafeSearch
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: policy.safeSearchEnabled,
                    onChanged: _setSafeSearchEnabled,
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _setSafeSearchEnabled(bool enabled) async {
    if (_isSavingSafeSearch || enabled == _child.policy.safeSearchEnabled) {
      return;
    }

    final previousChild = _child;
    final updatedPolicy = _child.policy.copyWith(safeSearchEnabled: enabled);
    final updatedChild = _child.copyWith(policy: updatedPolicy);

    setState(() {
      _child = updatedChild;
      _isSavingSafeSearch = true;
    });

    try {
      final parentId = _parentId;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );

      if (RolloutFlags.policySyncTriggerRemoteCommand &&
          widget.child.deviceIds.isNotEmpty) {
        final remoteCommandService = RemoteCommandService();
        for (final deviceId in widget.child.deviceIds) {
          remoteCommandService.sendRestartVpnCommand(deviceId).catchError(
                (_) => '',
              );
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingSafeSearch = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'Safe Search enabled' : 'Safe Search disabled',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _child = previousChild;
        _isSavingSafeSearch = false;
      });

      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Update Failed'),
            content: Text('Unable to update safe search: $error'),
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

  Widget _buildCustomDomainsCard(BuildContext context, Policy policy) {
    final count = policy.blockedDomains.length;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async => _openCustomDomains(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.domain, color: Colors.purple.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom Blocked Domains',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$count ${count == 1 ? 'domain' : 'domains'} blocked',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey.shade600),
                ],
              ),
              if (count > 0) ...[
                const SizedBox(height: 12),
                ...policy.blockedDomains.take(3).map(
                      (domain) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.block,
                                size: 14, color: Colors.purple.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                domain,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (count > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${count - 3} more',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  'Tap to add specific websites to block',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextDnsControlsCard(BuildContext context) {
    final hasProfile = (_child.nextDnsProfileId ?? '').trim().isNotEmpty;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async => _openNextDnsControls(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasProfile
                      ? Colors.blue.shade100
                      : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.dns_outlined,
                  color: hasProfile
                      ? Colors.blue.shade700
                      : Colors.orange.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NextDNS Blocking Controls',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasProfile
                          ? 'Services, categories, and bypass protection'
                          : 'Link a NextDNS profile first from settings',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBlockCategories(BuildContext context) async {
    final updatedChild = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => BlockCategoriesScreen(
          child: _child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );

    if (updatedChild != null && mounted) {
      setState(() {
        _child = updatedChild;
      });
    }
  }

  Future<void> _openAgePreset(BuildContext context) async {
    final updatedChild = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => AgePresetPolicyScreen(
          child: _child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );

    if (updatedChild != null && mounted) {
      setState(() {
        _child = updatedChild;
      });
    }
  }

  Future<void> _openCustomDomains(BuildContext context) async {
    final updatedChild = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => CustomDomainsScreen(
          child: _child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );

    if (updatedChild != null && mounted) {
      setState(() {
        _child = updatedChild;
      });
    }
  }

  Future<void> _openNextDnsControls(BuildContext context) async {
    final hasProfile = (_child.nextDnsProfileId ?? '').trim().isNotEmpty;
    if (!hasProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect and map NextDNS profile first.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NextDnsControlsScreen(
          child: _child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    final parentId = _parentId;
    if (parentId == null) {
      return;
    }
    final refreshed = await _resolvedFirestoreService.getChild(
      parentId: parentId,
      childId: _child.id,
    );
    if (refreshed == null || !mounted) {
      return;
    }
    setState(() {
      _child = refreshed;
    });
  }

  Future<void> _openScheduleCreator(BuildContext context) async {
    final updatedChild = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => ScheduleCreatorScreen(
          child: _child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );

    if (updatedChild != null && mounted) {
      setState(() {
        _child = updatedChild;
      });
    }
  }

  Future<void> _openQuickModes(BuildContext context) async {
    final updatedChild = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => QuickModesScreen(
          child: _child,
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );

    if (updatedChild != null && mounted) {
      setState(() {
        _child = updatedChild;
      });
    }
  }

  Widget _quickModeChip(String label) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
    );
  }

  String _formatCategoryName(String category) {
    return category
        .split('-')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
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
}
