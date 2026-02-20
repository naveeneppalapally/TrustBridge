import 'package:flutter/material.dart';

import 'request_access_screen.dart';

/// Child-friendly full-screen message shown when an app is unavailable.
class BlockedOverlayScreen extends StatelessWidget {
  const BlockedOverlayScreen({
    super.key,
    required this.appName,
    this.modeName = 'Study Mode',
    this.untilLabel = '5:00 PM',
  });

  final String appName;
  final String modeName;
  final String untilLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📵', style: TextStyle(fontSize: 70)),
              const SizedBox(height: 16),
              Text(
                '$appName is off right now',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                '$modeName is active until $untilLabel',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            RequestAccessScreen(prefilledAppName: appName),
                      ),
                    );
                  },
                  icon: const Icon(Icons.volunteer_activism),
                  label: const Text('Ask to use it'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK, I understand'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
