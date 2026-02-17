import 'package:flutter/material.dart';
import 'package:trustbridge_app/screens/add_child_screen.dart';
import 'package:trustbridge_app/screens/vpn_protection_screen.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.parentId,
    this.isRevisit = false,
    this.firestoreService,
  });

  final String parentId;
  final bool isRevisit;
  final FirestoreService? firestoreService;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _totalPages = 3;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCompleting = false;

  FirestoreService get _resolvedFirestoreService {
    return widget.firestoreService ?? FirestoreService();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage >= _totalPages - 1) {
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
    );
  }

  void _previousPage() {
    if (_currentPage <= 0) {
      return;
    }
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
    );
  }

  Future<void> _complete() async {
    if (_isCompleting) {
      return;
    }
    setState(() {
      _isCompleting = true;
    });

    try {
      await _resolvedFirestoreService.completeOnboarding(widget.parentId);
      if (!mounted) {
        return;
      }
      if (widget.isRevisit) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCompleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to complete onboarding: $error')),
      );
    }
  }

  Future<void> _skip() async {
    if (_isCompleting) {
      return;
    }
    setState(() {
      _isCompleting = true;
    });
    try {
      await _resolvedFirestoreService.completeOnboarding(widget.parentId);
      if (!mounted) {
        return;
      }
      if (widget.isRevisit) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCompleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to skip onboarding: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildWelcomePage(context),
                  _buildAddChildPage(context),
                  _buildEnableProtectionPage(context),
                ],
              ),
            ),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Row(
            children: List<Widget>.generate(_totalPages, (int index) {
              final bool isActive = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                margin: const EdgeInsets.only(right: 6),
                width: isActive ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const Spacer(),
          TextButton(
            onPressed: _skip,
            child: Text(
              'Skip',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePage(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 20),
      children: [
        Icon(
          Icons.shield_outlined,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Welcome to TrustBridge',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          'Set healthy digital boundaries for your family without surveillance or broken trust.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey.shade600,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 28),
        _featureRow(
          context,
          icon: Icons.lock_outline,
          title: 'Privacy-first',
          subtitle: 'Filtering happens on-device. No browsing content is sent.',
        ),
        const SizedBox(height: 14),
        _featureRow(
          context,
          icon: Icons.handshake_outlined,
          title: 'Transparent',
          subtitle: 'Children can understand what is paused and why.',
        ),
        const SizedBox(height: 14),
        _featureRow(
          context,
          icon: Icons.bolt_outlined,
          title: 'Instant',
          subtitle: 'Policy changes apply quickly to VPN protection.',
        ),
      ],
    );
  }

  Widget _buildAddChildPage(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 20),
      children: [
        Icon(
          Icons.child_care_outlined,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Add your first child',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          'Create one profile per child. TrustBridge starts with age-based defaults so setup is fast.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey.shade600,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 24),
        _ageBandRow(
          context,
          icon: Icons.shield_outlined,
          range: '6-9 years',
          description: 'Strict profile with stronger content boundaries',
        ),
        const SizedBox(height: 10),
        _ageBandRow(
          context,
          icon: Icons.track_changes_outlined,
          range: '10-13 years',
          description: 'Balanced profile for growing independence',
        ),
        const SizedBox(height: 10),
        _ageBandRow(
          context,
          icon: Icons.groups_outlined,
          range: '14-17 years',
          description: 'Lighter profile focused on high-risk content',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AddChildScreen(),
              ),
            );
            if (!mounted) {
              return;
            }
            _nextPage();
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Child Now'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _nextPage,
          child: Text(
            'I\'ll do this later',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  Widget _buildEnableProtectionPage(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 20),
      children: [
        Icon(
          Icons.security_outlined,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Enable protection',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          'TrustBridge uses local VPN mode to filter DNS safely on this device.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey.shade600,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 24),
        _stepRow(
          context,
          number: '1',
          label: 'Open Protection screen',
        ),
        const SizedBox(height: 10),
        _stepRow(
          context,
          number: '2',
          label: 'Tap "Enable Protection"',
        ),
        const SizedBox(height: 10),
        _stepRow(
          context,
          number: '3',
          label: 'Allow VPN permission when Android prompts',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const VpnProtectionScreen(),
              ),
            );
          },
          icon: const Icon(Icons.security),
          label: const Text('Open Protection Settings'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'You can always revisit this setup guide from Settings.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final bool isLastPage = _currentPage == _totalPages - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        children: [
          if (_currentPage > 0)
            TextButton(
              onPressed: _previousPage,
              child: const Text('Back'),
            )
          else
            const SizedBox(width: 60),
          const Spacer(),
          ElevatedButton(
            onPressed:
                _isCompleting ? null : (isLastPage ? _complete : _nextPage),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(128, 50),
            ),
            child: _isCompleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(isLastPage ? 'Get Started' : 'Next'),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
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
    );
  }

  Widget _ageBandRow(
    BuildContext context, {
    required IconData icon,
    required String range,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  range,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepRow(
    BuildContext context, {
    required String number,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
