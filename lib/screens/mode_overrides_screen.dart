import 'package:flutter/material.dart';

import '../config/service_definitions.dart';
import '../models/child_profile.dart';
import '../models/policy.dart';
import '../models/service_definition.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/remote_command_service.dart';

class ModeOverridesScreen extends StatefulWidget {
  const ModeOverridesScreen({
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
  State<ModeOverridesScreen> createState() => _ModeOverridesScreenState();
}

class _ModeOverridesScreenState extends State<ModeOverridesScreen> {
  static const Map<String, String> _modeLabels = <String, String>{
    'homework': 'Homework',
    'bedtime': 'Bedtime',
    'free': 'Free Play',
  };

  static const List<_ServiceGroup> _groups = <_ServiceGroup>[
    _ServiceGroup(
      title: 'Social Media',
      categoryId: 'social-networks',
      hint: 'Instagram, Facebook, Snapchat, TikTok',
    ),
    _ServiceGroup(
      title: 'Messaging',
      categoryId: 'chat',
      hint: 'WhatsApp, Telegram, Discord',
    ),
    _ServiceGroup(
      title: 'Streaming',
      categoryId: 'streaming',
      hint: 'YouTube and video apps',
    ),
    _ServiceGroup(
      title: 'Gaming',
      categoryId: 'games',
      hint: 'Roblox and online games',
    ),
  ];

  static const List<String> _popularServiceIds = <String>[
    'instagram',
    'youtube',
    'tiktok',
    'facebook',
    'snapchat',
    'whatsapp',
    'telegram',
    'discord',
    'roblox',
  ];

  AuthService? _authService;
  FirestoreService? _firestoreService;

  late final Map<String, ModeOverrideSet> _workingModeOverrides;
  String _selectedMode = 'homework';
  bool _saving = false;
  late Set<String> _blockedServiceIds;

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
  void initState() {
    super.initState();
    _workingModeOverrides = <String, ModeOverrideSet>{
      for (final entry in widget.child.policy.modeOverrides.entries)
        entry.key: entry.value,
    };
    _hydrateSelectedMode();
  }

  @override
  Widget build(BuildContext context) {
    final modeLabel = _modeLabels[_selectedMode] ?? 'Mode';
    return Scaffold(
      appBar: AppBar(title: const Text('Easy Mode Setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          Text(
            'Child: ${widget.child.nickname}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a mode and choose what should be blocked in that mode.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Lockdown follows Bedtime rules.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _modeLabels.entries.map((entry) {
              return ChoiceChip(
                label: Text(entry.value),
                selected: _selectedMode == entry.key,
                onSelected: (_) => _switchMode(entry.key),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '$modeLabel: Quick Toggles',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Turn these on to block that group.'),
                ),
                const Divider(height: 1),
                ..._groups.map((group) => _buildGroupToggle(group)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    'Popular Apps',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Use these for app-specific control in this mode.',
                  ),
                ),
                const Divider(height: 1),
                ..._popularServices()
                    .map((service) => _buildServiceToggle(service)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Saving...' : 'Save $modeLabel Rules'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupToggle(_ServiceGroup group) {
    final serviceIds = _serviceIdsForCategory(group.categoryId);
    final allBlocked = serviceIds.isNotEmpty &&
        serviceIds.every((serviceId) => _blockedServiceIds.contains(serviceId));

    return SwitchListTile(
      title: Text(group.title),
      subtitle: Text(group.hint),
      value: allBlocked,
      onChanged: (value) {
        setState(() {
          if (value) {
            _blockedServiceIds.addAll(serviceIds);
          } else {
            _blockedServiceIds.removeWhere(serviceIds.contains);
          }
        });
      },
    );
  }

  Widget _buildServiceToggle(ServiceDefinition service) {
    final serviceId = service.serviceId.trim().toLowerCase();
    final blocked = _blockedServiceIds.contains(serviceId);
    return CheckboxListTile(
      value: blocked,
      title: Text(service.displayName),
      subtitle: Text(_prettyCategoryLabel(service.categoryId)),
      onChanged: (value) {
        setState(() {
          if (value == true) {
            _blockedServiceIds.add(serviceId);
          } else {
            _blockedServiceIds.remove(serviceId);
          }
        });
      },
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  String _prettyCategoryLabel(String categoryId) {
    final normalized = categoryId.trim().toLowerCase();
    switch (normalized) {
      case 'social-networks':
        return 'Social Media';
      case 'streaming':
        return 'Streaming';
      case 'games':
        return 'Gaming';
      case 'chat':
        return 'Messaging';
      default:
        return normalized;
    }
  }

  List<ServiceDefinition> _popularServices() {
    final services = <ServiceDefinition>[];
    for (final serviceId in _popularServiceIds) {
      final service = ServiceDefinitions.byId[serviceId];
      if (service != null) {
        services.add(service);
      }
    }
    return services;
  }

  List<String> _serviceIdsForCategory(String categoryId) {
    return ServiceDefinitions.servicesForCategory(categoryId);
  }

  void _switchMode(String modeKey) {
    setState(() {
      _persistSelectedMode();
      _selectedMode = modeKey;
      _hydrateSelectedMode();
    });
  }

  void _hydrateSelectedMode() {
    final current =
        _workingModeOverrides[_selectedMode] ?? const ModeOverrideSet();
    _blockedServiceIds = current.forceBlockServices
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  void _persistSelectedMode() {
    final current =
        _workingModeOverrides[_selectedMode] ?? const ModeOverrideSet();
    final blockedServices = _ordered(_blockedServiceIds);
    final allowedServices = current.forceAllowServices
        .map((value) => value.trim().toLowerCase())
        .where(
            (value) => value.isNotEmpty && !_blockedServiceIds.contains(value))
        .toSet();
    final updated = current.copyWith(
      forceBlockServices: blockedServices,
      forceAllowServices: _ordered(allowedServices),
    );
    if (updated.isEmpty) {
      _workingModeOverrides.remove(_selectedMode);
    } else {
      _workingModeOverrides[_selectedMode] = updated;
    }
  }

  List<String> _ordered(Set<String> values) {
    final sorted = values.toList()..sort();
    return sorted;
  }

  Future<void> _save() async {
    final parentId = _parentId?.trim();
    if (parentId == null || parentId.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Parent session missing. Please sign in.')),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() => _saving = true);
    try {
      _persistSelectedMode();
      final updatedPolicy = widget.child.policy.copyWith(
        modeOverrides: _workingModeOverrides,
      );
      final updatedChild = widget.child.copyWith(policy: updatedPolicy);
      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );

      if (widget.child.deviceIds.isNotEmpty) {
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
        const SnackBar(content: Text('Mode rules saved')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save mode rules: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _ServiceGroup {
  const _ServiceGroup({
    required this.title,
    required this.categoryId,
    required this.hint,
  });

  final String title;
  final String categoryId;
  final String hint;
}
