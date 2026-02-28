import 'dart:async';

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
  bool _autoPromptedDeviceAdmin = false;

  static const Duration _vpnPermissionTimeout = Duration(seconds: 30);
  static const Duration _vpnStartTimeout = Duration(seconds: 20);
  static const Duration _deviceAdminTimeout = Duration(seconds: 30);
  static const Duration _backgroundOpTimeout = Duration(seconds: 8);

  Future<void> _requestProtectionPermission() async {
    if (_isRequesting) {
      return;
    }
    setState(() {
      _isRequesting = true;
    });

    try {
      final granted = await _vpnService
          .requestPermission()
          .timeout(_vpnPermissionTimeout, onTimeout: () => false);
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

      final started = await _vpnService
          .startVpn()
          .timeout(_vpnStartTimeout, onTimeout: () => false);
      if (!mounted) {
        return;
      }
      if (started) {
        setState(() {
          _step = _SetupStep.deviceAdmin;
          _isRequesting = false;
          _needsRetry = false;
        });
        unawaited(_autoPromptDeviceAdminIfNeeded());
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

    var granted = false;
    try {
      final requestFuture = _deviceAdminService
          .requestDeviceAdmin()
          .timeout(_deviceAdminTimeout, onTimeout: () async {
        // Some OEM flows do not return immediately via onActivityResult.
        return _deviceAdminService.isDeviceAdminActive();
      });
      final fallbackFuture =
          Future<bool>.delayed(const Duration(seconds: 10)).then(
        (_) => _deviceAdminService.isDeviceAdminActive(),
      );
      granted = await Future.any<bool>(<Future<bool>>[
        requestFuture,
        fallbackFuture,
      ]);
      if (!granted) {
        granted = await _deviceAdminService.isDeviceAdminActive();
      }
    } catch (_) {
      granted = await _deviceAdminService.isDeviceAdminActive();
    }

    await _finishSetup(deviceAdminActive: granted);
  }

  Future<void> _autoPromptDeviceAdminIfNeeded() async {
    if (_autoPromptedDeviceAdmin || _step != _SetupStep.deviceAdmin) {
      return;
    }
    _autoPromptedDeviceAdmin = true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      return;
    }
    await _requestDeviceAdminAndFinish();
  }

  Future<void> _continueWithoutDeviceAdmin() async {
    if (_isRequesting) {
      return;
    }
    setState(() {
      _isRequesting = true;
    });
    await _finishSetup(deviceAdminActive: false);
  }

  Future<void> _finishSetup({required bool deviceAdminActive}) async {
    try {
      await _saveDeviceAdminState(deviceAdminActive).timeout(_backgroundOpTimeout);
    } catch (error) {
      debugPrint('[ChildSetup] saveDeviceAdminState skipped: $error');
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context)
        .pushNamedAndRemoveUntil('/child/status', (route) => false);

    // Monitoring setup is best-effort and must not block child onboarding.
    unawaited(_startBypassMonitoringBestEffort());
  }

  Future<void> _startBypassMonitoringBestEffort() async {
    await _runBestEffort(
      label: 'bypass.startMonitoring',
      operation: _bypassDetectionService.startMonitoring,
    );
    await _runBestEffort(
      label: 'bypass.startPrivateDnsMonitoring',
      operation: _bypassDetectionService.startPrivateDnsMonitoring,
    );
    await _runBestEffort(
      label: 'heartbeat.initialize',
      operation: HeartbeatService.initialize,
    );
    await _runBestEffort(
      label: 'remote.initialize',
      operation: RemoteCommandService.initialize,
    );
    await _runBestEffort(
      label: 'heartbeat.sendHeartbeat',
      operation: HeartbeatService.sendHeartbeat,
    );
    await _runBestEffort(
      label: 'remote.processPendingCommands',
      operation: RemoteCommandService().processPendingCommands,
    );
  }

  Future<void> _runBestEffort({
    required String label,
    required Future<void> Function() operation,
  }) async {
    try {
      await operation().timeout(_backgroundOpTimeout);
    } catch (error) {
      debugPrint('[ChildSetup] $label skipped: $error');
    }
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
        ? 'Activate uninstall protection'
        : _needsRetry
            ? 'Protection needs this permission to work.'
            : 'Setting up protection for your phone';
    final subtitle = isDeviceAdminStep
        ? 'This prevents your child from uninstalling TrustBridge.'
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
                              ? 'Activate protection'
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
