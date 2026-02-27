import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  static const String _supportEmail = String.fromEnvironment(
    'TRUSTBRIDGE_SUPPORT_EMAIL',
    defaultValue: '',
  );

  static const List<String> _topics = [
    'Blocking Question',
    'Child Profile Issue',
    'Account & Security',
    'Billing & Subscription',
    'Bug Report',
    'Feature Request',
  ];

  final TextEditingController _messageController = TextEditingController();

  AuthService? _authService;
  FirestoreService? _firestoreService;

  String? _selectedTopic;
  String? _selectedChildId;
  String? _validationError;
  bool _isSubmitting = false;

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
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Help & Support')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
      ),
      body: StreamBuilder<List<ChildProfile>>(
        stream: _resolvedFirestoreService.getChildrenStream(parentId),
        builder: (context, snapshot) {
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
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    const Text(
                      'Unable to load support tools',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final children = snapshot.data ?? const <ChildProfile>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text(
                'Get Help Quickly',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use quick FAQs or send a support request from inside the app.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 16),
              _buildContactCard(context),
              const SizedBox(height: 16),
              _buildRequestCard(context, children),
              const SizedBox(height: 16),
              _buildFaqCard(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContactCard(BuildContext context) {
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
            Row(
              children: [
                Icon(Icons.support_agent, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Support Contact',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_supportEmail.isNotEmpty)
              Text(
                'Email: $_supportEmail',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Text(
                'Email support is unavailable right now. Use the support form below.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 4),
            Text(
              'Response time: Usually within 24 hours',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            if (_supportEmail.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('support_copy_email_button'),
                onPressed: _copySupportEmail,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy Support Email'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(BuildContext context, List<ChildProfile> children) {
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
              'Send Support Request',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('support_topic_dropdown'),
              initialValue: _selectedTopic,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Topic',
                border: OutlineInputBorder(),
              ),
              items: _topics
                  .map(
                    (topic) => DropdownMenuItem<String>(
                      value: topic,
                      child: Text(topic),
                    ),
                  )
                  .toList(),
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      setState(() {
                        _selectedTopic = value;
                        _validationError = null;
                      });
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('support_child_dropdown'),
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
                  (child) => DropdownMenuItem<String?>(
                    value: child.id,
                    child: Text(child.nickname),
                  ),
                ),
              ],
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      setState(() {
                        _selectedChildId = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('support_message_input'),
              controller: _messageController,
              maxLines: 4,
              minLines: 3,
              enabled: !_isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Describe your issue',
                hintText:
                    'Tell us what happened, what you expected, and any steps to reproduce.',
                border: OutlineInputBorder(),
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationError!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('support_submit_button'),
                onPressed: _isSubmitting ? null : _submitRequest,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_isSubmitting ? 'Sending...' : 'Send Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqCard(BuildContext context) {
    const faqs = <(String, String)>[
      (
        'How do age presets work?',
        'Age presets apply recommended category blocks and schedule defaults for each age band. You can customize each rule anytime.',
      ),
      (
        'What does Pause Internet do?',
        'Pause Internet temporarily blocks access for that child. It auto-resumes when the selected duration ends or when you manually resume.',
      ),
      (
        'How quickly do updates apply?',
        'Most changes apply in a few seconds. If needed, refresh once after making a change.',
      ),
      (
        'Can I restore deleted child profiles?',
        'No. Child profile deletion is permanent in this app. Please review before confirming delete.',
      ),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.help_outline, color: Colors.indigo.shade600),
              title: const Text(
                'Frequently Asked Questions',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ...faqs.map(
              (faq) => ExpansionTile(
                title: Text(faq.$1),
                childrenPadding:
                    const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      faq.$2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
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

  void _copySupportEmail() {
    if (_supportEmail.isEmpty) {
      return;
    }
    Clipboard.setData(
      const ClipboardData(text: _supportEmail),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support email copied')),
    );
  }

  Future<void> _submitRequest() async {
    final parentId = _parentId;
    if (parentId == null) {
      _setValidationError('You must be logged in to send support requests.');
      return;
    }

    final topic = _selectedTopic?.trim();
    final message = _messageController.text.trim();

    if (topic == null || topic.isEmpty) {
      _setValidationError('Please choose a support topic.');
      return;
    }
    if (message.length < 10) {
      _setValidationError('Please enter at least 10 characters.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _validationError = null;
    });

    try {
      await _resolvedFirestoreService.createSupportTicket(
        parentId: parentId,
        subject: topic,
        message: message,
        childId: _selectedChildId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _selectedTopic = null;
        _selectedChildId = null;
      });
      _messageController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Support request sent successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
      });

      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Send Failed'),
            content: Text('Unable to send support request: $error'),
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
