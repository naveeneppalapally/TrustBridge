import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class BetaFeedbackScreen extends StatefulWidget {
  const BetaFeedbackScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<BetaFeedbackScreen> createState() => _BetaFeedbackScreenState();
}

class _BetaFeedbackScreenState extends State<BetaFeedbackScreen> {
  static const List<String> _categories = <String>[
    'Bug Report',
    'Blocking Accuracy',
    'Performance',
    'UX / Design',
    'Feature Request',
    'Other',
  ];
  static const List<String> _severities = <String>[
    'Low',
    'Medium',
    'High',
    'Critical',
  ];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  AuthService? _authService;
  FirestoreService? _firestoreService;

  String? _selectedCategory;
  String _selectedSeverity = 'Medium';
  String? _selectedChildId;
  String? _validationError;
  bool _submitting = false;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  String? get _parentId {
    return widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Beta Feedback')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beta Feedback'),
      ),
      body: StreamBuilder<List<ChildProfile>>(
        stream: _resolvedFirestoreService.getChildrenStream(parentId),
        builder:
            (BuildContext context, AsyncSnapshot<List<ChildProfile>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Unable to load feedback form',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }

          final children = snapshot.data ?? const <ChildProfile>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _buildIntroCard(context),
              const SizedBox(height: 16),
              _buildFormCard(context, children),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Help shape TrustBridge Beta',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share bugs, blocking issues, and UX feedback. '
              'Your reports are routed directly to the build queue.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context, List<ChildProfile> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('beta_feedback_category_dropdown'),
              initialValue: _selectedCategory,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map(
                    (String category) => DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (String? value) {
                      setState(() {
                        _selectedCategory = value;
                        _validationError = null;
                      });
                    },
            ),
            const SizedBox(height: 12),
            Text(
              'Severity',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _severities.map((String severity) {
                return ChoiceChip(
                  label: Text(severity),
                  selected: _selectedSeverity == severity,
                  onSelected: _submitting
                      ? null
                      : (_) {
                          setState(() {
                            _selectedSeverity = severity;
                          });
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('beta_feedback_child_dropdown'),
              initialValue: _selectedChildId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Related Child (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No specific child'),
                ),
                ...children.map(
                  (ChildProfile child) => DropdownMenuItem<String?>(
                    value: child.id,
                    child: Text(child.nickname),
                  ),
                ),
              ],
              onChanged: _submitting
                  ? null
                  : (String? value) {
                      setState(() {
                        _selectedChildId = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('beta_feedback_title_input'),
              controller: _titleController,
              enabled: !_submitting,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Short title',
                hintText: 'e.g., Approved requests not expiring',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('beta_feedback_details_input'),
              controller: _detailsController,
              enabled: !_submitting,
              minLines: 5,
              maxLines: 7,
              maxLength: 1500,
              decoration: const InputDecoration(
                labelText: 'Details',
                hintText: 'What happened? Expected result? Steps to reproduce?',
                border: OutlineInputBorder(),
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationError!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('beta_feedback_submit_button'),
                onPressed: _submitting ? null : _submitFeedback,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_submitting ? 'Submitting...' : 'Submit Feedback'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitFeedback() async {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      _setValidationError('You must be logged in to submit beta feedback.');
      return;
    }

    final category = _selectedCategory?.trim();
    final title = _titleController.text.trim();
    final details = _detailsController.text.trim();

    if (category == null || category.isEmpty) {
      _setValidationError('Please choose a feedback category.');
      return;
    }
    if (title.length < 4) {
      _setValidationError('Title must be at least 4 characters.');
      return;
    }
    if (details.length < 20) {
      _setValidationError('Please enter at least 20 characters in details.');
      return;
    }

    setState(() {
      _submitting = true;
      _validationError = null;
    });

    try {
      await _resolvedFirestoreService.submitBetaFeedback(
        parentId: parentId,
        category: category,
        severity: _selectedSeverity,
        title: title,
        details: details,
        childId: _selectedChildId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _selectedCategory = null;
        _selectedSeverity = 'Medium';
        _selectedChildId = null;
      });
      _titleController.clear();
      _detailsController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feedback submitted. Thank you!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
      });
      showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Submit Failed'),
            content: Text('Unable to submit beta feedback: $error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  void _setValidationError(String message) {
    setState(() {
      _validationError = message;
    });
  }
}
