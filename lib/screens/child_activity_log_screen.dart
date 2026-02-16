import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trustbridge_app/models/child_profile.dart';

class ChildActivityLogScreen extends StatelessWidget {
  const ChildActivityLogScreen({
    super.key,
    required this.child,
  });

  final ChildProfile child;

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();

    return Scaffold(
      appBar: AppBar(
        title: Text('${child.nickname} Activity'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Recent Activity',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Latest profile and policy activity for ${child.nickname}.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No activity yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ),
            )
          else
            ...entries.map(
              (entry) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(entry.icon, size: 18),
                  ),
                  title: Text(entry.title),
                  subtitle: Text(entry.subtitle),
                  trailing: Text(
                    DateFormat('MMM d, h:mm a').format(entry.time),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_ActivityEntry> _buildEntries() {
    final list = <_ActivityEntry>[
      _ActivityEntry(
        time: child.createdAt,
        icon: Icons.person_add_alt_1,
        title: 'Profile created',
        subtitle: '${child.nickname} profile was added to TrustBridge.',
      ),
      _ActivityEntry(
        time: child.updatedAt,
        icon: Icons.settings_suggest_outlined,
        title: 'Policy updated',
        subtitle:
            '${child.policy.blockedCategories.length} categories blocked, ${child.policy.schedules.length} schedules active.',
      ),
      _ActivityEntry(
        time: child.updatedAt,
        icon: Icons.devices_outlined,
        title: 'Device links reviewed',
        subtitle:
            '${child.deviceIds.length} ${child.deviceIds.length == 1 ? 'device' : 'devices'} linked.',
      ),
    ];

    final pausedUntil = child.pausedUntil;
    if (pausedUntil != null) {
      final now = DateTime.now();
      if (pausedUntil.isAfter(now)) {
        list.add(
          _ActivityEntry(
            time: now,
            icon: Icons.pause_circle_outline,
            title: 'Internet paused',
            subtitle:
                'Pause active until ${DateFormat('MMM d, h:mm a').format(pausedUntil)}.',
          ),
        );
      } else {
        list.add(
          _ActivityEntry(
            time: pausedUntil,
            icon: Icons.play_circle_outline,
            title: 'Internet pause ended',
            subtitle: 'Pause ended automatically.',
          ),
        );
      }
    }

    list.sort((a, b) => b.time.compareTo(a.time));
    return list;
  }
}

class _ActivityEntry {
  _ActivityEntry({
    required this.time,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final DateTime time;
  final IconData icon;
  final String title;
  final String subtitle;
}
