import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:trustbridge_app/l10n/app_localizations.dart';
import 'package:trustbridge_app/l10n/app_localizations_en.dart';
import 'package:trustbridge_app/config/feature_gates.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/screens/add_child_device_screen.dart';
import 'package:trustbridge_app/screens/upgrade_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/feature_gate_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nicknameController = TextEditingController();

  AuthService? _authService;
  FirestoreService? _firestoreService;

  AgeBand _selectedAgeBand = AgeBand.middle;
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedAvatar = '🙂';

  static const _avatarOptions = <String>['🙂', '😎', '🧒', '👧', '👦', '🧑'];

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enforceAdditionalChildrenGateOnEntry();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addChildTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              'Add Child · STEP 1 OF 2',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: const LinearProgressIndicator(
                value: 0.5,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 24),
            _buildAvatarPicker(),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nicknameController,
              key: const Key('add_child_nickname_input'),
              decoration: InputDecoration(
                labelText: l10n.childNicknameLabel,
                hintText: l10n.nicknameHint,
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return l10n.enterNicknameError;
                }
                if (trimmed.length < 2) {
                  return l10n.nicknameMinError;
                }
                if (trimmed.length > 20) {
                  return l10n.nicknameMaxError;
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            Text(
              'PROTECTION LEVEL',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
            ),
            const SizedBox(height: 10),
            _buildProtectionCard(
              key: const Key('add_child_level_strict'),
              title: 'Strict',
              subtitle:
                  'Highest safety and content filtering. Manual approval for all new apps.',
              color: const Color(0xFFD32F2F),
              selected: _selectedAgeBand == AgeBand.young,
              onTap: () => setState(() => _selectedAgeBand = AgeBand.young),
            ),
            const SizedBox(height: 10),
            _buildProtectionCard(
              key: const Key('add_child_level_moderate'),
              title: 'Moderate',
              subtitle:
                  'Balanced freedom and automation. Safe-search and filtering enabled.',
              color: const Color(0xFF1976D2),
              selected: _selectedAgeBand == AgeBand.middle,
              onTap: () => setState(() => _selectedAgeBand = AgeBand.middle),
            ),
            const SizedBox(height: 10),
            _buildProtectionCard(
              key: const Key('add_child_level_light'),
              title: 'Light',
              subtitle:
                  'Trust-based monitoring with minimal blocking and fewer restrictions.',
              color: const Color(0xFF2E7D32),
              selected: _selectedAgeBand == AgeBand.teen,
              onTap: () => setState(() => _selectedAgeBand = AgeBand.teen),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              _buildErrorCard(),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                key: const Key('add_child_submit'),
                onPressed: _isLoading ? null : _saveChild,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Continue to Pairing ->'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'PRIVACY-FIRST ENCRYPTION ENABLED',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.10),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  _selectedAvatar,
                  style: const TextStyle(fontSize: 42),
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: InkWell(
                key: const Key('add_child_avatar_picker_button'),
                onTap: _openAvatarPicker,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFF207CF8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Choose an avatar',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
        ),
      ],
    );
  }

  Widget _buildProtectionCard({
    required Key key,
    required String title,
    required String subtitle,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF207CF8)
                : Colors.grey.withValues(alpha: 0.35),
            width: selected ? 2 : 1,
          ),
          color: selected ? const Color(0x1A207CF8) : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_rounded, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[700],
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF207CF8),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAvatarPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _avatarOptions
                  .map(
                    (avatar) => InkWell(
                      onTap: () => Navigator.of(context).pop(avatar),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          avatar,
                          style: const TextStyle(fontSize: 30),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedAvatar = selected;
      });
    }
  }

  Future<void> _saveChild() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final parentId =
          widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      final existingChildren =
          await _resolvedFirestoreService.getChildrenOnce(parentId);
      if (existingChildren.isNotEmpty) {
        final gateResult =
            await FeatureGateService().checkGate(AppFeature.additionalChildren);
        if (!gateResult.allowed) {
          if (mounted) {
            final upgraded = await UpgradeScreen.maybeShow(
              context,
              feature: AppFeature.additionalChildren,
              reason: gateResult.upgradeReason,
            );
            if (!upgraded && mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          }
          return;
        }
      }

      final child = await _resolvedFirestoreService.addChild(
        parentId: parentId,
        nickname: _nicknameController.text.trim(),
        ageBand: _selectedAgeBand,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l10n(context).childAddedSuccessMessage(child.nickname),
          ),
          backgroundColor: Colors.green,
        ),
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddChildDeviceScreen(child: child),
        ),
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = _l10n(context).failedToAddChildMessage(
          _messageFromError(error),
        );
      });
    }
  }

  String _messageFromError(Object error) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.replaceFirst('Exception: ', '');
    }
    return raw;
  }

  Future<void> _enforceAdditionalChildrenGateOnEntry() async {
    if (widget.parentIdOverride == null &&
        widget.authService == null &&
        Firebase.apps.isEmpty) {
      return;
    }

    final parentId =
        widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
    if (parentId == null || !mounted) {
      return;
    }

    final existingChildren =
        await _resolvedFirestoreService.getChildrenOnce(parentId);
    if (existingChildren.isEmpty || !mounted) {
      return;
    }

    final gateResult = await () async {
      try {
        return await FeatureGateService()
            .checkGate(AppFeature.additionalChildren);
      } catch (_) {
        // Ignore gate checks when Firebase isn't available in test contexts.
        return const GateResult(allowed: true);
      }
    }();
    if (gateResult.allowed || !mounted) {
      return;
    }

    final upgraded = await UpgradeScreen.maybeShow(
      context,
      feature: AppFeature.additionalChildren,
      reason: gateResult.upgradeReason,
    );
    if (!upgraded && mounted) {
      Navigator.of(context).pop();
    }
  }
}

AppLocalizations _l10n(BuildContext context) {
  return AppLocalizations.of(context) ?? AppLocalizationsEn();
}
