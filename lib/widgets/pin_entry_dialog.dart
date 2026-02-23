import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trustbridge_app/services/app_lock_service.dart';

Future<bool> showPinEntryDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => const _PinEntryDialog(),
  );
  return result ?? false;
}

class _PinEntryDialog extends StatefulWidget {
  const _PinEntryDialog();

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final AppLockService _appLockService = AppLockService();

  String _entered = '';
  String? _error;
  bool _isChecking = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricAvailability();
  }

  Future<void> _loadBiometricAvailability() async {
    final isAvailable = await _appLockService.isBiometricAvailable();
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricAvailable = isAvailable;
    });
  }

  void _onDigitPressed(String digit) {
    if (_isChecking ||
        _appLockService.isTemporarilyLocked ||
        _entered.length >= 4) {
      return;
    }

    setState(() {
      _entered += digit;
      _error = null;
    });

    if (_entered.length == 4) {
      _verifyPin();
    }
  }

  void _onBackspacePressed() {
    if (_isChecking || _appLockService.isTemporarilyLocked || _entered.isEmpty) {
      return;
    }
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
    });
  }

  Future<void> _verifyPin() async {
    if (_appLockService.isTemporarilyLocked) {
      final remaining = _appLockService.remainingLockDuration;
      final seconds = remaining == null ? 0 : remaining.inSeconds.clamp(1, 999);
      setState(() {
        _entered = '';
        _isChecking = false;
        _error = 'Too many attempts. Try again in ${seconds}s.';
      });
      return;
    }

    setState(() {
      _isChecking = true;
      _error = null;
    });

    final isValid = await _appLockService.verifyPin(_entered);
    if (!mounted) {
      return;
    }

    if (isValid) {
      Navigator.of(context).pop(true);
      return;
    }

    HapticFeedback.heavyImpact();
    final remaining = _appLockService.remainingLockDuration;
    final lockedNow = _appLockService.isTemporarilyLocked;
    final seconds = remaining == null ? 0 : remaining.inSeconds.clamp(1, 999);
    setState(() {
      _entered = '';
      _isChecking = false;
      _error = lockedNow
          ? 'Too many attempts. Try again in ${seconds}s.'
          : 'Incorrect PIN. Try again.';
    });
  }

  Future<void> _authenticateWithBiometric() async {
    final unlocked = await _appLockService.authenticateWithBiometric();
    if (!mounted) {
      return;
    }
    if (unlocked) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                'Parent PIN',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter your 4-digit PIN to continue',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(4, (int index) {
                  final isFilled = index < _entered.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutBack,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withValues(alpha: 0.32),
                    ),
                  );
                }),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              _PinNumpad(
                onDigitPressed: _onDigitPressed,
                onBackspacePressed: _onBackspacePressed,
                enabled: !_isChecking && !_appLockService.isTemporarilyLocked,
              ),
              if (_biometricAvailable) ...<Widget>[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _authenticateWithBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use fingerprint'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed:
                    _isChecking ? null : () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinNumpad extends StatelessWidget {
  const _PinNumpad({
    required this.onDigitPressed,
    required this.onBackspacePressed,
    required this.enabled,
  });

  final ValueChanged<String> onDigitPressed;
  final VoidCallback onBackspacePressed;
  final bool enabled;

  static const List<List<String>> _rows = <List<String>>[
    <String>['1', '2', '3'],
    <String>['4', '5', '6'],
    <String>['7', '8', '9'],
    <String>['', '0', 'backspace'],
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const keyMargin = 4.0;
        const keyMinWidth = 44.0;
        const keyMaxWidth = 72.0;
        const keyHeight = 56.0;

        final rawWidth = (constraints.maxWidth - (keyMargin * 2 * 3)) / 3;
        final keyWidth = rawWidth.clamp(keyMinWidth, keyMaxWidth).toDouble();
        final spacerWidth = keyWidth + (keyMargin * 2);

        return Column(
          children: _rows.map((List<String> row) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((String key) {
                if (key.isEmpty) {
                  return SizedBox(width: spacerWidth, height: keyHeight);
                }

                final isBackspace = key == 'backspace';
                return Padding(
                  padding: const EdgeInsets.all(keyMargin),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: !enabled
                        ? null
                        : () {
                      if (isBackspace) {
                        onBackspacePressed();
                      } else {
                        onDigitPressed(key);
                      }
                    },
                    child: Ink(
                      width: keyWidth,
                      height: keyHeight,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: isBackspace
                            ? const Icon(Icons.backspace_outlined)
                            : Text(
                                key,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        );
      },
    );
  }
}
