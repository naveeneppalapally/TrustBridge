import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class ChildDevicesScreen extends StatefulWidget {
  const ChildDevicesScreen({
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
  State<ChildDevicesScreen> createState() => _ChildDevicesScreenState();
}

class _ChildDevicesScreenState extends State<ChildDevicesScreen> {
  final TextEditingController _deviceIdController = TextEditingController();

  AuthService? _authService;
  FirestoreService? _firestoreService;

  late List<String> _deviceIds;
  bool _hasChanges = false;
  bool _isSaving = false;
  String? _inlineError;

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
    _deviceIds = List<String>.from(widget.child.deviceIds);
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.child.nickname}\'s Devices'),
        actions: [
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
        children: [
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
          _buildAddDeviceCard(context),
          const SizedBox(height: 16),
          _buildDeviceListCard(context),
          if (_inlineError != null) ...[
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
          children: [
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
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addDeviceId(),
              decoration: const InputDecoration(
                hintText: 'e.g. pixel-7-pro',
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
          children: [
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueGrey.shade100),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.smartphone),
                      title: Text(
                        deviceId,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: IconButton(
                        key: Key('remove_device_$deviceId'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove device',
                        onPressed:
                            _isSaving ? null : () => _removeDeviceId(deviceId),
                      ),
                    ),
                  ),
                ),
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

    setState(() {
      _deviceIds.insert(0, raw);
      _deviceIdController.clear();
      _hasChanges = true;
      _inlineError = null;
    });
  }

  void _removeDeviceId(String deviceId) {
    setState(() {
      _deviceIds.removeWhere((existing) => existing == deviceId);
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
      final updatedChild = widget.child.copyWith(deviceIds: _deviceIds);
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

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Failed'),
          content: Text(message),
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
