import 'package:flutter/material.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

class DomainPolicyTesterScreen extends StatefulWidget {
  const DomainPolicyTesterScreen({
    super.key,
    this.vpnService,
  });

  final VpnServiceBase? vpnService;

  @override
  State<DomainPolicyTesterScreen> createState() =>
      _DomainPolicyTesterScreenState();
}

class _DomainPolicyTesterScreenState extends State<DomainPolicyTesterScreen> {
  late final VpnServiceBase _vpnService;
  final TextEditingController _domainController = TextEditingController();

  bool _isEvaluating = false;
  DomainPolicyEvaluation? _evaluation;

  static const List<String> _quickChecks = [
    'facebook.com',
    'm.instagram.com',
    'youtube.com',
    'reddit.com',
    'google.com',
  ];

  @override
  void initState() {
    super.initState();
    _vpnService = widget.vpnService ?? VpnService();
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Domain Policy Tester'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Check Native Rule Match',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'This checks the native rule cache directly and shows whether a domain is blocked.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('domain_tester_input'),
            controller: _domainController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Domain',
              hintText: 'e.g. youtube.com',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _evaluateDomain(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('domain_tester_run_button'),
            onPressed: _isEvaluating ? null : _evaluateDomain,
            icon: _isEvaluating
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.rule),
            label: Text(_isEvaluating ? 'Checking...' : 'Evaluate Domain'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickChecks
                .map(
                  (domain) => ActionChip(
                    key: Key('domain_tester_chip_$domain'),
                    label: Text(domain),
                    onPressed: _isEvaluating
                        ? null
                        : () {
                            _domainController.text = domain;
                            _evaluateDomain();
                          },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (_evaluation != null) _buildResultCard(context, _evaluation!),
        ],
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, DomainPolicyEvaluation eval) {
    final blocked = eval.blocked;
    final color = blocked ? Colors.red.shade700 : Colors.green.shade700;
    final icon = blocked ? Icons.block : Icons.check_circle;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  blocked ? 'Blocked by Policy' : 'Allowed by Policy',
                  key: const Key('domain_tester_result_header'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _metric(context, 'Input', eval.inputDomain),
            _metric(context, 'Normalized', eval.normalizedDomain),
            _metric(context, 'Matched Rule', eval.matchedRule ?? 'None'),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 98,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _evaluateDomain() async {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a domain to evaluate.'),
        ),
      );
      return;
    }

    setState(() => _isEvaluating = true);
    try {
      final evaluation = await _vpnService.evaluateDomainPolicy(domain);
      if (!mounted) {
        return;
      }
      if (evaluation.inputDomain.isEmpty &&
          evaluation.normalizedDomain.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Unable to evaluate this domain on current platform.'),
          ),
        );
        return;
      }
      setState(() => _evaluation = evaluation);
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }
}
