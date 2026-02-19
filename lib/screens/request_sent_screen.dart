import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'child_requests_screen.dart';

class RequestSentScreen extends StatefulWidget {
  const RequestSentScreen({
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
  State<RequestSentScreen> createState() => _RequestSentScreenState();
}

class _RequestSentScreenState extends State<RequestSentScreen>
    with TickerProviderStateMixin {
  late final AnimationController _planeController;
  late final AnimationController _statusPulseController;
  late final Animation<double> _planeOffset;

  @override
  void initState() {
    super.initState();
    _planeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _statusPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _planeOffset = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _planeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _planeController.dispose();
    _statusPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              _buildPlaneAnimation(),
              const SizedBox(height: 24),
              Text(
                'Request Sent!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.child.nickname} usually gets a response in 15 mins.\nWe will notify you as soon as there is an update.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 24),
              _buildStatusCard(),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('request_sent_view_status_button'),
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ChildRequestsScreen(
                          child: widget.child,
                          authService: widget.authService,
                          firestoreService: widget.firestoreService,
                          parentIdOverride: widget.parentIdOverride,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'View Status ->',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('request_sent_back_home_button'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to Home'),
              ),
              const SizedBox(height: 8),
              Text(
                'TRUSTBRIDGE SECURE',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaneAnimation() {
    return AnimatedBuilder(
      animation: _planeOffset,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _planeOffset.value),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x1A207CF8),
                ),
                child: const Icon(
                  Icons.send_rounded,
                  size: 56,
                  color: Color(0xFF207CF8),
                ),
              ),
              Positioned(
                top: 20,
                right: 18,
                child: _floatingDot(const Color(0xFF9AC3FF)),
              ),
              Positioned(
                left: 16,
                bottom: 20,
                child: _floatingDot(const Color(0xFF72A8FF)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _floatingDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
        color: Colors.blue.withValues(alpha: 0.06),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Color(0xFF207CF8)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT STATUS',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[600],
                        letterSpacing: 0.6,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Waiting for approval',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    FadeTransition(
                      opacity: _statusPulseController.drive(
                        Tween<double>(begin: 0.35, end: 1.0),
                      ),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF207CF8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
