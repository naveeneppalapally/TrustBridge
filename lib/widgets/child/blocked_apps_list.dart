import 'package:flutter/material.dart';

/// Child-facing list of apps that are currently off limits.
class BlockedAppsList extends StatelessWidget {
  const BlockedAppsList({
    super.key,
    required this.blockedAppKeys,
    this.onAppTap,
  });

  /// Canonical app keys (e.g. instagram, tiktok).
  final List<String> blockedAppKeys;

  /// Optional app tap callback with friendly app name.
  final void Function(String appName)? onAppTap;

  static const Map<String, ({String emoji, String name})> _apps = {
    'instagram': (emoji: '📸', name: 'Instagram'),
    'tiktok': (emoji: '🎵', name: 'TikTok'),
    'twitter': (emoji: '🐦', name: 'Twitter / X'),
    'snapchat': (emoji: '👻', name: 'Snapchat'),
    'facebook': (emoji: '👥', name: 'Facebook'),
    'youtube': (emoji: '▶️', name: 'YouTube'),
    'reddit': (emoji: '🤖', name: 'Reddit'),
    'roblox': (emoji: '🎮', name: 'Roblox'),
  };

  @override
  Widget build(BuildContext context) {
    final normalized = blockedAppKeys
        .map((key) => key.trim().toLowerCase())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    final visible = normalized.take(5).toList(growable: false);
    final remaining = normalized.length > 5 ? normalized.length - 5 : 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Taking a break from:',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            Text(
              'No apps are paused right now.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else
            ...visible.map((key) {
              final mapping = _apps[key];
              final appName = mapping?.name ?? _toLabel(key);
              final emoji = mapping?.emoji ?? '📱';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('$emoji $appName'),
                onTap: onAppTap == null ? null : () => onAppTap!(appName),
              );
            }),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '...and $remaining more',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  String _toLabel(String key) {
    if (key.isEmpty) {
      return 'Unknown app';
    }
    return key
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
