import 'package:flutter/material.dart';

/// Child-facing list of apps that are currently off limits.
class BlockedAppsList extends StatelessWidget {
  const BlockedAppsList({
    super.key,
    required this.blockedAppKeys,
    this.reasonsByAppKey = const <String, String>{},
    this.onAppTap,
  });

  /// Canonical app keys (e.g. instagram, tiktok).
  final List<String> blockedAppKeys;
  final Map<String, String> reasonsByAppKey;

  /// Optional app tap callback with friendly app name.
  final void Function(String appName)? onAppTap;

  static const Map<String, String> _apps = {
    'instagram': 'Instagram',
    'tiktok': 'TikTok',
    'twitter': 'Twitter / X',
    'snapchat': 'Snapchat',
    'facebook': 'Facebook',
    'youtube': 'YouTube',
    'reddit': 'Reddit',
    'roblox': 'Roblox',
    'zee5': 'ZEE5',
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
              final appName = _apps[key] ?? _toLabel(key);
              final reason = reasonsByAppKey[key]?.trim() ?? '';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.14),
                  child: Text(
                    appName.isEmpty ? '?' : appName[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(appName),
                subtitle: reason.isEmpty ? null : Text(reason),
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
