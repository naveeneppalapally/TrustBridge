import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../config/feature_gates.dart';
import '../../screens/upgrade_screen.dart';
import '../../services/feature_gate_service.dart';
import '../../services/request_access_service.dart';
import '../../utils/child_friendly_errors.dart';

/// Child-friendly screen to request temporary access from a parent.
class RequestAccessScreen extends StatefulWidget {
  const RequestAccessScreen({
    super.key,
    this.prefilledAppName,
    this.firestore,
    this.parentId,
    this.childId,
    this.childNickname,
  });

  final String? prefilledAppName;
  final FirebaseFirestore? firestore;
  final String? parentId;
  final String? childId;
  final String? childNickname;

  @override
  State<RequestAccessScreen> createState() => _RequestAccessScreenState();
}

class _RequestAccessScreenState extends State<RequestAccessScreen> {
  static const List<String> _defaultApps = <String>[
    'Instagram',
    'TikTok',
    'YouTube',
    'Something else...',
  ];

  static const List<({String label, int minutes})> _durations = [
    (label: '15 min', minutes: 15),
    (label: '30 min', minutes: 30),
    (label: '1 hour', minutes: 60),
    (label: 'Rest of day', minutes: 720),
  ];

  late final TextEditingController _noteController;
  late final TextEditingController _otherAppController;
  late final FirebaseFirestore _firestore;
  RequestAccessService? _requestAccessService;
  RequestAccessService get _resolvedRequestAccessService {
    _requestAccessService ??= RequestAccessService(firestore: _firestore);
    return _requestAccessService!;
  }

  String? _selectedApp;
  int _selectedDurationMinutes = 30;
  bool _sending = false;
  bool _sent = false;
  String? _error;
  String? _parentId;
  String? _childId;
  String? _childNickname;

  bool get _isOtherSelected => _selectedApp == 'Something else...';

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseFirestore.instance;
    _noteController = TextEditingController();
    _otherAppController = TextEditingController();
    _selectedApp = widget.prefilledAppName?.trim().isEmpty == true
        ? null
        : widget.prefilledAppName?.trim();
    _parentId = widget.parentId?.trim();
    _childId = widget.childId?.trim();
    _childNickname = widget.childNickname?.trim();
    unawaited(_resolveContextIfNeeded());
  }

  @override
  void dispose() {
    _noteController.dispose();
    _otherAppController.dispose();
    super.dispose();
  }

  Future<void> _resolveContextIfNeeded() async {
    if ((_parentId?.isNotEmpty ?? false) &&
        (_childId?.isNotEmpty ?? false) &&
        (_childNickname?.isNotEmpty ?? false)) {
      return;
    }

    try {
      final context = await _resolvedRequestAccessService.resolveContext(
        parentId: _parentId,
        childId: _childId,
        childNickname: _childNickname,
      );
      _parentId = context.parentId;
      _childId = context.childId;
      _childNickname = context.childNickname;
    } catch (error) {
      _error = ChildFriendlyErrors.sanitise(error.toString());
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendRequest() async {
    final selectedApp = _selectedApp?.trim();
    var requestedApp = selectedApp ?? '';
    if (_isOtherSelected) {
      requestedApp = _otherAppController.text.trim();
    }

    if (requestedApp.isEmpty || _parentId == null || _childId == null) {
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final gate =
          await FeatureGateService().checkGate(AppFeature.requestApproveFlow);
      if (!gate.allowed) {
        if (!mounted) {
          return;
        }
        await UpgradeScreen.maybeShow(
          context,
          feature: AppFeature.requestApproveFlow,
          reason: gate.upgradeReason,
        );
        setState(() {
          _sending = false;
          _error = 'Ask your parent to enable TrustBridge Pro for requests.';
        });
        return;
      }

      final selectedDuration = _durations
          .firstWhere((item) => item.minutes == _selectedDurationMinutes);
      await _resolvedRequestAccessService.sendAccessRequest(
        parentId: _parentId!,
        childId: _childId!,
        childNickname: _childNickname ?? 'Your child',
        requestedApp: requestedApp,
        durationLabel: selectedDuration.label,
        durationMinutes: _selectedDurationMinutes,
        reason: _noteController.text,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sending = false;
        _error = ChildFriendlyErrors.sanitise(error.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ask for access'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('✉️', style: TextStyle(fontSize: 50)),
                const SizedBox(height: 12),
                Text(
                  'Request sent!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your parent will see it soon.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final canSend = !_sending &&
        (_selectedApp?.isNotEmpty ?? false) &&
        (!_isOtherSelected || _otherAppController.text.trim().isNotEmpty) &&
        (_parentId?.isNotEmpty ?? false) &&
        (_childId?.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask for access'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            'What do you want to use?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          ..._defaultApps.map((app) {
            final selected = _selectedApp == app;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _sending
                    ? null
                    : () {
                        setState(() {
                          _selectedApp = app;
                          _error = null;
                        });
                      },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.35),
                    ),
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.10)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(app)),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (_isOtherSelected) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _otherAppController,
              enabled: !_sending,
              decoration: const InputDecoration(
                labelText: 'App or website',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'For how long?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _durations.map((duration) {
              return ChoiceChip(
                label: Text(duration.label),
                selected: _selectedDurationMinutes == duration.minutes,
                onSelected: _sending
                    ? null
                    : (_) => setState(() {
                          _selectedDurationMinutes = duration.minutes;
                        }),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            enabled: !_sending,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Add a note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: canSend ? _sendRequest : null,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Sending...' : 'Send request'),
            ),
          ),
        ],
      ),
    );
  }
}
