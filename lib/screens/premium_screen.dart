import 'package:flutter/material.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({
    super.key,
    this.onClose,
  });

  final VoidCallback? onClose;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _yearlySelected = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            _buildTopBar(context),
            const SizedBox(height: 10),
            _buildHeaderCard(),
            const SizedBox(height: 14),
            _buildFeatureList(),
            const SizedBox(height: 14),
            _buildPricingCards(),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                key: const Key('premium_upgrade_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E86FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _yearlySelected
                            ? 'Starting yearly upgrade checkout...'
                            : 'Starting monthly upgrade checkout...',
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Upgrade Now >',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'RESTORE PURCHASE · TERMS · PRIVACY',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('premium_close_button'),
          onPressed: () {
            if (widget.onClose != null) {
              widget.onClose!();
              return;
            }
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.close),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE7F5ED),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'SAFE & SECURE',
            style: TextStyle(
              color: Color(0xFF0F9D58),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      key: const Key('premium_header_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5F3)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F2FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Color(0xFF2E86FF),
              size: 36,
            ),
          ),
          const SizedBox(height: 10),
          const Text.rich(
            TextSpan(
              text: 'TrustBridge ',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              children: [
                TextSpan(
                  text: 'Plus',
                  style: TextStyle(color: Color(0xFF2E86FF)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'PREMIUM PLAN',
              style: TextStyle(
                color: Color(0xFF2E86FF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureList() {
    const features = <_PremiumFeature>[
      _PremiumFeature(
        icon: Icons.family_restroom,
        title: 'Unlimited Children',
        subtitle: 'Protect every child profile in one family workspace.',
      ),
      _PremiumFeature(
        icon: Icons.analytics_outlined,
        title: 'Advanced Analytics',
        subtitle: 'View trends and insights across all children and devices.',
      ),
      _PremiumFeature(
        icon: Icons.category_outlined,
        title: 'Custom Categories',
        subtitle: 'Build category sets tailored to your family rules.',
      ),
      _PremiumFeature(
        icon: Icons.support_agent,
        title: 'Priority Support',
        subtitle: 'Get faster help when you need account or policy assistance.',
      ),
    ];

    return Card(
      key: const Key('premium_features_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: features
              .map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF3FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          feature.icon,
                          color: const Color(0xFF2E86FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              feature.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              feature.subtitle,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildPricingCards() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDDFBE8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'BEST VALUE',
              style: TextStyle(
                color: Color(0xFF0F9D58),
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _PricingCard(
          key: const Key('premium_yearly_plan_card'),
          selected: _yearlySelected,
          title: 'Yearly Plan',
          subtitle: 'INR 2999 / year · Save 40%',
          onTap: () {
            setState(() {
              _yearlySelected = true;
            });
          },
        ),
        const SizedBox(height: 10),
        _PricingCard(
          key: const Key('premium_monthly_plan_card'),
          selected: !_yearlySelected,
          title: 'Monthly Plan',
          subtitle: 'INR 299 / month',
          onTap: () {
            setState(() {
              _yearlySelected = false;
            });
          },
        ),
      ],
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF2E86FF) : const Color(0xFFDCE5F3),
            width: selected ? 1.8 : 1,
          ),
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
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? const Color(0xFF2E86FF) : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumFeature {
  const _PremiumFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}
