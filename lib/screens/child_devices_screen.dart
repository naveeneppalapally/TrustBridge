import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:trustbridge_app/models/child_device_record.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class ChildDevicesScreen extends StatefulWidget {
  const ChildDevicesScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.vpnService,
    this.httpClient,
    this.parentIdOverride,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final VpnServiceBase? vpnService;
  final http.Client? httpClient;
  final String? parentIdOverride;

  @override
  State<ChildDevicesScreen> createState() => _ChildDevicesScreenState();
}

class _ChildDevicesScreenState extends State<ChildDevicesScreen> {
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _aliasController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();

  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;
  http.Client? _httpClient;
  bool _ownsHttpClient = false;

  late List<String> _deviceIds;
  late Map<String, ChildDeviceRecord> _deviceMetadata;
  bool _hasChanges = false;
  bool _isSaving = false;
  bool _isVerifyingDns = false;
  String? _inlineError;
  String? _verificationMessage;

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

  http.Client get _resolvedHttpClient {
    if (_httpClient != null) {
      return _httpClient!;
    }
    if (widget.httpClient != null) {
      _httpClient = widget.httpClient;
      _ownsHttpClient = false;
      return _httpClient!;
    }
    _httpClient = http.Client();
    _ownsHttpClient = true;
    return _httpClient!;
  }

  String? get _parentId {
    return widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
  }

  String? get _nextDnsHostname {
    final profileId = widget.child.nextDnsProfileId?.trim();
    if (profileId == null || profileId.isEmpty) {
      return null;
    }
    return '$profileId.dns.nextdns.io';
  }

  @override
  void initState() {
    super.initState();
    _deviceIds = List<String>.from(widget.child.deviceIds);
    _deviceMetadata = Map<String, ChildDeviceRecord>.from(
      widget.child.deviceMetadata,
    );
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _aliasController.dispose();
    _modelController.dispose();
    if (_ownsHttpClient) {
      _httpClient?.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.child.nickname}\'s Devices'),
        actions: <Widget>[
          if (_hasChanges)
            TextButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
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
        children: <Widget>[
          Text(
            'Manage Devices',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_deviceIds.length} ${_deviceIds.length == 1 ? 'device' : 'devices'} linked to ${widget.child.nickname}.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          _buildHostnameCard(context),
          const SizedBox(height: 12),
          _buildAddDeviceCard(context),
          const SizedBox(height: 16),
          _buildDeviceListCard(context),
          if (_inlineError != null) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              _inlineError!,
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

  Widget _buildHostnameCard(BuildContext context) {
    final hostname = _nextDnsHostname;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Device Setup Wizard',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              hostname == null
                  ? 'Link NextDNS profile first to show child hostname.'
                  : 'Use this hostname on child device DNS settings.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            if (hostname != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.shade100),
                ),
                child: Text(
                  hostname,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: QrImageView(
                    key: const Key('child_device_setup_qr'),
                    data: hostname,
                    size: 180,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('device_hostname_copy_button'),
                    onPressed: () => _copyHostname(hostname),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Hostname'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('device_hostname_share_button'),
                    onPressed: () => _shareHostname(hostname),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share Setup'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('open_private_dns_settings_button'),
                    onPressed: _openPrivateDnsSettings,
                    icon: const Icon(Icons.settings_ethernet, size: 16),
                    label: const Text('Open Private DNS Settings'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSetupStep(
                number: 1,
                title: 'Name the Device',
                body:
                    'Give it a nickname, choose child, then add phone/tablet model.',
              ),
              const SizedBox(height: 8),
              _buildSetupStep(
                number: 2,
                title: 'Scan QR Code',
                body:
                    'Open Settings > Network & Internet > Private DNS on child device and scan/copy hostname.',
              ),
              const SizedBox(height: 8),
              _buildSetupStep(
                number: 3,
                title: 'Paste Hostname',
                body:
                    'Set Private DNS to Custom hostname and paste $hostname, then tap Save.',
              ),
              const SizedBox(height: 8),
              _buildSetupStep(
                number: 4,
                title: 'Verify & Done',
                body:
                    'Run live verification to confirm this device is routed through NextDNS.',
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('verify_nextdns_button'),
                onPressed: _isVerifyingDns ? null : _verifyNextDnsRouting,
                icon: _isVerifyingDns
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_outlined),
                label: Text(
                  _isVerifyingDns ? 'Checking...' : 'Check if it\'s working',
                ),
              ),
              if (_verificationMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _verificationMessage!,
                  key: const Key('child_device_verify_message'),
                  style: TextStyle(
                    color: _verificationMessage!.startsWith('✅')
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddDeviceCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Add Device ID',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('device_id_input'),
              controller: _deviceIdController,
              enabled: !_isSaving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'e.g. pixel-7-pro',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _aliasController,
              enabled: !_isSaving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Friendly name (e.g. Aarav Pixel)',
                labelText: 'Alias (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelController,
              enabled: !_isSaving,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addDeviceId(),
              decoration: const InputDecoration(
                hintText: 'Device model (optional)',
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('add_device_id_button'),
                onPressed: _isSaving ? null : _addDeviceId,
                icon: const Icon(Icons.add),
                label: const Text('Add Device'),
              ),
            ),
            if (_inlineError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _inlineError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceListCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Linked Devices',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            if (_deviceIds.isEmpty)
              Text(
                'No devices linked yet. Add one to start managing this child device.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              )
            else
              ..._deviceIds.map(
                (deviceId) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildDeviceRow(context, deviceId),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceRow(BuildContext context, String deviceId) {
    final metadata = _deviceMetadata[deviceId];
    final verified = metadata?.isVerified == true;
    final alias = metadata?.alias.trim();
    final model = metadata?.model?.trim();
    final subtitle = <String>[
      if (alias != null && alias.isNotEmpty && alias != deviceId) alias,
      if (model != null && model.isNotEmpty) model,
      verified ? 'Verified' : 'Pending verification',
    ].join(' • ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          verified ? Icons.verified : Icons.smartphone,
          color: verified ? Colors.green : null,
        ),
        title: Text(
          deviceId,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        subtitle: Text(subtitle),
        trailing: Wrap(
          spacing: 2,
          children: <Widget>[
            if (!verified)
              IconButton(
                key: Key('verify_device_$deviceId'),
                tooltip: 'Mark verified',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: _isSaving ? null : () => _verifyDevice(deviceId),
              ),
            IconButton(
              key: Key('remove_device_$deviceId'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove device',
              onPressed: _isSaving ? null : () => _removeDeviceId(deviceId),
            ),
          ],
        ),
      ),
    );
  }

  void _addDeviceId() {
    final raw = _deviceIdController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _inlineError = 'Device ID cannot be empty.';
      });
      return;
    }
    if (raw.length > 64) {
      setState(() {
        _inlineError = 'Device ID must be 64 characters or less.';
      });
      return;
    }

    final exists = _deviceIds.any(
      (existing) => existing.toLowerCase() == raw.toLowerCase(),
    );
    if (exists) {
      setState(() {
        _inlineError = 'This device ID is already linked.';
      });
      return;
    }

    final alias = _aliasController.text.trim();
    final model = _modelController.text.trim();
    final now = DateTime.now();
    final metadata = ChildDeviceRecord(
      deviceId: raw,
      alias: alias.isEmpty ? raw : alias,
      model: model.isEmpty ? null : model,
      linkedNextDnsProfileId: widget.child.nextDnsProfileId,
      isVerified: false,
      createdAt: now,
      lastSeenAt: null,
    );

    setState(() {
      _deviceIds.insert(0, raw);
      _deviceMetadata[raw] = metadata;
      _deviceIdController.clear();
      _aliasController.clear();
      _modelController.clear();
      _hasChanges = true;
      _inlineError = null;
    });
  }

  void _verifyDevice(String deviceId) {
    final existing = _deviceMetadata[deviceId];
    if (existing == null) {
      return;
    }
    setState(() {
      _deviceMetadata[deviceId] = existing.copyWith(
        isVerified: true,
        lastSeenAt: DateTime.now(),
      );
      _hasChanges = true;
      _inlineError = null;
    });
  }

  void _removeDeviceId(String deviceId) {
    setState(() {
      _deviceIds.removeWhere((existing) => existing == deviceId);
      _deviceMetadata.remove(deviceId);
      _hasChanges = true;
      _inlineError = null;
    });
  }

  Future<void> _saveChanges() async {
    if (_isSaving || !_hasChanges) {
      return;
    }

    final parentId = _parentId;
    if (parentId == null) {
      _showErrorDialog('Not logged in');
      return;
    }

    setState(() {
      _isSaving = true;
      _inlineError = null;
    });

    try {
      final updatedChild = widget.child.copyWith(
        deviceIds: _deviceIds,
        deviceMetadata: _deviceMetadata,
      );
      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devices updated successfully'),
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
      _showErrorDialog('Unable to save device changes: $error');
    }
  }

  Future<void> _copyHostname(String hostname) async {
    await Clipboard.setData(ClipboardData(text: hostname));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hostname copied')),
    );
  }

  Future<void> _shareHostname(String hostname) async {
    await Share.share(
      'TrustBridge device setup\n'
      'DNS Hostname: $hostname\n'
      'Child: ${widget.child.nickname}\n'
      'Steps:\n'
      '1) Open Settings > Network & Internet\n'
      '2) Private DNS > Custom hostname\n'
      '3) Paste hostname and Save',
      subject: 'TrustBridge Device Setup',
    );
  }

  Widget _buildSetupStep({
    required int number,
    required String title,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF2563EB),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openPrivateDnsSettings() async {
    final opened = await _resolvedVpnService.openPrivateDnsSettings();
    if (!mounted) {
      return;
    }
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Private DNS settings.')),
      );
    }
  }

  Future<void> _verifyNextDnsRouting() async {
    final profileId = widget.child.nextDnsProfileId?.trim();
    if (profileId == null || profileId.isEmpty) {
      setState(() {
        _verificationMessage = '❌ NextDNS profile is not linked yet.';
      });
      return;
    }

    setState(() {
      _isVerifyingDns = true;
      _verificationMessage = null;
    });

    try {
      final response = await _resolvedHttpClient.get(
        Uri.parse('https://test.nextdns.io'),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) {
          return;
        }
        setState(() {
          _verificationMessage =
              '❌ Verification failed (status ${response.statusCode}).';
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      String detectedProfile = '';
      if (decoded is Map) {
        final map = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        detectedProfile = (map['profile'] as String? ?? '').trim();
        if (detectedProfile.isEmpty) {
          detectedProfile = (map['id'] as String? ?? '').trim();
        }
      }

      if (!mounted) {
        return;
      }

      if (detectedProfile.toLowerCase() == profileId.toLowerCase()) {
        setState(() {
          _verificationMessage = '✅ Protected — NextDNS profile is active.';
        });
      } else {
        setState(() {
          _verificationMessage =
              '❌ Not yet protected. Detected profile: ${detectedProfile.isEmpty ? 'unknown' : detectedProfile}';
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _verificationMessage = '❌ Verification failed. Check internet and retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingDns = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Failed'),
          content: Text(message),
          actions: <Widget>[
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
