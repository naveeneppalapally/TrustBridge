import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class EditChildScreen extends StatefulWidget {
  const EditChildScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<EditChildScreen> createState() => _EditChildScreenState();
}

class _EditChildScreenState extends State<EditChildScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameController;

  AuthService? _authService;
  FirestoreService? _firestoreService;
  late AgeBand _selectedAgeBand;

  bool _isLoading = false;
  String? _errorMessage;
  bool _ageBandChanged = false;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.child.nickname);
    _selectedAgeBand = widget.child.ageBand;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageWidth = MediaQuery.sizeOf(context).width;
    final isTablet = pageWidth >= 600;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final surfaceColor = isDark ? const Color(0xFF1F2937) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Child'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            isTablet ? 28 : 20,
            12,
            isTablet ? 28 : 20,
            28,
          ),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update Profile',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Changes will be saved to ${widget.child.nickname}\'s profile',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nicknameController,
                          decoration: const InputDecoration(
                            labelText: 'Nickname',
                            hintText: 'e.g., Alex, Sam, Priya',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            if (trimmed.isEmpty) {
                              return 'Please enter a nickname';
                            }
                            if (trimmed.length < 2) {
                              return 'Nickname must be at least 2 characters';
                            }
                            if (trimmed.length > 20) {
                              return 'Nickname must be less than 20 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Age Group',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_ageBandChanged) ...[
                          _buildAgeWarning(),
                          const SizedBox(height: 8),
                        ],
                        RadioGroup<AgeBand>(
                          groupValue: _selectedAgeBand,
                          onChanged: (value) {
                            if (value != null) {
                              _onAgeBandSelected(value);
                            }
                          },
                          child: Column(
                            children: [
                              _buildAgeBandOption(
                                ageBand: AgeBand.young,
                                title: '6-9 years',
                                subtitle: 'Young children - strictest filters',
                                icon: Icons.child_care,
                              ),
                              const SizedBox(height: 10),
                              _buildAgeBandOption(
                                ageBand: AgeBand.middle,
                                title: '10-13 years',
                                subtitle: 'Middle schoolers - moderate filters',
                                icon: Icons.school,
                              ),
                              const SizedBox(height: 10),
                              _buildAgeBandOption(
                                ageBand: AgeBand.teen,
                                title: '14-17 years',
                                subtitle: 'Teenagers - balanced approach',
                                icon: Icons.face,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_ageBandChanged) ...[
                    const SizedBox(height: 16),
                    _buildChangesPreview(),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.red.withValues(alpha: 0.15)
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      key: const Key('edit_child_save'),
                      onPressed: _isLoading ? null : _saveChanges,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).pop(false);
                            },
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgeWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Changing age band will update content filters to match the new age group.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeBandOption({
    required AgeBand ageBand,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedAgeBand == ageBand;
    final isOriginal = widget.child.ageBand == ageBand;

    return InkWell(
      onTap: () => _onAgeBandSelected(ageBand),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: Row(
          children: [
            Radio<AgeBand>(
              value: ageBand,
            ),
            const SizedBox(width: 6),
            Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                      ),
                      if (isOriginal)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Current',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade800,
                                    ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangesPreview() {
    final oldPolicy = widget.child.policy;
    final newPolicy = Policy.presetForAgeBand(_selectedAgeBand);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Policy Changes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPolicyComparison(
            context,
            'Blocked Categories',
            oldPolicy.blockedCategories.length,
            newPolicy.blockedCategories.length,
          ),
          const SizedBox(height: 8),
          _buildPolicyComparison(
            context,
            'Time Restrictions',
            oldPolicy.schedules.length,
            newPolicy.schedules.length,
          ),
          const SizedBox(height: 8),
          _buildPolicyComparison(
            context,
            'Safe Search',
            oldPolicy.safeSearchEnabled ? 1 : 0,
            newPolicy.safeSearchEnabled ? 1 : 0,
            isBoolean: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyComparison(
    BuildContext context,
    String label,
    int oldValue,
    int newValue, {
    bool isBoolean = false,
  }) {
    final changed = oldValue != newValue;
    final arrowColor = changed ? Colors.orange.shade700 : Colors.grey.shade600;
    final oldDisplay = isBoolean ? (oldValue == 1 ? 'ON' : 'OFF') : '$oldValue';
    final newDisplay = isBoolean ? (newValue == 1 ? 'ON' : 'OFF') : '$newValue';

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Text(
          oldDisplay,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: changed ? Colors.grey.shade600 : null,
                decoration: changed ? TextDecoration.lineThrough : null,
              ),
        ),
        if (changed) ...[
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward, size: 16, color: arrowColor),
          const SizedBox(width: 8),
          Text(
            newDisplay,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: arrowColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }

  void _onAgeBandSelected(AgeBand ageBand) {
    setState(() {
      _selectedAgeBand = ageBand;
      _ageBandChanged = widget.child.ageBand != ageBand;
    });
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final newNickname = _nicknameController.text.trim();
    final nicknameChanged = newNickname != widget.child.nickname;
    if (!nicknameChanged && !_ageBandChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No changes to save')),
      );
      return;
    }

    if (_ageBandChanged) {
      final confirmed = await _confirmAgeBandChange();
      if (!confirmed) {
        return;
      }
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

      final updatedChild = widget.child.copyWith(
        nickname: newNickname,
        ageBand: _selectedAgeBand,
        policy: _ageBandChanged
            ? Policy.presetForAgeBand(_selectedAgeBand)
            : widget.child.policy,
      );

      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${updatedChild.nickname} updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to update child: ${_messageFromError(error)}';
      });
    }
  }

  Future<bool> _confirmAgeBandChange() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Age Band?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Changing from ${widget.child.ageBand.value} to ${_selectedAgeBand.value} will update content filters.',
              ),
              const SizedBox(height: 12),
              const Text(
                'The policy will reset to age-appropriate defaults. Any custom changes will be lost.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text('Do you want to continue?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Change Age Band'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  String _messageFromError(Object error) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.replaceFirst('Exception: ', '');
    }
    return raw;
  }
}
