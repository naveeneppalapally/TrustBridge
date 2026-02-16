import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/screens/age_band_presets_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
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

  AgeBand _selectedAgeBand = AgeBand.young;
  bool _isLoading = false;
  String? _errorMessage;

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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final surfaceColor = isDark ? const Color(0xFF1F2937) : Colors.white;
    final pageWidth = MediaQuery.sizeOf(context).width;
    final isTablet = pageWidth >= 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Child'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Age Band Guide',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AgeBandPresetsScreen(),
                ),
              );
            },
          ),
        ],
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
                    'Add a new child profile',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We will set up age-appropriate content filters',
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
                            helperText: 'What should we call this child?',
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
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 370;
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Age Group',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                if (isCompact)
                                  IconButton(
                                    icon: const Icon(Icons.help_outline),
                                    tooltip: 'Which age band?',
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AgeBandPresetsScreen(),
                                        ),
                                      );
                                    },
                                  )
                                else
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AgeBandPresetsScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.help_outline, size: 16),
                                    label: const Text('Which age band?'),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        RadioGroup<AgeBand>(
                          groupValue: _selectedAgeBand,
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedAgeBand = value;
                              });
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
                  const SizedBox(height: 18),
                  _buildPolicyPreview(),
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
                          : const Text('Add Child'),
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

  Widget _buildAgeBandOption({
    required AgeBand ageBand,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedAgeBand == ageBand;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedAgeBand = ageBand;
        });
      },
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
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
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

  Widget _buildPolicyPreview() {
    final policy = Policy.presetForAgeBand(_selectedAgeBand);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF172638) : const Color(0xFFEFF7FF);
    final borderColor =
        isDark ? Colors.blue.withValues(alpha: 0.35) : const Color(0xFFBFDBFE);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'What will be blocked?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark ? Colors.white : Colors.blue.shade900,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (policy.blockedCategories.isNotEmpty) ...[
            Text(
              'Content:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            ...policy.blockedCategories.map(
              (category) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  children: [
                    Icon(Icons.block, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatCategoryName(category),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (policy.schedules.isNotEmpty) ...[
            Text(
              'Time restrictions:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            ...policy.schedules.map(
              (schedule) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${schedule.name}: ${schedule.startTime} - ${schedule.endTime}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (policy.safeSearchEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Row(
                children: [
                  Icon(Icons.search, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  const Text('Safe search enabled'),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'You can customize these settings later',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }

  String _formatCategoryName(String category) {
    return category
        .split('-')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
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
      final parentId = widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
      if (parentId == null) {
        throw Exception('Not logged in');
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
          content: Text('${child.nickname} added successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to add child: ${_messageFromError(error)}';
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
}
