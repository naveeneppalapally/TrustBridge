import 'package:flutter/material.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/policy_quick_modes.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/remote_command_service.dart';

class QuickModesScreen extends StatefulWidget {
  const QuickModesScreen({
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
  State<QuickModesScreen> createState() => _QuickModesScreenState();
}

class _QuickModesScreenState extends State<QuickModesScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;

  PolicyQuickMode? _selectedMode;
  bool _isSaving = false;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  List<PolicyQuickModeConfig> get _availableModes =>
      PolicyQuickModes.configsForAgeBand(widget.child.ageBand);

  Policy? get _previewPolicy {
    final mode = _selectedMode;
    if (mode == null) {
      return null;
    }
    return PolicyQuickModes.applyMode(
      currentPolicy: widget.child.policy,
      mode: mode,
      ageBand: widget.child.ageBand,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewPolicy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Modes'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'One-Tap Policy Presets',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Apply a complete preset instantly for ${widget.child.nickname}.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          RadioGroup<PolicyQuickMode>(
            groupValue: _selectedMode,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedMode = value;
              });
            },
            child: Column(
              children: _availableModes
                  .map((mode) => _buildModeCard(context, mode))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          _buildPreviewCard(context, preview),
          const SizedBox(height: 16),
          _buildDomainNote(context),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed:
                  _selectedMode == null || _isSaving ? null : _confirmAndApply,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.flash_on),
              label: Text(
                _isSaving ? 'Applying...' : 'Apply Mode',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(BuildContext context, PolicyQuickModeConfig config) {
    final selected = _selectedMode == config.mode;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            _selectedMode = config.mode;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Radio<PolicyQuickMode>(
                value: config.mode,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      config.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statChip(
                            '${config.blockedCategories.length} categories'),
                        _statChip('${config.schedules.length} schedules'),
                        _statChip(
                          config.safeSearchEnabled
                              ? 'Safe Search ON'
                              : 'Safe Search OFF',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context, Policy? previewPolicy) {
    final current = widget.child.policy;

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
              'Preview Changes',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            if (previewPolicy == null)
              Text(
                'Select a mode to preview how policy settings will change.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else ...[
              _deltaRow(
                context,
                label: 'Blocked Categories',
                before: '${current.blockedCategories.length}',
                after: '${previewPolicy.blockedCategories.length}',
              ),
              const SizedBox(height: 6),
              _deltaRow(
                context,
                label: 'Schedules',
                before: '${current.schedules.length}',
                after: '${previewPolicy.schedules.length}',
              ),
              const SizedBox(height: 6),
              _deltaRow(
                context,
                label: 'Safe Search',
                before: current.safeSearchEnabled ? 'ON' : 'OFF',
                after: previewPolicy.safeSearchEnabled ? 'ON' : 'OFF',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDomainNote(BuildContext context) {
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
              'Custom blocked domains are preserved when applying a quick mode.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blue.shade900,
                  ),
            ),
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
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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

  Widget _statChip(String label) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
    );
  }

  Future<void> _confirmAndApply() async {
    final selectedMode = _selectedMode;
    if (selectedMode == null) {
      return;
    }

    final config = PolicyQuickModes.configFor(
      mode: selectedMode,
      ageBand: widget.child.ageBand,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Apply Quick Mode?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Apply "${config.title}" to ${widget.child.nickname}?'),
              const SizedBox(height: 10),
              const Text(
                'This will update blocked categories, schedules, and safe search.',
              ),
              const SizedBox(height: 10),
              const Text(
                'Custom domains will not be removed.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
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
      _isSaving = true;
    });

    try {
      final parentId =
          widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      final updatedPolicy = PolicyQuickModes.applyMode(
        currentPolicy: widget.child.policy,
        mode: selectedMode,
        ageBand: widget.child.ageBand,
      );
      final updatedChild = widget.child.copyWith(policy: updatedPolicy);

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${config.title} applied successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(updatedChild);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Apply Failed'),
            content: Text('Unable to apply quick mode: $error'),
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
}
