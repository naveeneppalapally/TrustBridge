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
    final categoryLabels = blockedCategories
        .map(_categoryLabel)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final appLabels = blockedAppKeys
        .map(_appLabel)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('What Is Blocked'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SectionCard(
            title: 'Blocked categories',
            child: categoryLabels.isEmpty
                ? const Text('No blocked categories right now.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categoryLabels
                        .map(
                          (label) => Chip(
                            label: Text(label),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Blocked apps',
            child: appLabels.isEmpty
                ? const Text('No blocked apps right now.')
                : Column(
                    children: appLabels
                        .map(
                          (label) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.block, color: Colors.red),
                            title: Text(label),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Blocked websites',
            child: Text(
              '$blockedDomainsCount website domains are currently blocked.',
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String id) {
    final normalized = id.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    switch (normalized) {
      case '__block_all__':
        return 'All Internet';
      case 'social-networks':
        return 'Social Media';
      case 'adult-content':
        return 'Adult Content';
      case 'games':
        return 'Gaming';
      case 'streaming':
        return 'Streaming';
      default:
        return normalized
            .split(RegExp(r'[_\s-]+'))
            .where((part) => part.isNotEmpty)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');
    }
  }

  String _appLabel(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    return normalized
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
