import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_mode_service.dart';
import '../services/heartbeat_service.dart';
import '../services/pairing_service.dart';

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
  bool _isReady = false;
  String? _errorMessage;
  String? _lastAuthErrorCode;

  Future<void> _goBackToRolePicker() async {
    await AppModeService().clearMode();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
  }

  Future<void> _openParentSignIn() async {
    if (_isConnecting) {
      return;
    }
    await Navigator.of(context).pushNamed(
      '/parent/login',
      arguments: const <String, dynamic>{
        'redirectAfterLogin': '/child/setup',
        'targetMode': 'child',
      },
    );
    if (!mounted) {
      return;
    }
    await _ensureAuthenticatedSession();
  }

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      6,
      (_) => TextEditingController(),
    );
    _focusNodes = List<FocusNode>.generate(6, (_) => FocusNode());
    _ensureAuthenticatedSession();
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

  Future<void> _ensureAuthenticatedSession() async {
    setState(() {
      _isReady = false;
      _errorMessage = null;
      _lastAuthErrorCode = null;
    });

    try {
      var currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        try {
          final credential = await FirebaseAuth.instance.signInAnonymously();
          currentUser = credential.user;
        } on FirebaseAuthException catch (error) {
          if (!mounted) {
            return;
          }
          final code = error.code.trim().toLowerCase();
          setState(() {
            _isReady = false;
            _lastAuthErrorCode = code;
            _errorMessage = _friendlyAuthInitError(code);
          });
          return;
        } catch (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isReady = false;
            _lastAuthErrorCode = 'auth-init-failed';
            _errorMessage =
                'Could not start secure child setup. Check internet and retry.';
          });
          return;
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isReady = true;
        _lastAuthErrorCode = null;
        _errorMessage = null;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      final code = error.code.trim().toLowerCase();
      setState(() {
        _isReady = false;
        _lastAuthErrorCode = code;
        _errorMessage = _friendlyAuthInitError(code);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isReady = false;
        _lastAuthErrorCode = null;
        _errorMessage = 'Could not connect. Check internet and try again.';
      });
    }
  }

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
    if (!_isReady || !_canConnect) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    PairingResult result;
    try {
      final deviceId = await _resolvedPairingService.getOrCreateDeviceId();
      result = await _resolvedPairingService.validateAndPair(_code, deviceId);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Could not verify this code right now. Try again.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    if (result.success) {
      // Fire an immediate heartbeat so the parent dashboard shows the child
      // device as online right away, rather than waiting for the next
      // periodic WorkManager heartbeat (10-15 min).
      try {
        await HeartbeatService.sendHeartbeat();
      } catch (_) {
        // Non-fatal; the periodic task will send the heartbeat later.
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context)
          .pushReplacementNamed('/child/protection-permission');
      return;
    }

    await _resolvedPairingService.clearLocalPairing();

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
      case PairingError.permissionDenied:
        return 'Setup permission is blocked. Ask your parent to check app setup.';
      case PairingError.networkError:
      case null:
        return 'Could not verify this code right now. Try again.';
    }
  }

  String _friendlyAuthInitError(String code) {
    switch (code) {
      case 'missing-parent-session':
        return 'Sign in with the parent account on this device before child setup.';
      case 'network-request-failed':
        return 'Could not connect. Check internet and try again.';
      case 'app-not-authorized':
      case 'invalid-api-key':
      case 'api-key-not-valid':
        return 'This app build is not authorized for Firebase. Ask your parent to update app setup (SHA/API key).';
      case 'too-many-requests':
        return 'Too many attempts. Wait a minute and try again.';
      default:
        return 'Setup needs your parent\'s help right now.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: _isConnecting ? null : _goBackToRolePicker,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
            ),
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
            if (!_isReady && _errorMessage == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List<Widget>.generate(6, (index) {
                  return SizedBox(
                    width: 44,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      enabled: !_isConnecting && _isReady,
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
              if (kDebugMode && _lastAuthErrorCode != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Auth code: $_lastAuthErrorCode',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade300,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
              if (!_isReady) ...[
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    TextButton(
                      onPressed:
                          _isConnecting ? null : _ensureAuthenticatedSession,
                      child: const Text('Retry'),
                    ),
                    if (_lastAuthErrorCode == 'missing-parent-session')
                      FilledButton.tonalIcon(
                        onPressed: _isConnecting ? null : _openParentSignIn,
                        icon: const Icon(Icons.login),
                        label: const Text('Sign In Parent Account'),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: (_isReady && _canConnect) ? _connect : null,
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
