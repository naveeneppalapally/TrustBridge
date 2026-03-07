import 'dart:async';
import 'package:trustbridge_app/core/utils/app_logger.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/app_usage_service.dart';
import '../services/bypass_detection_service.dart';
import '../services/device_admin_service.dart';
import '../services/heartbeat_service.dart';
import '../services/pairing_service.dart';
import '../services/remote_command_service.dart';
import '../services/vpn_service.dart';

/// Post-pairing protection permission flow for child devices.
class ChildProtectionPermissionScreen extends StatefulWidget {
  const ChildProtectionPermissionScreen({
    super.key,
    VpnServiceBase? vpnService,
    AppUsageService? appUsageService,
    DeviceAdminService? deviceAdminService,
    PairingService? pairingService,
    BypassDetectionService? bypassDetectionService,
  })  : _vpnService = vpnService,
        _appUsageService = appUsageService,
        _deviceAdminService = deviceAdminService,
        _pairingService = pairingService,
        _bypassDetectionService = bypassDetectionService;

  final VpnServiceBase? _vpnService;
  final AppUsageService? _appUsageService;
  final DeviceAdminService? _deviceAdminService;
  final PairingService? _pairingService;
  final BypassDetectionService? _bypassDetectionService;

  @override
  State<ChildProtectionPermissionScreen> createState() =>
      _ChildProtectionPermissionScreenState();
}

class _ChildProtectionPermissionScreenState
    extends State<ChildProtectionPermissionScreen> with WidgetsBindingObserver {
  late final VpnServiceBase _vpnService;
  late final AppUsageService _appUsageService;
  late final DeviceAdminService _deviceAdminService;
  late final PairingService _pairingService;
  late final BypassDetectionService _bypassDetectionService;

  bool _isRequesting = false;
  bool _needsRetry = false;
  _SetupStep _step = _SetupStep.protectionPermission;
  bool _autoPromptedDeviceAdmin = false;

  static const Duration _vpnPermissionTimeout = Duration(seconds: 30);
  static const Duration _vpnStartTimeout = Duration(seconds: 20);
  static const Duration _deviceAdminTimeout = Duration(seconds: 30);
  static const Duration _backgroundOpTimeout = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    _vpnService = widget._vpnService ?? VpnService();
    _appUsageService = widget._appUsageService ?? AppUsageService();
    _deviceAdminService = widget._deviceAdminService ?? DeviceAdminService();
    _pairingService = widget._pairingService ?? PairingService();
    _bypassDetectionService =
        widget._bypassDetectionService ?? BypassDetectionService();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        _step != _SetupStep.usageAccess ||
        _isRequesting) {
      return;
    }
    unawaited(_refreshUsageAccessStateOnResume());
  }

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
        final usageAccessGranted =
            await _appUsageService.hasUsageAccessPermission();
        if (!mounted) {
          return;
        }
        if (usageAccessGranted) {
          _enterDeviceAdminStep();
          return;
        }
        setState(() {
          _step = _SetupStep.usageAccess;
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

  Future<void> _requestUsageAccessPermission() async {
    if (_isRequesting) {
      return;
    }
    setState(() {
      _isRequesting = true;
      _needsRetry = false;
    });

    try {
      final opened = await _appUsageService.openUsageAccessSettings();
      if (!mounted) {
        return;
      }
      if (!opened) {
        setState(() {
          _isRequesting = false;
          _needsRetry = true;
        });
        return;
      }

      final granted = await _appUsageService.hasUsageAccessPermission();
      if (!mounted) {
        return;
      }
      if (granted) {
        _enterDeviceAdminStep();
        return;
      }

      setState(() {
        _isRequesting = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRequesting = false;
        _needsRetry = true;
      });
    }
  }

  Future<void> _refreshUsageAccessStateOnResume() async {
    final granted = await _appUsageService.hasUsageAccessPermission();
    if (!mounted || _step != _SetupStep.usageAccess) {
      return;
    }
    if (granted) {
      _enterDeviceAdminStep();
      return;
    }
    setState(() {
      _needsRetry = true;
    });
  }

  void _enterDeviceAdminStep() {
    setState(() {
      _step = _SetupStep.deviceAdmin;
      _isRequesting = false;
      _needsRetry = false;
    });
    unawaited(_autoPromptDeviceAdminIfNeeded());
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
      await _saveDeviceAdminState(deviceAdminActive)
          .timeout(_backgroundOpTimeout);
    } catch (error) {
      AppLogger.debug('[ChildSetup] saveDeviceAdminState skipped: $error');
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
      AppLogger.debug('[ChildSetup] $label skipped: $error');
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
    final isUsageAccessStep = _step == _SetupStep.usageAccess;
    final title = isDeviceAdminStep
        ? 'Activate uninstall protection'
        : isUsageAccessStep
            ? _needsRetry
                ? 'App blocking needs one more permission.'
                : 'Allow app access for instant blocking'
            : _needsRetry
                ? 'Protection needs this permission to work.'
                : 'Setting up protection for your phone';
    final subtitle = isDeviceAdminStep
        ? 'This prevents your child from uninstalling TrustBridge.'
        : isUsageAccessStep
            ? _needsRetry
                ? 'Turn on Usage Access for TrustBridge, then return here.'
                : 'This lets TrustBridge detect blocked apps like WhatsApp and Instagram and close them right away.'
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
                          : isUsageAccessStep
                              ? _requestUsageAccessPermission
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
                              : isUsageAccessStep
                                  ? (_needsRetry
                                      ? 'Open settings again'
                                      : 'Allow app access')
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
  usageAccess,
  deviceAdmin,
}
