import 'package:flutter/material.dart';

import '../models/access_request.dart';
import '../models/child_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/spring_animation.dart';
import 'request_sent_screen.dart';

class ChildRequestScreen extends StatefulWidget {
  const ChildRequestScreen({
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
  State<ChildRequestScreen> createState() => _ChildRequestScreenState();
}

class _ChildRequestScreenState extends State<ChildRequestScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  final TextEditingController _appController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  String _appOrSite = '';
  String? _selectedQuickApp;
  RequestDuration _selectedDuration = RequestDuration.fifteenMin;
  bool _isLoading = false;
  String? _error;

  static const _quickApps = <_QuickApp>[
    _QuickApp(name: 'Roblox', icon: Icons.sports_esports_rounded),
    _QuickApp(name: 'YouTube', icon: Icons.play_circle_fill_rounded),
    _QuickApp(name: 'TikTok', icon: Icons.music_note_rounded),
    _QuickApp(name: 'Instagram', icon: Icons.camera_alt_rounded),
  ];

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  bool get _canSubmit => _appOrSite.trim().isNotEmpty && !_isLoading;

  @override
  void dispose() {
    _appController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask for Access'),
      ),
      body: _buildRequestComposer(),
    );
  }

  Widget _buildRequestComposer() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _buildHeroBanner(),
              const SizedBox(height: 20),
              _buildAppSection(),
              const SizedBox(height: 20),
              _buildDurationSection(),
              const SizedBox(height: 20),
              _buildReasonSection(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _buildError(),
              ],
            ],
          ),
        ),
        _buildDraftBar(),
      ],
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF2D8CFF), Color(0xFF1D6FE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white24,
            child: Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask your parent',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Share what you need and why. They usually reply quickly.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Which app?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 10),
        TextField(
          onChanged: (value) {
            setState(() {
              _appOrSite = value;
              _selectedQuickApp = null;
            });
          },
          decoration: InputDecoration(
            hintText: 'Search apps...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _quickApps
              .map(
                (app) => _buildQuickAppChip(app),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('child_request_app_input'),
          controller: _appController,
          onChanged: (value) {
            setState(() {
              _appOrSite = value;
              _selectedQuickApp = _quickApps.any(
                (app) => app.name.toLowerCase() == value.toLowerCase().trim(),
              )
                  ? value.trim()
                  : null;
            });
          },
          decoration: InputDecoration(
            hintText: 'Type app/site name if not listed',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAppChip(_QuickApp app) {
    final selected = _selectedQuickApp == app.name;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedQuickApp = app.name;
          _appOrSite = app.name;
          _appController.text = app.name;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: SpringAnimation.springCurve,
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0x1A207CF8)
              : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF207CF8) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(app.icon,
                color: selected ? const Color(0xFF207CF8) : Colors.grey[700]),
            const SizedBox(height: 6),
            Text(
              app.name,
              style: TextStyle(
                fontSize: 11,
                color: selected ? const Color(0xFF207CF8) : Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'For how long?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: RequestDuration.values
              .map((duration) => _buildDurationChip(duration))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildDurationChip(RequestDuration duration) {
    final selected = _selectedDuration == duration;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDuration = duration;
        });
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 320),
        curve: SpringAnimation.springCurve,
        scale: selected ? 1.06 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: SpringAnimation.springCurve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF207CF8) : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? const Color(0xFF207CF8)
                  : Colors.grey.withValues(alpha: 0.40),
            ),
          ),
          child: Text(
            _durationChipLabel(duration),
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey[800],
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _durationChipLabel(RequestDuration duration) {
    switch (duration) {
      case RequestDuration.fifteenMin:
        return '15m';
      case RequestDuration.thirtyMin:
        return '30m';
      case RequestDuration.oneHour:
        return '1h';
      case RequestDuration.twoHours:
        return '2h';
      case RequestDuration.untilScheduleEnds:
        return 'Until schedule ends';
    }
  }

  Widget _buildReasonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Why do you need it?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('child_request_reason_input'),
          controller: _reasonController,
          maxLines: 4,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: "I'm finishing a game with Leo...",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDraftBar() {
    final hasDraft = _appOrSite.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: Colors.grey.withValues(alpha: 0.20)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasDraft)
              Container(
                key: const Key('child_request_draft_preview'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0x1A207CF8),
                      child: Icon(Icons.apps_rounded,
                          color: Color(0xFF207CF8), size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Requesting access - ${_appOrSite.trim()} for ${_selectedDuration.label}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Draft',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pick an app to start your request.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                key: const Key('child_request_submit_button'),
                onPressed: _canSubmit ? _submitRequest : null,
                child: _isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Send Request ->',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRequest() async {
    if (!_canSubmit) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final parentId =
          widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
      if (parentId == null || parentId.trim().isEmpty) {
        throw StateError('Not logged in');
      }

      final request = AccessRequest.create(
        childId: widget.child.id,
        parentId: parentId,
        childNickname: widget.child.nickname,
        appOrSite: _appOrSite.trim(),
        duration: _selectedDuration,
        reason: _reasonController.text.trim().isEmpty
            ? null
            : _reasonController.text.trim(),
      );

      await _resolvedFirestoreService.submitAccessRequest(request);
      await _resolvedFirestoreService.queueParentNotification(
        parentId: parentId,
        title: '${widget.child.nickname} wants access',
        body:
            '${widget.child.nickname} is requesting access to ${_appOrSite.trim()} for ${_selectedDuration.label}',
        route: '/parent-requests',
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RequestSentScreen(
            child: widget.child,
            authService: widget.authService,
            firestoreService: widget.firestoreService,
            parentIdOverride: widget.parentIdOverride,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = 'Could not send request. Please try again.';
      });
    }
  }
}

class _QuickApp {
  const _QuickApp({
    required this.name,
    required this.icon,
  });

  final String name;
  final IconData icon;
}
