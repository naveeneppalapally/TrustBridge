import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/child_profile.dart';
import '../services/pairing_service.dart';

/// Parent-side device pairing screen that generates setup codes.
class AddChildDeviceScreen extends StatefulWidget {
  const AddChildDeviceScreen({
    super.key,
    required this.child,
    this.pairingService,
  });

  final ChildProfile child;
  final PairingService? pairingService;

  @override
  State<AddChildDeviceScreen> createState() => _AddChildDeviceScreenState();
}

class _AddChildDeviceScreenState extends State<AddChildDeviceScreen> {
  PairingService? _pairingService;
  PairingService get _resolvedPairingService {
    _pairingService ??= widget.pairingService ?? PairingService();
    return _pairingService!;
  }

  String? _code;
  DateTime? _expiresAt;
  Timer? _timer;
  StreamSubscription<bool>? _codeUsedSubscription;
  bool _loading = true;
  bool _generating = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_generateCode());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeUsedSubscription?.cancel();
    super.dispose();
  }

  bool get _isExpired {
    final expiresAt = _expiresAt;
    if (expiresAt == null) {
      return true;
    }
    return !expiresAt.isAfter(DateTime.now());
  }

  Future<void> _generateCode() async {
    if (_generating) {
      return;
    }
    setState(() {
      _generating = true;
      _loading = true;
      _error = null;
    });

    try {
      final code = await _resolvedPairingService.generatePairingCode(
        widget.child.id,
      );
      final expiresAt = DateTime.now().add(const Duration(minutes: 15));

      await _codeUsedSubscription?.cancel();
      _codeUsedSubscription =
          _resolvedPairingService.watchCodeUsed(code).listen(
        (used) {
          if (!used || _connected || !mounted) {
            return;
          }
          _connected = true;
          _showConnectedDialog();
        },
      );

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        if (_isExpired) {
          setState(() {});
          return;
        }
        setState(() {});
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _code = code;
        _expiresAt = expiresAt;
        _loading = false;
        _generating = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _generating = false;
        _error = _friendlyGenerateError(error);
      });
    }
  }

  String _friendlyGenerateError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Pairing code is unavailable right now. Please try again in a moment.';
        case 'unavailable':
          return 'Network unavailable. Please check internet and try again.';
        default:
          final message = error.message?.trim();
          if (message != null && message.isNotEmpty) {
            return message;
          }
      }
    }

    if (error is StateError) {
      final message = error.message.toString().toLowerCase();
      if (message.contains('signed in')) {
        return 'Please sign in again, then try generating a code.';
      }
      if (message.contains('own child profiles')) {
        return 'This child profile is not linked to your account.';
      }
      return 'Could not generate code. Please try again.';
    }

    return 'Could not generate code. Please try again.';
  }

  Future<void> _showConnectedDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Device connected'),
        content: Text(
          '${widget.child.nickname}\'s phone is now linked successfully.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  String _countdownLabel() {
    final expiresAt = _expiresAt;
    if (expiresAt == null) {
      return '--:--';
    }
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.inSeconds <= 0) {
      return '00:00';
    }
    final minutes =
        remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _spacedCode(String code) {
    return code.split('').join('  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Device'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(
                  "Set up ${widget.child.nickname}'s phone",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ask your child to open TrustBridge, tap "I\'m a Child", and enter this code.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.30),
                    ),
                    color: theme.cardColor,
                  ),
                  child: Center(
                    child: Text(
                      _code == null ? '------' : _spacedCode(_code!),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Opacity(
                  opacity: _isExpired ? 0.35 : 1,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.25),
                        ),
                      ),
                      child: QrImageView(
                        data: _code ?? '',
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_code == null)
                  Text(
                    'No active code. Generate a new one.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (_isExpired)
                  Text(
                    'Code expired. Generate a new one.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    'Code expires in ${_countdownLabel()}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _generating ? null : _generateCode,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                      _isExpired ? 'Generate new code' : 'Generate new code'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Instructions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const _InstructionStep(
                  number: '1',
                  text: 'Download TrustBridge on the child phone.',
                ),
                const _InstructionStep(
                  number: '2',
                  text: 'Open it and tap "I\'m a Child".',
                ),
                const _InstructionStep(
                  number: '3',
                  text: 'Enter the 6-digit code shown here.',
                ),
              ],
            ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({
    required this.number,
    required this.text,
  });

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.15),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E88E5),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
