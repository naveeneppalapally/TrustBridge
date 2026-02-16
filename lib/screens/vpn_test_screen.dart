import 'package:flutter/material.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class VpnTestScreen extends StatefulWidget {
  const VpnTestScreen({
    super.key,
    this.vpnService,
  });

  final VpnServiceBase? vpnService;

  @override
  State<VpnTestScreen> createState() => _VpnTestScreenState();
}

class _VpnTestScreenState extends State<VpnTestScreen> {
  late final VpnServiceBase _vpnService;

  bool _hasPermission = false;
  bool _isRunning = false;
  bool _isBusy = false;
  String _status = 'Not started';

  @override
  void initState() {
    super.initState();
    _vpnService = widget.vpnService ?? VpnService();
    _checkState();
  }

  Future<void> _checkState() async {
    final permission = await _vpnService.hasVpnPermission();
    final running = await _vpnService.isVpnRunning();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasPermission = permission;
      _isRunning = running;
      _status = permission
          ? (running ? 'VPN running' : 'Permission granted')
          : 'Permission needed';
    });
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isBusy = true;
      _status = 'Requesting permission...';
    });
    final granted = await _vpnService.requestPermission();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasPermission = granted;
      _isBusy = false;
      _status = granted ? 'Permission granted' : 'Permission denied';
    });
  }

  Future<void> _startVpn() async {
    setState(() {
      _isBusy = true;
      _status = 'Starting VPN...';
    });

    final success = await _vpnService.startVpn(
      blockedCategories: const ['social-networks', 'adult-content'],
      blockedDomains: const [
        'facebook.com',
        'instagram.com',
        'pornhub.com',
      ],
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _isRunning = success;
      _isBusy = false;
      _status = success ? 'VPN started' : 'Failed to start VPN';
    });
  }

  Future<void> _stopVpn() async {
    setState(() {
      _isBusy = true;
      _status = 'Stopping VPN...';
    });
    final success = await _vpnService.stopVpn();
    if (!mounted) {
      return;
    }
    setState(() {
      _isRunning = !success;
      _isBusy = false;
      _status = success ? 'VPN stopped' : 'Failed to stop VPN';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VPN Test (Dev)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'VPN Status',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isRunning ? Icons.check_circle : Icons.cancel,
                        color: _isRunning ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status,
                          key: const Key('vpn_test_status'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Permission: ${_hasPermission ? 'Granted' : 'Not granted'}',
                  ),
                  Text('VPN: ${_isRunning ? 'Running' : 'Stopped'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!_hasPermission)
            ElevatedButton(
              key: const Key('vpn_test_request_permission_button'),
              onPressed: _isBusy ? null : _requestPermission,
              child: const Text('Request VPN Permission'),
            ),
          if (_hasPermission && !_isRunning)
            ElevatedButton(
              key: const Key('vpn_test_start_button'),
              onPressed: _isBusy ? null : _startVpn,
              child: const Text('Start VPN'),
            ),
          if (_isRunning)
            ElevatedButton(
              key: const Key('vpn_test_stop_button'),
              onPressed: _isBusy ? null : _stopVpn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Stop VPN'),
            ),
          const SizedBox(height: 24),
          TextButton.icon(
            key: const Key('vpn_test_refresh_button'),
            onPressed: _isBusy ? null : _checkState,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Status'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Test Instructions:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('1. Request VPN permission'),
          const Text('2. Start VPN'),
          const Text('3. Try accessing facebook.com in browser'),
          const Text('4. Should be blocked'),
          const Text('5. Try accessing google.com'),
          const Text('6. Should work normally'),
        ],
      ),
    );
  }
}
