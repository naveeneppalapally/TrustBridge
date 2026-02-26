import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trustbridge_app/config/rollout_flags.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/remote_command_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class CustomDomainsScreen extends StatefulWidget {
  const CustomDomainsScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.vpnService,
    this.parentIdOverride,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final VpnServiceBase? vpnService;
  final String? parentIdOverride;

  @override
  State<CustomDomainsScreen> createState() => _CustomDomainsScreenState();
}

class _CustomDomainsScreenState extends State<CustomDomainsScreen> {
  final TextEditingController _domainController = TextEditingController();

  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;

  late final List<String> _initialDomains;
  late List<String> _blockedDomains;

  bool _isLoading = false;
  String? _inputError;

  static const List<String> _suggestions = [
    'youtube.com',
    'tiktok.com',
    'reddit.com',
    'discord.com',
    'instagram.com',
  ];

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

  bool get _hasChanges => !listEquals(_blockedDomains, _initialDomains);

  @override
  void initState() {
    super.initState();
    _initialDomains = _prepareDomains(widget.child.policy.blockedDomains);
    _blockedDomains = List<String>.from(_initialDomains);
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Domains'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveChanges,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'SAVE',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Block Specific Websites',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_blockedDomains.length} custom ${_blockedDomains.length == 1 ? 'domain' : 'domains'} blocked',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          _buildInputCard(context),
          const SizedBox(height: 16),
          _buildSuggestionsCard(context),
          const SizedBox(height: 16),
          _buildBlockedDomainsCard(context),
        ],
      ),
    );
  }

  Widget _buildInputCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Domain',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _domainController,
              onSubmitted: (_) => _addDomainFromInput(),
              decoration: InputDecoration(
                hintText: 'example.com',
                helperText: 'Enter domain only (no http/https)',
                errorText: _inputError,
                prefixIcon: const Icon(Icons.public),
                suffixIcon: IconButton(
                  onPressed: _isLoading ? null : _addDomainFromInput,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Add domain',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Add',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions.map((domain) {
                final alreadyAdded = _blockedDomains.contains(domain);
                return ActionChip(
                  label: Text(domain),
                  avatar: Icon(
                    alreadyAdded ? Icons.check_circle : Icons.add,
                    size: 16,
                  ),
                  onPressed:
                      _isLoading ? null : () => _addSuggestedDomain(domain),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedDomainsCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Blocked Domains',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            if (_blockedDomains.isEmpty)
              Text(
                'No custom domains blocked yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else
              ..._blockedDomains.map(
                (domain) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.block, color: Colors.purple),
                    title: Text(
                      domain,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    trailing: IconButton(
                      onPressed:
                          _isLoading ? null : () => _removeDomain(domain),
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _addDomainFromInput() {
    final normalized = _normalizeDomain(_domainController.text);
    if (normalized == null) {
      setState(() {
        _inputError = 'Enter a valid domain like example.com';
      });
      return;
    }
    _addDomain(normalized);
  }

  void _addSuggestedDomain(String domain) {
    final normalized = _normalizeDomain(domain);
    if (normalized == null) {
      return;
    }
    _addDomain(normalized);
  }

  void _addDomain(String domain) {
    if (_blockedDomains.contains(domain)) {
      setState(() {
        _inputError = 'Domain already added';
      });
      return;
    }

    setState(() {
      _blockedDomains = [..._blockedDomains, domain]..sort();
      _domainController.clear();
      _inputError = null;
    });
  }

  void _removeDomain(String domain) {
    setState(() {
      _blockedDomains =
          _blockedDomains.where((item) => item != domain).toList();
      _inputError = null;
    });
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final parentId =
          widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      final updatedPolicy = widget.child.policy.copyWith(
        blockedDomains: List<String>.from(_blockedDomains),
      );
      final updatedChild = widget.child.copyWith(policy: updatedPolicy);

      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );
      await _syncVpnRulesIfRunning(updatedPolicy);

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
        const SnackBar(
          content: Text('Custom domains updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(updatedChild);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Save Failed'),
            content: Text('Failed to update domains: $error'),
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

  Future<void> _syncVpnRulesIfRunning(Policy updatedPolicy) async {
    try {
      final status = await _resolvedVpnService.getStatus();
      if (!status.supported || !status.isRunning) {
        return;
      }

      await _resolvedVpnService.updateFilterRules(
        blockedCategories: updatedPolicy.blockedCategories,
        blockedDomains: updatedPolicy.blockedDomains,
      );
    } catch (_) {
      // Saving policy should succeed even if VPN sync is unavailable.
    }
  }

  List<String> _prepareDomains(List<String> domains) {
    final normalized = <String>{};
    for (final raw in domains) {
      final value = _normalizeDomain(raw);
      if (value != null) {
        normalized.add(value);
      }
    }
    final sorted = normalized.toList()..sort();
    return sorted;
  }

  String? _normalizeDomain(String input) {
    var value = input.trim().toLowerCase();
    if (value.isEmpty) {
      return null;
    }

    value = value.replaceFirst(RegExp(r'^[a-z]+://'), '');
    value = value.replaceFirst(RegExp(r'^www\.'), '');
    value = value.split('/').first.split('?').first.split('#').first;
    value = value.replaceAll(RegExp(r'^\.+|\.+$'), '');

    if (!_isValidDomain(value)) {
      return null;
    }
    return value;
  }

  bool _isValidDomain(String value) {
    final domainPattern = RegExp(
      r'^(?=.{1,253}$)(?!-)(?:[a-z0-9-]{1,63}\.)+[a-z]{2,63}$',
    );
    return domainPattern.hasMatch(value);
  }
}
