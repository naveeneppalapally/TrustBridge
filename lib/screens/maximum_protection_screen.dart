import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trustbridge_app/services/device_admin_service.dart';
import 'package:url_launcher/url_launcher.dart';

class MaximumProtectionScreen extends StatefulWidget {
  const MaximumProtectionScreen({super.key, this.deviceAdminService});

  final DeviceAdminService? deviceAdminService;

  @override
  State<MaximumProtectionScreen> createState() =>
      _MaximumProtectionScreenState();
}

class _MaximumProtectionScreenState extends State<MaximumProtectionScreen> {
  DeviceAdminService? _deviceAdminService;
  bool _loading = true;
  bool _applying = false;
  Map<String, dynamic> _status = const <String, dynamic>{};
  String _setupCommand = _defaultDeviceOwnerCommand;

  static const String _guideUrl =
      'https://github.com/naveeneppalapally/TrustBridge/blob/main/parental_controls_app/DEVICE_OWNER_SETUP.md';
  static const String _defaultDeviceOwnerCommand =
      'adb shell dpm set-device-owner '
      'com.navee.trustbridge/.TrustBridgeAdminReceiver';

  DeviceAdminService get _resolvedDeviceAdminService {
    _deviceAdminService ??= widget.deviceAdminService ?? DeviceAdminService();
    return _deviceAdminService!;
  }

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _loading = true;
    });
    final command =
        await _resolvedDeviceAdminService.getDeviceOwnerSetupCommand();
    final status =
        await _resolvedDeviceAdminService.getMaximumProtectionStatus();
    if (!mounted) {
      return;
    }
    setState(() {
      _setupCommand = command;
      _status = status;
      _loading = false;
    });
  }

  Future<void> _applyMaximumProtection() async {
    if (_applying) {
      return;
    }
    setState(() {
      _applying = true;
    });
    final result =
        await _resolvedDeviceAdminService.applyMaximumProtectionPolicies();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = result;
      _applying = false;
    });
    final message = (result['message'] as String?)?.trim();
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _copyCommand() async {
    await Clipboard.setData(ClipboardData(text: _setupCommand));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Command copied. Paste it in your laptop terminal.')),
    );
  }

  Future<void> _openGuide() async {
    final uri = Uri.parse(_guideUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) {
      return;
    }
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open guide link.')),
      );
    }
  }

  Future<void> _showSetupDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set up Maximum Protection',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'On a laptop with ADB installed, connect the child phone by USB and run this command once:',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    _setupCommand,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _copyCommand,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Command'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openGuide,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Setup Guide'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _vpnRunning => _status['vpnRunning'] == true;
  bool get _deviceAdminActive => _status['deviceAdminActive'] == true;
  bool get _deviceOwnerActive => _status['deviceOwnerActive'] == true;
  bool get _alwaysOnVpnEnabled => _status['alwaysOnVpnEnabled'] == true;
  bool get _lockdownEnabled => _status['lockdownEnabled'] == true;
  bool get _uninstallBlocked => _status['uninstallBlocked'] == true;
  bool get _appsControlRestricted => _status['appsControlRestricted'] == true;

  bool get _tierThreeFullyActive =>
      _deviceOwnerActive &&
      _alwaysOnVpnEnabled &&
      _lockdownEnabled &&
      _uninstallBlocked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maximum Protection')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshStatus,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    'Choose the protection level for this child device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  _buildTierCard(
                    title: 'Tier 1 - Basic',
                    subtitle:
                        'VPN running and protection stays on through normal app switching.',
                    active: _vpnRunning,
                    activeLabel: 'Active now',
                    inactiveLabel: 'Not active',
                  ),
                  const SizedBox(height: 12),
                  _buildTierCard(
                    title: 'Tier 2 - Device Admin',
                    subtitle:
                        'TrustBridge cannot be removed without parent approval.',
                    active: _deviceAdminActive,
                    activeLabel: 'Active now',
                    inactiveLabel: 'Not active',
                  ),
                  const SizedBox(height: 12),
                  _buildTierCard(
                    title: 'Tier 3 - Maximum',
                    subtitle:
                        'Force-stop hardening, always-on lockdown, and uninstall block via one-time laptop setup.',
                    active: _tierThreeFullyActive,
                    activeLabel: 'Active now',
                    inactiveLabel: _deviceOwnerActive
                        ? 'Partially active'
                        : 'Setup required',
                    extra: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        _buildSmallStatusRow(
                            'Device Owner', _deviceOwnerActive),
                        _buildSmallStatusRow(
                            'Always-on protection', _alwaysOnVpnEnabled),
                        _buildSmallStatusRow('Lockdown mode', _lockdownEnabled),
                        _buildSmallStatusRow(
                            'Uninstall blocked', _uninstallBlocked),
                        _buildSmallStatusRow(
                            'App controls restricted', _appsControlRestricted),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton(
                              key: const Key('maximum_protection_setup_button'),
                              onPressed: _showSetupDialog,
                              child: const Text('Set up Maximum Protection'),
                            ),
                            if (_deviceOwnerActive)
                              OutlinedButton(
                                key: const Key(
                                    'maximum_protection_apply_button'),
                                onPressed:
                                    _applying ? null : _applyMaximumProtection,
                                child: _applying
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Apply Now'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Without Tier 3, protection still works for normal use. Tier 3 is for advanced tamper resistance.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTierCard({
    required String title,
    required String subtitle,
    required bool active,
    required String activeLabel,
    required String inactiveLabel,
    Widget? extra,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = active ? Colors.green : colorScheme.onSurfaceVariant;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.green.withValues(alpha: 0.18)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    active ? activeLabel : inactiveLabel,
                    style: TextStyle(
                      color: activeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle),
            if (extra != null) extra,
          ],
        ),
      ),
    );
  }

  Widget _buildSmallStatusRow(String label, bool active) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: active
                ? Colors.green
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
