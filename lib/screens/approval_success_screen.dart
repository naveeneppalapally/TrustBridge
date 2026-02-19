import 'package:flutter/material.dart';

class ApprovalSuccessScreen extends StatefulWidget {
  const ApprovalSuccessScreen({
    super.key,
    required this.appName,
    required this.durationLabel,
    required this.childName,
  });

  final String appName;
  final String durationLabel;
  final String childName;

  @override
  State<ApprovalSuccessScreen> createState() => _ApprovalSuccessScreenState();
}

class _ApprovalSuccessScreenState extends State<ApprovalSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final AnimationController _dotController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _dotController.dispose();
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
              _buildAnimatedCheck(),
              const SizedBox(height: 26),
              Text(
                'Success!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                '${widget.appName} approved for ${widget.durationLabel}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.green[800],
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Sent to ${widget.childName}',
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  key: const Key('approval_success_done_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCheck() {
    return AnimatedBuilder(
      animation: Listenable.merge([_scaleAnimation, _dotController]),
      builder: (context, _) {
        final pulse = 1 + (_dotController.value * 0.08);
        return Transform.scale(
          scale: _scaleAnimation.value * pulse,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  color: Color(0xFF68B901),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              ),
              Positioned(
                top: 8,
                right: 18,
                child: _particle(Colors.green.withValues(alpha: 0.65)),
              ),
              Positioned(
                left: 14,
                bottom: 18,
                child: _particle(Colors.lightGreen.withValues(alpha: 0.65)),
              ),
              Positioned(
                right: 8,
                bottom: 22,
                child: _particle(Colors.teal.withValues(alpha: 0.55)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _particle(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
