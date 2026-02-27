import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/child_profile.dart';
import '../services/firestore_service.dart';
import '../services/onboarding_state_service.dart';
import '../services/pairing_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.parentId,
    this.isRevisit = false,
    this.firestoreService,
    this.onboardingStateService,
    this.onCompleteOnboarding,
  });

  final String parentId;
  final bool isRevisit;
  final FirestoreService? firestoreService;
  final OnboardingStateService? onboardingStateService;
  final Future<void> Function(String parentId)? onCompleteOnboarding;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _childNameController = TextEditingController();

  bool _isSubmitting = false;
  bool _consentAccepted = false;
  AgeBand _selectedAgeBand = AgeBand.middle;
  ChildProfile? _createdChild;
  String? _pairingCode;
  DateTime? _pairingCodeExpiresAt;
  String? _errorMessage;
  Timer? _pairingTimer;

  bool get _requiresConsent => !widget.isRevisit && !kDebugMode;

  FirestoreService get _resolvedFirestoreService {
    return widget.firestoreService ?? FirestoreService();
  }

  OnboardingStateService get _resolvedOnboardingStateService {
    return widget.onboardingStateService ?? OnboardingStateService();
  }

  PairingService get _pairingService => PairingService();

  Future<void> _completeOnboardingForParent() async {
    final override = widget.onCompleteOnboarding;
    if (override != null) {
      await override(widget.parentId);
      return;
    }
    await _resolvedFirestoreService.completeOnboarding(widget.parentId);
  }

  @override
  void initState() {
    super.initState();
    _consentAccepted = widget.isRevisit;
    unawaited(_loadConsentState());
  }

  @override
  void dispose() {
    _pairingTimer?.cancel();
    _childNameController.dispose();
    super.dispose();
  }

  Future<void> _loadConsentState() async {
    if (widget.isRevisit) {
      return;
    }
    try {
      final profile =
          await _resolvedFirestoreService.getParentProfile(widget.parentId);
      if (!mounted) {
        return;
      }
      setState(() {
        _consentAccepted = profile?['consentGiven'] == true;
      });
    } catch (_) {
      // Best effort.
    }
  }

  String _countdownLabel() {
    final expiresAt = _pairingCodeExpiresAt;
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

  bool get _isPairingCodeExpired {
    final expiresAt = _pairingCodeExpiresAt;
    if (expiresAt == null) {
      return true;
    }
    return !expiresAt.isAfter(DateTime.now());
  }

  String _spacedCode(String code) => code.split('').join('  ');

  Future<void> _submitSingleStepOnboarding() async {
    if (_isSubmitting) {
      return;
    }

    final childName = _childNameController.text.trim();
    if (childName.length < 2) {
      setState(() {
        _errorMessage = 'Please enter your child\'s name.';
      });
      return;
    }
    if (_requiresConsent && !_consentAccepted) {
      _showConsentRequired();
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final child = await _resolvedFirestoreService.addChild(
        parentId: widget.parentId,
        nickname: childName,
        ageBand: _selectedAgeBand,
      );
      final pairingCode = await _pairingService.generatePairingCode(child.id);

      try {
        await _resolvedOnboardingStateService
            .markCompleteLocally(widget.parentId);
      } catch (_) {
        // Local flag best-effort.
      }

      unawaited(() async {
        try {
          await _resolvedFirestoreService
              .recordGuardianConsent(widget.parentId);
        } catch (_) {
          // Cloud consent sync is best effort.
        }
        try {
          await _completeOnboardingForParent();
        } catch (_) {
          // Cloud completion sync is best effort.
        }
      }());

      _pairingTimer?.cancel();
      _pairingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _createdChild = child;
        _pairingCode = pairingCode;
        _pairingCodeExpiresAt = DateTime.now().add(const Duration(minutes: 15));
        _isSubmitting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Could not finish setup. Please try again. ($error)';
      });
    }
  }

  void _openHome() {
    if (widget.isRevisit) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacementNamed('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Setup'),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _openHome,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            'Set up in one step',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter child name, pick age, and get a pairing code immediately.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (_requiresConsent) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: _consentAccepted,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I am the parent or legal guardian and I consent to child device data processing for parental controls.',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _consentAccepted = value ?? false;
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _openExternalUrl(
                          context,
                          'https://trustbridge.app/privacy',
                        ),
                        child: const Text('Privacy Policy'),
                      ),
                      TextButton(
                        onPressed: () => _openExternalUrl(
                          context,
                          'https://trustbridge.app/terms',
                        ),
                        child: const Text('Terms'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _childNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Child name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Age group',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('6-9 years'),
                selected: _selectedAgeBand == AgeBand.young,
                onSelected: _isSubmitting
                    ? null
                    : (_) => setState(() {
                          _selectedAgeBand = AgeBand.young;
                        }),
              ),
              ChoiceChip(
                label: const Text('10-13 years'),
                selected: _selectedAgeBand == AgeBand.middle,
                onSelected: _isSubmitting
                    ? null
                    : (_) => setState(() {
                          _selectedAgeBand = AgeBand.middle;
                        }),
              ),
              ChoiceChip(
                label: const Text('14-17 years'),
                selected: _selectedAgeBand == AgeBand.teen,
                onSelected: _isSubmitting
                    ? null
                    : (_) => setState(() {
                          _selectedAgeBand = AgeBand.teen;
                        }),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitSingleStepOnboarding,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_rounded),
              label: Text(
                _isSubmitting ? 'Generating...' : 'Generate Pairing Code',
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          if (_createdChild != null && _pairingCode != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pairing code for ${_createdChild!.nickname}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _spacedCode(_pairingCode!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isPairingCodeExpired
                          ? 'Code expired. Generate a fresh code.'
                          : 'Expires in ${_countdownLabel()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : _submitSingleStepOnboarding,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Regenerate'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _openHome,
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showConsentRequired() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please accept guardian consent to continue.'),
      ),
    );
  }

  Future<void> _openExternalUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open link right now.')),
      );
    }
  }
}
