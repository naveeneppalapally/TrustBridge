import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class AgePresetPolicyScreen extends StatefulWidget {
  const AgePresetPolicyScreen({
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
  State<AgePresetPolicyScreen> createState() => _AgePresetPolicyScreenState();
}

class _AgePresetPolicyScreenState extends State<AgePresetPolicyScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  bool _isApplying = false;

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

  Policy get _recommendedPolicy {
    final preset = Policy.presetForAgeBand(widget.child.ageBand);
    return preset.copyWith(
      blockedDomains: widget.child.policy.blockedDomains,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.child.policy;
    final recommended = _recommendedPolicy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Age Preset'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Recommended for Age ${widget.child.ageBand.value}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Reapply the age-based policy baseline for ${widget.child.nickname}.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          _buildPresetSummary(context, recommended),
          const SizedBox(height: 12),
          _buildComparisonCard(context, current, recommended),
          const SizedBox(height: 12),
          _buildCategoryPreview(context, recommended),
          const SizedBox(height: 12),
          _buildDomainPreserveNote(context, current),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _isApplying ? null : _confirmAndApplyPreset,
              icon: _isApplying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.replay),
              label: Text(
                  _isApplying ? 'Applying...' : 'Apply Recommended Preset'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSummary(BuildContext context, Policy recommended) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _metricChip(
                context,
                icon: Icons.block,
                label: 'Categories',
                value: '${recommended.blockedCategories.length}',
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricChip(
                context,
                icon: Icons.schedule,
                label: 'Schedules',
                value: '${recommended.schedules.length}',
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricChip(
                context,
                icon: Icons.search,
                label: 'Safe Search',
                value: recommended.safeSearchEnabled ? 'ON' : 'OFF',
                color:
                    recommended.safeSearchEnabled ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonCard(
    BuildContext context,
    Policy current,
    Policy recommended,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current vs Recommended',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            _deltaRow(
              context,
              label: 'Blocked Categories',
              before: '${current.blockedCategories.length}',
              after: '${recommended.blockedCategories.length}',
            ),
            const SizedBox(height: 8),
            _deltaRow(
              context,
              label: 'Schedules',
              before: '${current.schedules.length}',
              after: '${recommended.schedules.length}',
            ),
            const SizedBox(height: 8),
            _deltaRow(
              context,
              label: 'Safe Search',
              before: current.safeSearchEnabled ? 'ON' : 'OFF',
              after: recommended.safeSearchEnabled ? 'ON' : 'OFF',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPreview(BuildContext context, Policy recommended) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Blocked Categories',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recommended.blockedCategories.take(8).map((category) {
                return Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_formatCategoryName(category)),
                );
              }).toList(),
            ),
            if (recommended.blockedCategories.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${recommended.blockedCategories.length - 8} more',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainPreserveNote(BuildContext context, Policy current) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Custom blocked domains (${current.blockedDomains.length}) will be preserved.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blue.shade900,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _deltaRow(
    BuildContext context, {
    required String label,
    required String before,
    required String after,
  }) {
    final changed = before != after;
    return Row(
      children: [
        Expanded(
          child: Text(label),
        ),
        Text(
          before,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: changed ? Colors.grey.shade600 : null,
                decoration: changed ? TextDecoration.lineThrough : null,
              ),
        ),
        if (changed) ...[
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward, size: 14),
          const SizedBox(width: 6),
          Text(
            after,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmAndApplyPreset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Apply Age Preset?'),
          content: const Text(
            'This will reset blocked categories, schedules, and safe search to age-recommended defaults.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isApplying = true;
    });

    try {
      final parentId = _parentId;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      final updatedChild = widget.child.copyWith(policy: _recommendedPolicy);
      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Age preset applied successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(updatedChild);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isApplying = false;
      });
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Apply Failed'),
            content: Text('Unable to apply age preset: $error'),
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

  String _formatCategoryName(String category) {
    return category
        .split('-')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}
