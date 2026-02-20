import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/bypass_detection_service.dart';
import '../services/device_admin_service.dart';
import '../services/heartbeat_service.dart';
import '../services/pairing_service.dart';
import '../services/remote_command_service.dart';
import '../services/vpn_service.dart';

/// Post-pairing protection permission flow for child devices.
class ChildProtectionPermissionScreen extends StatefulWidget {
  const ChildProtectionPermissionScreen({super.key});

  @override
  State<ChildProtectionPermissionScreen> createState() =>
      _ChildProtectionPermissionScreenState();
}

class _ChildProtectionPermissionScreenState
    extends State<ChildProtectionPermissionScreen> {
  final VpnService _vpnService = VpnService();
  final DeviceAdminService _deviceAdminService = DeviceAdminService();
  final PairingService _pairingService = PairingService();
  final BypassDetectionService _bypassDetectionService =
      BypassDetectionService();

  bool _isRequesting = false;
  bool _needsRetry = false;
  _SetupStep _step = _SetupStep.protectionPermission;

  Future<void> _requestProtectionPermission() async {
    if (_isRequesting) {
      return;
    }
    setState(() {
      _isRequesting = true;
    });

    try {
      final granted = await _vpnService.requestPermission();
      if (!granted) {
        if (!mounted) {
          return;
        }
        setState(() {
          _needsRetry = true;
          _isRequesting = false;
        });
        return;
      }

      final started = await _vpnService.startVpn();
      if (!mounted) {
        return;
      }
      if (started) {
        setState(() {
          _step = _SetupStep.deviceAdmin;
          _isRequesting = false;
          _needsRetry = false;
        });
        return;
      }

      setState(() {
        _needsRetry = true;
        _isRequesting = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _needsRetry = true;
        _isRequesting = false;
      });
    }
  }

  Future<void> _requestDeviceAdminAndFinish() async {
    if (_isRequesting) {
      return;
    }
    setState(() {
      _isRequesting = true;
    });

    final granted = await _deviceAdminService.requestDeviceAdmin();
    await _saveDeviceAdminState(granted);
    await _startBypassMonitoring();
    if (!mounted) {
      return;
    }
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/child/status', (route) => false);
  }

  Future<void> _continueWithoutDeviceAdmin() async {
    await _saveDeviceAdminState(false);
    await _startBypassMonitoring();
    if (!mounted) {
      return;
    }
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/child/status', (route) => false);
  }

  Future<void> _startBypassMonitoring() async {
    await _bypassDetectionService.startMonitoring();
    await _bypassDetectionService.startPrivateDnsMonitoring();
    await HeartbeatService.initialize();
    await RemoteCommandService.initialize();
    await HeartbeatService.sendHeartbeat();
    await RemoteCommandService().processPendingCommands();
  }

  Future<void> _saveDeviceAdminState(bool active) async {
    final childId = await _pairingService.getPairedChildId();
    final parentId = await _pairingService.getPairedParentId();
    final deviceId = await _pairingService.getOrCreateDeviceId();
    if (childId == null || childId.isEmpty) {
      return;
    }

    await FirebaseFirestore.instance
        .collection('children')
        .doc(childId)
        .collection('devices')
        .doc(deviceId)
        .set(
      <String, dynamic>{
        'parentId': parentId,
        'deviceAdminActive': active,
        'deviceAdminUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (!active && parentId != null && parentId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('notification_queue').add({
        'parentId': parentId,
        'title': 'Device Admin not active',
        'body': 'Protection on your child device can be removed easily.',
        'route': '/parent/bypass-alerts',
        'processed': false,
        'sentAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDeviceAdminStep = _step == _SetupStep.deviceAdmin;
    final title = isDeviceAdminStep
        ? 'One more step'
        : _needsRetry
            ? 'Protection needs this permission to work.'
            : 'Setting up protection for your phone';
    final subtitle = isDeviceAdminStep
        ? 'To keep protection working, TrustBridge needs one more permission.'
        : _needsRetry
            ? "Ask your parent if you're not sure."
            : 'We need one permission to keep you safe online.';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(
                Icons.shield_outlined,
                size: 72,
                color: Color(0xFF1E88E5),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isRequesting
                      ? null
                      : isDeviceAdminStep
                          ? _requestDeviceAdminAndFinish
                          : _requestProtectionPermission,
                  child: _isRequesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isDeviceAdminStep
                              ? 'Continue'
                              : (_needsRetry ? 'Try again' : 'Continue'),
                        ),
                ),
              ),
              if (isDeviceAdminStep) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _isRequesting ? null : _continueWithoutDeviceAdmin,
                  child: const Text('Ask my parent first'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _SetupStep {
  protectionPermission,
  deviceAdmin,
}
