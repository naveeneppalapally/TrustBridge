import 'package:flutter/material.dart';

import '../models/blocklist_source.dart';
import '../services/blocklist_sync_service.dart';

/// Displays current blocklist sync status and manual sync action.
class BlocklistStatusCard extends StatelessWidget {
  /// Creates a blocklist status card.
  const BlocklistStatusCard({
    super.key,
    required this.statuses,
    required this.isSyncing,
    required this.onSyncNow,
  });

  /// Source status list to render.
  final List<BlocklistSyncStatus> statuses;

  /// Whether a sync operation is currently running.
  final bool isSyncing;

  /// Callback fired when user taps sync.
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync_outlined),
                const SizedBox(width: 8),
                Text(
                  'Open-Source Blocklists',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'StevenBlack sources synced to local protection database.',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (statuses.isEmpty)
              const Text('No blocklist sources configured.')
            else
              ...statuses.map((status) => _StatusRow(status: status)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: isSyncing ? null : onSyncNow,
                icon: isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(isSyncing ? 'Syncing...' : 'Sync Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status});

  final BlocklistSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final isStale = status.isStale;
    final colorScheme = Theme.of(context).colorScheme;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    final lastSyncedLabel = status.lastSynced == null
        ? 'Never synced'
        : '${localizations.formatMediumDate(status.lastSynced!)} '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(status.lastSynced!))}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
            foregroundColor: colorScheme.primary,
            child: Icon(
              _iconFor(status.source.category),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.source.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${status.domainCount} domains • $lastSyncedLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurfaceVariant,
                  ),
                ),
                if (isStale) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Stale: sync recommended',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(BlocklistCategory category) {
    switch (category) {
      case BlocklistCategory.social:
        return Icons.people_alt_outlined;
      case BlocklistCategory.ads:
        return Icons.campaign_outlined;
      case BlocklistCategory.malware:
        return Icons.security_outlined;
      case BlocklistCategory.adult:
        return Icons.visibility_off_outlined;
      case BlocklistCategory.gambling:
        return Icons.casino_outlined;
    }
  }
}
