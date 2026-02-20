import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/app_mode.dart';
import 'package:trustbridge_app/services/app_mode_service.dart';

/// Entry screen shown when device role mode is not selected yet.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _setModeAndNavigate(
    BuildContext context, {
    required AppMode mode,
    required String route,
  }) async {
    await AppModeService().setMode(mode);
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(
                Icons.shield_outlined,
                size: 72,
                color: Color(0xFF1E88E5),
              ),
              const SizedBox(height: 16),
              const Text(
                'TrustBridge',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Safer phones for your family',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () => _setModeAndNavigate(
                    context,
                    mode: AppMode.parent,
                    route: '/parent/login',
                  ),
                  child: const Text('Set up as Parent'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _setModeAndNavigate(
                    context,
                    mode: AppMode.child,
                    route: '/child/setup',
                  ),
                  child: const Text("I'm a Child"),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Already set up? Your device will remember your role.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
