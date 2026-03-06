import 'package:flutter/material.dart';

class BlockedDetailsScreen extends StatelessWidget {
  const BlockedDetailsScreen({
    super.key,
    required this.blockedCategories,
    required this.blockedAppKeys,
    required this.blockedDomainsCount,
  });

  final List<String> blockedCategories;
  final List<String> blockedAppKeys;
  final int blockedDomainsCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryTile(
            label: 'Blocked categories',
            value: blockedCategories.length.toString(),
          ),
          _SummaryTile(
            label: 'Blocked apps',
            value: blockedAppKeys.length.toString(),
          ),
          _SummaryTile(
            label: 'Blocked domains',
            value: blockedDomainsCount.toString(),
          ),
          if (blockedCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Categories',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...blockedCategories.map((category) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.block_outlined),
                  title: Text(category),
                )),
          ],
          if (blockedAppKeys.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Apps',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...blockedAppKeys.map((appKey) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.apps_outlined),
                  title: Text(appKey),
                )),
          ],
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
