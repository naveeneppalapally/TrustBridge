import 'package:flutter/material.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class NextDnsSettingsScreen extends StatefulWidget {
  const NextDnsSettingsScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.vpnService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final VpnServiceBase? vpnService;
  final String? parentIdOverride;

  @override
  State<NextDnsSettingsScreen> createState() => _NextDnsSettingsScreenState();
}

class _NextDnsSettingsScreenState extends State<NextDnsSettingsScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;

  final NextDnsService _nextDnsService = const NextDnsService();
  late final TextEditingController _profileIdController;

  bool _nextDnsEnabled = false;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _vpnRunning = false;
  String? _inlineError;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  VpnServiceBase get _resolvedVpnService {
    _vpnService ??= widget.vpnService ?? VpnService();
    return _vpnService!;
  }

  String? get _parentId {
    return widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
  }

  @override
  void initState() {
    super.initState();
    _profileIdController = TextEditingController();
    _refreshVpnState();
  }

  @override
  void dispose() {
    _profileIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('NextDNS Integration')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('NextDNS Integration'),
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _resolvedFirestoreService.watchParentProfile(parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    const Text(
                      'Unable to load NextDNS settings',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          _hydrateFromProfile(snapshot.data);
          final validationError = _validationError();
          final normalizedProfileId = _nextDnsService
              .sanitizedProfileIdOrNull(_profileIdController.text);
          final showEndpoints = _nextDnsEnabled &&
              normalizedProfileId != null &&
              validationError == null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text(
                'Managed DNS Profile (Optional)',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect a NextDNS profile for future upstream filtering and analytics.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  key: const Key('nextdns_enabled_switch'),
                  value: _nextDnsEnabled,
                  title: const Text('Enable NextDNS Profile'),
                  subtitle: Text(
                    _vpnRunning
                        ? 'VPN is running. Save settings, then use Sync Policy Rules.'
                        : 'VPN is currently off.',
                  ),
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          setState(() {
                            _nextDnsEnabled = value;
                            _hasChanges = true;
                            _inlineError = null;
                          });
                        },
                ),
              ),
              const SizedBox(height: 12),
              Card(
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
                        'Profile ID',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('nextdns_profile_field'),
                        controller: _profileIdController,
                        enabled: _nextDnsEnabled && !_isSaving,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText: 'e.g. abc123',
                          helperText:
                              '6-character profile ID from your NextDNS setup.',
                          errorText: _inlineError ?? validationError,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          setState(() {
                            _hasChanges = true;
                            _inlineError = null;
                          });
                        },
                      ),
                      if (showEndpoints) ...[
                        const SizedBox(height: 12),
                        _buildEndpointRow(
                          context,
                          label: 'DoH',
                          value:
                              _nextDnsService.dohEndpoint(normalizedProfileId),
                        ),
                        _buildEndpointRow(
                          context,
                          label: 'DoT',
                          value:
                              _nextDnsService.dotEndpoint(normalizedProfileId),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: Colors.blue.shade50,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Saving now also updates VPN upstream resolver settings. If VPN is active, resolver changes are applied immediately.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.blue.shade900,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key('nextdns_save_button'),
                  onPressed: _isSaving || !_hasChanges ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label:
                      Text(_isSaving ? 'Saving...' : 'Save NextDNS Settings'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEndpointRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        ],
      ),
    );
  }

  void _hydrateFromProfile(Map<String, dynamic>? profile) {
    if (_hasChanges) {
      return;
    }

    final preferences = _toMap(profile?['preferences']);
    _nextDnsEnabled = preferences['nextDnsEnabled'] == true;
    final currentProfileId = preferences['nextDnsProfileId'];
    final nextText = currentProfileId is String ? currentProfileId : '';
    if (_profileIdController.text != nextText) {
      _profileIdController.text = nextText;
    }
  }

  Map<String, dynamic> _toMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    return const {};
  }

  String? _validationError() {
    if (!_nextDnsEnabled) {
      return null;
    }
    final profileId = _profileIdController.text.trim();
    if (profileId.isEmpty) {
      return 'Profile ID is required when NextDNS is enabled.';
    }
    if (!_nextDnsService.isValidProfileId(profileId)) {
      return 'Profile ID must be 6 lowercase letters/numbers.';
    }
    return null;
  }

  Future<void> _refreshVpnState() async {
    final running = await _resolvedVpnService.isVpnRunning();
    if (!mounted) {
      return;
    }
    setState(() {
      _vpnRunning = running;
    });
  }

  Future<void> _saveSettings() async {
    final parentId = _parentId;
    if (parentId == null) {
      return;
    }

    final validationError = _validationError();
    if (validationError != null) {
      setState(() {
        _inlineError = validationError;
      });
      return;
    }

    final normalizedProfileId =
        _nextDnsService.sanitizedProfileIdOrNull(_profileIdController.text);
    final upstreamDns = _nextDnsEnabled && normalizedProfileId != null
        ? _nextDnsService.upstreamDnsHost(normalizedProfileId)
        : null;
    setState(() {
      _isSaving = true;
      _inlineError = null;
    });

    try {
      await _resolvedFirestoreService.updateParentPreferences(
        parentId: parentId,
        nextDnsEnabled: _nextDnsEnabled,
        nextDnsProfileId: _nextDnsEnabled ? normalizedProfileId : '',
      );
      final resolverUpdated =
          await _resolvedVpnService.setUpstreamDns(upstreamDns: upstreamDns);

      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _hasChanges = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _nextDnsEnabled
                ? (resolverUpdated
                    ? 'NextDNS settings saved and applied to VPN.'
                    : 'NextDNS settings saved. VPN resolver update not confirmed.')
                : (resolverUpdated
                    ? 'NextDNS integration disabled and VPN reset to default DNS.'
                    : 'NextDNS integration disabled.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save Failed'),
          content: Text('Unable to save NextDNS settings: $error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
