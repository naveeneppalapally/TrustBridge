import 'package:flutter/material.dart';

class ChildTutorialScreen extends StatefulWidget {
  const ChildTutorialScreen({
    super.key,
    this.onFinished,
  });

  final VoidCallback? onFinished;

  @override
  State<ChildTutorialScreen> createState() => _ChildTutorialScreenState();
}

class _ChildTutorialScreenState extends State<ChildTutorialScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_TutorialStep> _steps = [
    _TutorialStep(
      stepNumber: '1',
      title: '1. Ask for Permission',
      subtitle:
          'Found a fun new app or game? Just tap the button to ask your parents!',
      icon: Icons.send_rounded,
      iconColor: Color(0xFF2E86FF),
    ),
    _TutorialStep(
      stepNumber: '2',
      title: '2. Wait for Reply',
      subtitle:
          'Mom or Dad will get a notification and can approve it right away.',
      icon: Icons.notifications_active_outlined,
      iconColor: Color(0xFF10B981),
    ),
    _TutorialStep(
      stepNumber: '3',
      title: '3. You are Protected',
      subtitle:
          'TrustBridge keeps you safe while giving you freedom to explore.',
      icon: Icons.shield_rounded,
      iconColor: Color(0xFF8B5CF6),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _steps.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Step ${_index + 1} of ${_steps.length}: The Basics',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[700],
                        ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const Key('child_tutorial_skip_button'),
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const Key('child_tutorial_page_view'),
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (value) {
                  setState(() {
                    _index = value;
                  });
                },
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return _TutorialPage(step: step);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _steps.length,
                  (dot) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: dot == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot == _index
                          ? const Color(0xFF2E86FF)
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('child_tutorial_next_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E86FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: isLast ? _finish : _next,
                  child: Text(
                    isLast ? 'Let\'s Go!' : 'Next ->',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish() {
    if (widget.onFinished != null) {
      widget.onFinished!();
      return;
    }
    Navigator.of(context).pop();
  }
}

class _TutorialPage extends StatelessWidget {
  const _TutorialPage({required this.step});

  final _TutorialStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  step.icon,
                  size: 118,
                  color: step.iconColor,
                ),
              ),
              Positioned(
                top: -10,
                right: -10,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E86FF),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      step.stepNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            step.title,
            key: Key('child_tutorial_title_${step.stepNumber}'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 10),
          Text(
            step.subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _TutorialStep {
  const _TutorialStep({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });

  final String stepNumber;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
}
