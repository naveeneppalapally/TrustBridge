import 'package:flutter/material.dart';

import '../services/pairing_service.dart';
import '../utils/child_friendly_errors.dart';

/// Child setup flow where a child enters a parent-generated pairing code.
class ChildSetupScreen extends StatefulWidget {
  const ChildSetupScreen({
    super.key,
    this.pairingService,
  });

  final PairingService? pairingService;

  @override
  State<ChildSetupScreen> createState() => _ChildSetupScreenState();
}

class _ChildSetupScreenState extends State<ChildSetupScreen> {
  PairingService? _pairingService;
  PairingService get _resolvedPairingService {
    _pairingService ??= widget.pairingService ?? PairingService();
    return _pairingService!;
  }

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      6,
      (_) => TextEditingController(),
    );
    _focusNodes = List<FocusNode>.generate(6, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((controller) => controller.text).join();

  bool get _canConnect =>
      !_isConnecting &&
      _controllers.every((controller) => controller.text.trim().length == 1);

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      final char = value.substring(value.length - 1);
      _controllers[index].text = char;
      _controllers[index].selection = TextSelection.fromPosition(
        TextPosition(offset: _controllers[index].text.length),
      );
    }

    setState(() {
      _errorMessage = null;
    });

    final normalized = _controllers[index].text.trim();
    if (normalized.isNotEmpty && index < _focusNodes.length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (normalized.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _connect() async {
    if (!_canConnect) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final deviceId = await _resolvedPairingService.getOrCreateDeviceId();
    final result = await _resolvedPairingService.validateAndPair(_code, deviceId);

    if (!mounted) {
      return;
    }

    if (result.success) {
      Navigator.of(context).pushReplacementNamed('/child/protection-permission');
      return;
    }

    setState(() {
      _isConnecting = false;
      _errorMessage = _friendlyErrorMessage(result.error);
      for (final controller in _controllers) {
        controller.clear();
      }
    });
    _focusNodes.first.requestFocus();
  }

  String _friendlyErrorMessage(PairingError? error) {
    switch (error) {
      case PairingError.invalidCode:
        return "That code didn't work. Ask your parent for the code again.";
      case PairingError.expiredCode:
        return 'That code has expired. Ask your parent to generate a new one.';
      case PairingError.alreadyUsed:
        return 'That code has already been used.';
      case PairingError.networkError:
      case null:
        return ChildFriendlyErrors.sanitise('network error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            const SizedBox(height: 28),
            const Icon(
              Icons.shield_outlined,
              size: 72,
              color: Color(0xFF1E88E5),
            ),
            const SizedBox(height: 20),
            Text(
              "Hi! Let's get you set up",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Ask your parent to open TrustBridge and show you the setup code.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List<Widget>.generate(6, (index) {
                return SizedBox(
                  width: 44,
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    enabled: !_isConnecting,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    decoration: const InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => _onDigitChanged(index, value),
                  ),
                );
              }),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _canConnect ? _connect : null,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
