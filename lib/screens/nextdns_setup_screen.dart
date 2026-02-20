import 'package:flutter/material.dart';
import 'package:trustbridge_app/config/feature_gates.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/upgrade_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/feature_gate_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';

class NextDnsSetupScreen extends StatefulWidget {
  const NextDnsSetupScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.nextDnsApiService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final NextDnsApiService? nextDnsApiService;
  final String? parentIdOverride;

  @override
  State<NextDnsSetupScreen> createState() => _NextDnsSetupScreenState();
}

class _NextDnsSetupScreenState extends State<NextDnsSetupScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  NextDnsApiService? _nextDnsApiService;
  final FeatureGateService _featureGateService = FeatureGateService();

  final TextEditingController _apiKeyController = TextEditingController();

  bool _loading = true;
  bool _gateAllowed = true;
  bool _connecting = false;
  bool _migrating = false;
  String? _error;

  List<ChildProfile> _children = <ChildProfile>[];
  List<NextDnsProfileSummary> _profiles = <NextDnsProfileSummary>[];
  final Map<String, String?> _selectedProfilePerChild = <String, String?>{};

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  NextDnsApiService get _resolvedNextDnsApiService {
    _nextDnsApiService ??= widget.nextDnsApiService ?? NextDnsApiService();
    return _nextDnsApiService!;
  }

  String? get _parentId {
    final override = widget.parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return _resolvedAuthService.currentUser?.uid;
  }

  bool get _isConnected => _profiles.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _resolveGateAndLoad();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _resolveGateAndLoad() async {
    final gate = await () async {
      try {
        return await _featureGateService
            .checkGate(AppFeature.nextDnsIntegration);
      } catch (_) {
        // Allow setup in non-Firebase test contexts.
        return const GateResult(allowed: true);
      }
    }();
    if (!gate.allowed) {
      if (!mounted) {
        return;
      }
      setState(() {
        _gateAllowed = false;
        _loading = false;
      });
      await UpgradeScreen.maybeShow(
        context,
        feature: AppFeature.nextDnsIntegration,
        reason: gate.upgradeReason,
      );
      return;
    }
    _gateAllowed = true;
    await _loadSetupState();
  }

  Future<void> _loadSetupState() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final parentId = _parentId;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      final savedKey = await _resolvedNextDnsApiService.getNextDnsApiKey();
      if (savedKey != null) {
        _apiKeyController.text = savedKey;
      }

      final children =
          await _resolvedFirestoreService.getChildrenOnce(parentId);
      List<NextDnsProfileSummary> profiles = const <NextDnsProfileSummary>[];
      if (savedKey != null && savedKey.trim().isNotEmpty) {
        profiles = await _resolvedNextDnsApiService.fetchProfiles(
          apiKey: savedKey,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _children = children;
        _profiles = profiles;
        _selectedProfilePerChild
          ..clear()
          ..addEntries(
            children.map(
              (child) => MapEntry(child.id, child.nextDnsProfileId),
            ),
          );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _connectApiKey() async {
    final parentId = _parentId;
    if (parentId == null) {
      return;
    }

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _error = 'Enter your NextDNS API key first.';
      });
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      await _resolvedNextDnsApiService.setNextDnsApiKey(apiKey);
      final profiles = await _resolvedNextDnsApiService.fetchProfiles(
        apiKey: apiKey,
      );

      await _resolvedFirestoreService.updateParentPreferences(
        parentId: parentId,
        nextDnsApiConnected: true,
        nextDnsConnectedAt: DateTime.now(),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _profiles = profiles;
        _connecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profiles.isEmpty
                ? 'Connected. No profiles found yet.'
                : 'Connected to NextDNS (${profiles.length} profiles).',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connecting = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _assignProfile({
    required ChildProfile child,
    required String profileId,
  }) async {
    final parentId = _parentId;
    if (parentId == null) {
      return;
    }

    try {
      await _resolvedFirestoreService.setChildNextDnsProfileId(
        parentId: parentId,
        childId: child.id,
        profileId: profileId,
      );
      await _resolvedFirestoreService.updateParentPreferences(
        parentId: parentId,
        nextDnsEnabled: true,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedProfilePerChild[child.id] = profileId;
        _children = _children
            .map(
              (item) => item.id == child.id
                  ? item.copyWith(nextDnsProfileId: profileId)
                  : item,
            )
            .toList(growable: false);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${child.nickname} linked to profile $profileId'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign profile: $error'),
        ),
      );
    }
  }

  Future<void> _createProfileForChild(ChildProfile child) async {
    try {
      final profile = await _resolvedNextDnsApiService.createProfile(
        name: child.nickname,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profiles = <NextDnsProfileSummary>[profile, ..._profiles];
      });
      await _assignProfile(child: child, profileId: profile.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create profile: $error'),
        ),
      );
    }
  }

  Future<void> _migrateMissingChildren() async {
    final parentId = _parentId;
    if (parentId == null || _migrating) {
      return;
    }

    setState(() {
      _migrating = true;
      _error = null;
    });

    try {
      final migratedCount = await _resolvedFirestoreService
          .migrateChildrenWithoutNextDnsProfiles(parentId);
      await _loadSetupState();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Migrated $migratedCount child profiles.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _migrating = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_parentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('NextDNS Setup')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    if (!_gateAllowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('NextDNS Setup')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 42),
                const SizedBox(height: 10),
                const Text(
                  'NextDNS integration is available with TrustBridge Pro.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => UpgradeScreen.maybeShow(
                    context,
                    feature: AppFeature.nextDnsIntegration,
                  ),
                  child: const Text('Upgrade options'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('NextDNS Setup'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadSetupState,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: <Widget>[
                _buildApiKeyCard(context),
                const SizedBox(height: 12),
                _buildMigrationCard(context),
                const SizedBox(height: 12),
                _buildChildrenMapCard(context),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildApiKeyCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Connect NextDNS',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              _isConnected
                  ? 'Connected (${_profiles.length} profiles found).'
                  : 'Add your NextDNS API key to load profiles.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('nextdns_setup_api_key_field'),
              controller: _apiKeyController,
              enabled: !_connecting,
              textInputAction: TextInputAction.done,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'NextDNS API Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('nextdns_setup_connect_button'),
                onPressed: _connecting ? null : _connectApiKey,
                icon: _connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_connecting ? 'Connecting...' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMigrationCard(BuildContext context) {
    final missingCount = _children
        .where((child) => (child.nextDnsProfileId ?? '').trim().isEmpty)
        .length;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: const Text('Auto-link missing children'),
        subtitle: Text(
          missingCount == 0
              ? 'All children already linked to NextDNS profiles.'
              : '$missingCount children still need profile mapping.',
        ),
        trailing: FilledButton(
          onPressed:
              missingCount == 0 || _migrating ? null : _migrateMissingChildren,
          child: Text(_migrating ? 'Running...' : 'Migrate'),
        ),
      ),
    );
  }

  Widget _buildChildrenMapCard(BuildContext context) {
    if (_children.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No children found. Add a child profile first.'),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Child Profile Mapping',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Each child should be linked to one NextDNS profile.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 12),
            ..._children.map(_buildChildMappingRow),
          ],
        ),
      ),
    );
  }

  Widget _buildChildMappingRow(ChildProfile child) {
    final selected = _selectedProfilePerChild[child.id];
    final hasProfiles = _profiles.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 14,
                child: Text(
                  child.nickname.isEmpty
                      ? '?'
                      : child.nickname[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  child.nickname,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Create profile for child',
                onPressed:
                    _isConnected ? () => _createProfileForChild(child) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(
              'nextdns_child_profile_dropdown_${child.id}_${selected ?? 'none'}',
            ),
            initialValue: selected,
            items: _profiles
                .map(
                  (profile) => DropdownMenuItem<String>(
                    value: profile.id,
                    child: Text('${profile.name} (${profile.id})'),
                  ),
                )
                .toList(growable: false),
            onChanged: hasProfiles
                ? (value) {
                    setState(() {
                      _selectedProfilePerChild[child.id] = value;
                    });
                  }
                : null,
            decoration: const InputDecoration(
              labelText: 'NextDNS profile',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: Key('nextdns_assign_button_${child.id}'),
              onPressed: selected == null
                  ? null
                  : () => _assignProfile(child: child, profileId: selected),
              child: const Text('Save Mapping'),
            ),
          ),
        ],
      ),
    );
  }
}
