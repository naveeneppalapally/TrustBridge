import 'package:flutter/material.dart';

import '../config/rollout_flags.dart';
import '../config/service_definitions.dart';
import '../models/child_profile.dart';
import '../models/installed_app_info.dart';
import '../models/policy.dart';
import '../models/service_definition.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/parent_pin_gate.dart';

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
    'bedtime': 'Bedtime',
    'homework': 'Homework',
    'focus': 'Focus',
    'free': 'Free Play',
  };

  AuthService? _authService;
  FirestoreService? _firestoreService;

  late final Map<String, ModeOverrideSet> _workingModeOverrides;
  String _selectedMode = 'bedtime';
  bool _saving = false;
  bool _loadingInstalledApps = false;
  String _query = '';
  List<InstalledAppInfo> _installedApps = const <InstalledAppInfo>[];

  late Set<String> _forceBlockServices;
  late Set<String> _forceAllowServices;
  late Set<String> _forceBlockPackages;
  late Set<String> _forceAllowPackages;

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
    try {
      return _resolvedAuthService.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _workingModeOverrides = <String, ModeOverrideSet>{
      for (final entry in widget.child.policy.modeOverrides.entries)
        entry.key: entry.value,
    };
    _hydrateSelectedMode();
    if (RolloutFlags.modeAppOverrides && RolloutFlags.appInventory) {
      _loadInstalledApps();
    }
  }

  void _hydrateSelectedMode() {
    final current =
        _workingModeOverrides[_selectedMode] ?? const ModeOverrideSet();
    _forceBlockServices = current.forceBlockServices
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    _forceAllowServices = current.forceAllowServices
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    _forceBlockPackages = current.forceBlockPackages
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    _forceAllowPackages = current.forceAllowPackages
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  void _persistSelectedMode() {
    _workingModeOverrides[_selectedMode] = ModeOverrideSet(
      forceBlockServices: _ordered(_forceBlockServices),
      forceAllowServices: _ordered(_forceAllowServices),
      forceBlockPackages: _ordered(_forceBlockPackages),
      forceAllowPackages: _ordered(_forceAllowPackages),
      forceBlockDomains:
          _workingModeOverrides[_selectedMode]?.forceBlockDomains ??
              const <String>[],
      forceAllowDomains:
          _workingModeOverrides[_selectedMode]?.forceAllowDomains ??
              const <String>[],
    );
  }

  Future<void> _loadInstalledApps() async {
    if (!RolloutFlags.appInventory) {
      return;
    }
    final parentId = _parentId?.trim();
    if (parentId == null || parentId.isEmpty) {
      return;
    }
    setState(() => _loadingInstalledApps = true);
    try {
      final apps = await _resolvedFirestoreService.getChildInstalledAppsOnce(
        parentId: parentId,
        childId: widget.child.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _installedApps = apps;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _installedApps = const <InstalledAppInfo>[];
      });
    } finally {
      if (mounted) {
        setState(() => _loadingInstalledApps = false);
      }
    }
  }

  List<InstalledAppInfo> get _visibleInstalledApps {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _installedApps;
    }
    return _installedApps.where((app) {
      return app.appName.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (!RolloutFlags.modeAppOverrides) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mode Overrides'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Mode overrides are temporarily disabled by rollout flag.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mode Overrides'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          Text(
            'Child: ${widget.child.nickname}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose one mode, then mark apps/services as Block or Allow for that mode only.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _modeLabels.entries.map((entry) {
              final selected = _selectedMode == entry.key;
              final counts = _modeCountLabel(entry.key);
              return ChoiceChip(
                label: Text('${entry.value} ($counts)'),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _persistSelectedMode();
                    _selectedMode = entry.key;
                    _hydrateSelectedMode();
                  });
                },
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 16),
          _buildServiceOverridesSection(),
          if (RolloutFlags.appInventory) ...[
            const SizedBox(height: 16),
            _buildInstalledAppsSection(),
          ],
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
            label: Text(_saving ? 'Saving…' : 'Save Mode Overrides'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceOverridesSection() {
    final services = ServiceDefinitions.all.toList(growable: false)
      ..sort(
        (left, right) => left.displayName
            .toLowerCase()
            .compareTo(right.displayName.toLowerCase()),
      );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Mapped Services (App + Web)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use this for cataloged services such as Instagram, YouTube, TikTok.',
            ),
            const SizedBox(height: 10),
            ...services.map((service) => _buildServiceRow(service)),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceRow(ServiceDefinition service) {
    final serviceId = service.serviceId.trim().toLowerCase();
    final blocked = _forceBlockServices.contains(serviceId);
    final allowed = _forceAllowServices.contains(serviceId);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(service.displayName),
      subtitle: Text(service.categoryId),
      trailing: Wrap(
        spacing: 8,
        children: <Widget>[
          FilterChip(
            label: const Text('Block'),
            selected: blocked,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _forceBlockServices.add(serviceId);
                  _forceAllowServices.remove(serviceId);
                } else {
                  _forceBlockServices.remove(serviceId);
                }
              });
            },
          ),
          FilterChip(
            label: const Text('Allow'),
            selected: allowed,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _forceAllowServices.add(serviceId);
                  _forceBlockServices.remove(serviceId);
                } else {
                  _forceAllowServices.remove(serviceId);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledAppsSection() {
    final visibleApps = _visibleInstalledApps;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Installed Apps (Child Device)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search app name or package',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingInstalledApps)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visibleApps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No installed apps found yet.'),
              )
            else
              ...visibleApps.map((app) => _buildInstalledAppRow(app)),
          ],
        ),
      ),
    );
  }

  Widget _buildInstalledAppRow(InstalledAppInfo app) {
    final packageName = app.packageName.trim().toLowerCase();
    final blocked = _forceBlockPackages.contains(packageName);
    final allowed = _forceAllowPackages.contains(packageName);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(app.appName),
      subtitle: Text(app.packageName),
      trailing: Wrap(
        spacing: 8,
        children: <Widget>[
          FilterChip(
            label: const Text('Block'),
            selected: blocked,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _forceBlockPackages.add(packageName);
                  _forceAllowPackages.remove(packageName);
                } else {
                  _forceBlockPackages.remove(packageName);
                }
              });
            },
          ),
          FilterChip(
            label: const Text('Allow'),
            selected: allowed,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _forceAllowPackages.add(packageName);
                  _forceBlockPackages.remove(packageName);
                } else {
                  _forceAllowPackages.remove(packageName);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  String _modeCountLabel(String modeKey) {
    final mode = _workingModeOverrides[modeKey] ?? const ModeOverrideSet();
    final blockCount =
        mode.forceBlockServices.length + mode.forceBlockPackages.length;
    final allowCount =
        mode.forceAllowServices.length + mode.forceAllowPackages.length;
    return 'B$blockCount/A$allowCount';
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

    final authorized = await requireParentPin(context);
    if (!authorized || !mounted) {
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mode overrides saved')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save mode overrides: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
