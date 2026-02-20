import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/feature_gates.dart';
import '../config/subscription_pricing.dart';
import '../services/subscription_service.dart';
import 'open_source_licenses_screen.dart';

/// TrustBridge Pro upgrade prompt shown for gated features.
class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({
    super.key,
    required this.triggeredBy,
    this.reason,
    this.subscriptionService,
  });

  final AppFeature triggeredBy;
  final String? reason;
  final SubscriptionService? subscriptionService;

  static final Set<AppFeature> _shownThisSession = <AppFeature>{};

  /// Shows upgrade prompt at most once per feature per app session.
  static Future<bool> maybeShow(
    BuildContext context, {
    required AppFeature feature,
    String? reason,
  }) async {
    if (_shownThisSession.contains(feature)) {
      return false;
    }
    _shownThisSession.add(feature);
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => UpgradeScreen(
          triggeredBy: feature,
          reason: reason,
        ),
      ),
    );
    return result == true;
  }

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  SubscriptionService? _subscriptionService;
  bool _yearlySelected = true;
  bool _startingTrial = false;

  SubscriptionService get _resolvedSubscriptionService {
    _subscriptionService ??=
        widget.subscriptionService ?? SubscriptionService();
    return _subscriptionService!;
  }

  @override
  Widget build(BuildContext context) {
    final reason = widget.reason ?? _defaultReason(widget.triggeredBy);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TrustBridge Pro'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upgrade to TrustBridge Pro',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    reason,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  const _BenefitRow(label: 'Unlimited children'),
                  const _BenefitRow(label: 'All content categories'),
                  const _BenefitRow(label: 'Smart schedules'),
                  const _BenefitRow(label: 'Bypass detection alerts'),
                  const _BenefitRow(label: 'Detailed usage reports'),
                  const _BenefitRow(label: 'Request and approve flow'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildPlanCard(
            title:
                'Rs ${SubscriptionPricing.yearlyInr} / year · Save ${SubscriptionPricing.yearlySavingsPercent}%',
            subtitle: 'Best value',
            selected: _yearlySelected,
            onTap: () => setState(() => _yearlySelected = true),
          ),
          const SizedBox(height: 10),
          _buildPlanCard(
            title: 'Rs ${SubscriptionPricing.monthlyInr} / month',
            subtitle: 'Flexible monthly billing',
            selected: !_yearlySelected,
            onTap: () => setState(() => _yearlySelected = false),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _startingTrial ? null : _startTrial,
              child: _startingTrial
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Start ${SubscriptionPricing.trialDays}-day free trial'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Maybe later'),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            children: [
              TextButton(
                onPressed: () => _showRestoreStub(context),
                child: const Text('Restore'),
              ),
              TextButton(
                onPressed: () => _openExternal(
                  context,
                  'https://trustbridge.app/terms',
                ),
                child: const Text('Terms'),
              ),
              TextButton(
                onPressed: () => _openExternal(
                  context,
                  'https://trustbridge.app/privacy',
                ),
                child: const Text('Privacy'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OpenSourceLicensesScreen(),
                  ),
                ),
                child: const Text('Licenses'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey.withValues(alpha: 0.35),
            width: selected ? 2 : 1,
          ),
          color: selected ? Colors.blue.withValues(alpha: 0.08) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? Colors.blue : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startTrial() async {
    setState(() {
      _startingTrial = true;
    });
    try {
      final started = await _resolvedSubscriptionService.startTrial();
      if (!mounted) {
        return;
      }
      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trial already used on this account.')),
        );
        setState(() {
          _startingTrial = false;
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Trial started. You have ${SubscriptionPricing.trialDays} days of Pro.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _startingTrial = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start trial right now.')),
      );
    }
  }

  String _defaultReason(AppFeature feature) {
    switch (feature) {
      case AppFeature.additionalChildren:
        return 'Adding more than one child profile requires TrustBridge Pro.';
      case AppFeature.categoryBlocking:
        return 'Advanced content categories require TrustBridge Pro.';
      case AppFeature.schedules:
        return 'Schedules require TrustBridge Pro.';
      case AppFeature.bypassAlerts:
        return 'Bypass alerts require TrustBridge Pro.';
      case AppFeature.fullReports:
        return 'Detailed reports require TrustBridge Pro.';
      case AppFeature.requestApproveFlow:
        return 'Request and approve flow requires TrustBridge Pro.';
      case AppFeature.nextDnsIntegration:
        return 'NextDNS integration requires TrustBridge Pro.';
    }
  }

  void _showRestoreStub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Restore purchases will be enabled after store approval.'),
      ),
    );
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open link right now.')),
      );
    }
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
