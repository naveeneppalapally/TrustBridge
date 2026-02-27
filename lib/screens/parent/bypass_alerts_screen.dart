import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/remote_command_service.dart';

/// Parent screen for bypass and protection alerts.
class BypassAlertsScreen extends StatefulWidget {
  const BypassAlertsScreen({
    super.key,
    this.authService,
    this.firestore,
    this.remoteCommandService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirebaseFirestore? firestore;
  final RemoteCommandService? remoteCommandService;
  final String? parentIdOverride;

  @override
  State<BypassAlertsScreen> createState() => _BypassAlertsScreenState();
}

class _BypassAlertsScreenState extends State<BypassAlertsScreen> {
  AuthService? _authService;
  FirebaseFirestore? _firestore;
  RemoteCommandService? _remoteCommandService;

  final Map<String, String> _commandStatusByAlertId = <String, String>{};
  final Map<String, StreamSubscription<CommandResult>> _commandSubscriptions =
      <String, StreamSubscription<CommandResult>>{};

  String _typeFilter = _allFilter;
  String _deviceFilter = _allFilter;
  bool _gateResolved = true;
  List<_BypassAlertItem> _lastLoadedAlerts = const <_BypassAlertItem>[];

  static const String _allFilter = '__all__';

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirebaseFirestore get _resolvedFirestore {
    _firestore ??= widget.firestore ?? FirebaseFirestore.instance;
    return _firestore!;
  }

  RemoteCommandService get _resolvedRemoteCommandService {
    _remoteCommandService ??=
        widget.remoteCommandService ?? RemoteCommandService();
    return _remoteCommandService!;
  }

  String? get _parentId {
    final override = widget.parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return _resolvedAuthService.currentUser?.uid;
  }

  @override
  void initState() {
    super.initState();
    _resolveGate();
  }

  @override
  void dispose() {
    for (final subscription in _commandSubscriptions.values) {
      subscription.cancel();
    }
    _commandSubscriptions.clear();
    super.dispose();
  }

  Future<void> _resolveGate() async {
    // Safety alerts must remain visible to all parents.
    if (!mounted) {
      return;
    }
    setState(() {
      _gateResolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Protection Alerts')),
        body: const Center(child: Text('Please sign in first.')),
      );
    }

    if (!_gateResolved) {
      return Scaffold(
        appBar: AppBar(title: const Text('Protection Alerts')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Protection Alerts'),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: StreamBuilder<List<_BypassAlertItem>>(
        stream: _watchAlerts(parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final errorText = _friendlyLoadError(snapshot.error);
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  errorText,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final allAlerts = snapshot.data ?? const <_BypassAlertItem>[];
          _lastLoadedAlerts = allAlerts;
          final unreadCount = allAlerts.where((alert) => !alert.read).length;
          final filteredAlerts = _applyFilters(allAlerts);

          if (allAlerts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No alerts yet - you\'ll be notified here if protection is turned off or bypassed.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final devices = <String>{
            for (final alert in allAlerts)
              if (alert.deviceId.trim().isNotEmpty) alert.deviceId.trim(),
          }.toList(growable: false)
            ..sort();
          final deviceLabels = <String, String>{
            for (final alert in allAlerts)
              if (alert.deviceId.trim().isNotEmpty)
                alert.deviceId.trim(): alert.childLabel,
          };

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildFilterChip(
                          icon: Icons.mark_email_unread_outlined,
                          label: '$unreadCount unread',
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          icon: Icons.notifications_active_outlined,
                          label: '${filteredAlerts.length} alerts',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTypeDropdown(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildDeviceDropdown(devices, deviceLabels),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filteredAlerts.isEmpty
                    ? const Center(child: Text('No alerts match this filter.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: filteredAlerts.length,
                        itemBuilder: (context, index) {
                          final alert = filteredAlerts[index];
                          final previousDeviceId = index == 0
                              ? null
                              : filteredAlerts[index - 1].deviceId;
                          final showDeviceHeader =
                              previousDeviceId != alert.deviceId;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showDeviceHeader)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(2, 2, 2, 8),
                                  child: Text(
                                    _deviceHeadingLabel(alert),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              _buildAlertCard(alert),
                              const SizedBox(height: 10),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Stream<List<_BypassAlertItem>> _watchAlerts(String parentId) async* {
    yield await _loadAlerts(parentId);
    yield* Stream<List<_BypassAlertItem>>.periodic(
      const Duration(seconds: 8),
    ).asyncMap((_) => _loadAlerts(parentId));
  }

  Future<List<_BypassAlertItem>> _loadAlerts(String parentId) async {
    final childNicknameById = <String, String>{};
    final deviceIds = <String>{};
    try {
      final parentChildrenSnapshot = await _resolvedFirestore
          .collection('children')
          .where('parentId', isEqualTo: parentId)
          .get();
      for (final childDoc in parentChildrenSnapshot.docs) {
        final childId = childDoc.id.trim();
        final data = childDoc.data();
        final nickname = (data['nickname'] as String?)?.trim();
        if (childId.isNotEmpty && nickname != null && nickname.isNotEmpty) {
          childNicknameById[childId] = nickname;
        }

        final rawDeviceIds = data['deviceIds'];
        if (rawDeviceIds is List) {
          for (final rawDeviceId in rawDeviceIds) {
            final deviceId = rawDeviceId?.toString().trim() ?? '';
            if (deviceId.isNotEmpty) {
              deviceIds.add(deviceId);
            }
          }
        }

        final rawDeviceMetadata = data['deviceMetadata'];
        if (rawDeviceMetadata is Map) {
          for (final entry in rawDeviceMetadata.entries) {
            final deviceId = entry.key.toString().trim();
            if (deviceId.isNotEmpty) {
              deviceIds.add(deviceId);
            }
          }
        }
      }

      // Fallback for older records that only populated children/{id}/devices.
      if (deviceIds.isEmpty) {
        for (final childDoc in parentChildrenSnapshot.docs) {
          try {
            final devicesSnapshot =
                await childDoc.reference.collection('devices').limit(20).get();
            for (final deviceDoc in devicesSnapshot.docs) {
              final deviceId = deviceDoc.id.trim();
              if (deviceId.isNotEmpty) {
                deviceIds.add(deviceId);
              }
            }
          } catch (_) {
            // Continue collecting devices from other children.
          }
        }
      }
    } catch (_) {
      // Child/device discovery failed; return empty state instead of hard error.
      return const <_BypassAlertItem>[];
    }

    if (deviceIds.isEmpty) {
      return const <_BypassAlertItem>[];
    }

    final alerts = <_BypassAlertItem>[];
    final seenDocPaths = <String>{};

    void appendSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
      for (final doc in snapshot.docs) {
        final path = doc.reference.path;
        if (seenDocPaths.contains(path)) {
          continue;
        }
        seenDocPaths.add(path);
        alerts.add(_BypassAlertItem.fromDoc(doc, childNicknameById));
      }
    }

    for (final deviceId in deviceIds) {
      try {
        final primarySnapshot = await _resolvedFirestore
            .collection('bypass_events')
            .doc(deviceId)
            .collection('events')
            .where('parentId', isEqualTo: parentId)
            .limit(160)
            .get();
        appendSnapshot(primarySnapshot);

        if (primarySnapshot.docs.isNotEmpty) {
          continue;
        }

        // Fallback for older events that may be missing parentId.
        final legacySnapshot = await _resolvedFirestore
            .collection('bypass_events')
            .doc(deviceId)
            .collection('events')
            .limit(80)
            .get();
        appendSnapshot(legacySnapshot);
      } catch (_) {
        // Continue gathering from other devices.
      }
    }

    alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (alerts.length > 200) {
      return alerts.take(200).toList(growable: false);
    }
    return alerts;
  }

  String _friendlyLoadError(Object? error) {
    final raw = error?.toString() ?? 'unknown';
    final lower = raw.toLowerCase();
    if (lower.contains('permission-denied') ||
        lower.contains('permission denied') ||
        lower.contains('cloud_permission')) {
      return 'Alerts unavailable right now. Please try again in a moment.';
    }
    return 'Alerts unavailable right now. Please try again in a moment.';
  }

  Widget _buildFilterChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeDropdown() {
    final options = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: _allFilter,
        child: Text('All'),
      ),
      ..._BypassAlertItem.supportedTypes.map(
        (type) => DropdownMenuItem<String>(
          value: type,
          child: Text(_BypassAlertItem.labelForType(type)),
        ),
      ),
    ];

    return DropdownButtonFormField<String>(
      initialValue: _typeFilter,
      decoration: const InputDecoration(
        labelText: 'Filter',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: options,
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() {
          _typeFilter = value;
        });
      },
    );
  }

  Widget _buildDeviceDropdown(
    List<String> devices,
    Map<String, String> deviceLabels,
  ) {
    final options = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: _allFilter,
        child: Text('All devices'),
      ),
      ...devices.map(
        (deviceId) => DropdownMenuItem<String>(
          value: deviceId,
          child: Text(
            (deviceLabels[deviceId] ?? '').trim().isEmpty
                ? 'Child device'
                : '${deviceLabels[deviceId]} device',
          ),
        ),
      ),
    ];

    if (_deviceFilter != _allFilter && !devices.contains(_deviceFilter)) {
      _deviceFilter = _allFilter;
    }

    return DropdownButtonFormField<String>(
      initialValue: _deviceFilter,
      decoration: const InputDecoration(
        labelText: 'Device',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: options,
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() {
          _deviceFilter = value;
        });
      },
    );
  }

  String _deviceHeadingLabel(_BypassAlertItem alert) {
    final childLabel = alert.childLabel.trim();
    if (childLabel.isNotEmpty) {
      return '$childLabel device';
    }
    return 'Child device';
  }

  Widget _buildAlertCard(_BypassAlertItem alert) {
    final severityColor = _BypassAlertItem.severityColor(alert.type);
    final severityIcon = _BypassAlertItem.severityIcon(alert.type);
    final commandStatus = _commandStatusByAlertId[alert.id];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(severityIcon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _BypassAlertItem.labelForType(alert.type),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (!alert.read)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: severityColor,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${alert.childLabel} - ${_formatAlertTime(context, alert.timestamp)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (alert.type == 'vpn_disabled')
                  FilledButton.tonal(
                    onPressed: _isRestartActionLocked(commandStatus)
                        ? null
                        : () => _restartProtection(alert),
                    child: Text(_restartButtonText(commandStatus)),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _showContactHint(alert.childLabel),
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Contact Child'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: alert.read ? null : () => _markAlertRead(alert),
                  child: const Text('Mark read'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_BypassAlertItem> _applyFilters(List<_BypassAlertItem> source) {
    return source.where((alert) {
      final matchesType =
          _typeFilter == _allFilter || alert.type == _typeFilter;
      final matchesDevice =
          _deviceFilter == _allFilter || alert.deviceId == _deviceFilter;
      return matchesType && matchesDevice;
    }).toList(growable: false);
  }

  bool _isRestartActionLocked(String? commandStatus) {
    return commandStatus == 'sending' ||
        commandStatus == 'pending' ||
        commandStatus == 'executed';
  }

  String _restartButtonText(String? commandStatus) {
    switch (commandStatus) {
      case 'sending':
      case 'pending':
        return 'Sending command...';
      case 'executed':
        return 'Restarted';
      case 'failed':
        return 'Could not restart';
      default:
        return 'Restart Protection';
    }
  }

  Future<void> _restartProtection(_BypassAlertItem alert) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _commandStatusByAlertId[alert.id] = 'sending';
    });

    try {
      final commandId = await _resolvedRemoteCommandService
          .sendRestartVpnCommand(alert.deviceId);
      final previousSubscription = _commandSubscriptions.remove(alert.id);
      await previousSubscription?.cancel();

      _commandSubscriptions[alert.id] = _resolvedRemoteCommandService
          .watchCommandResult(commandId)
          .listen((result) {
        if (!mounted) {
          return;
        }
        setState(() {
          _commandStatusByAlertId[alert.id] = result.status;
        });
        if (result.status == 'executed' || result.status == 'failed') {
          final done = _commandSubscriptions.remove(alert.id);
          done?.cancel();
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _commandStatusByAlertId[alert.id] = 'failed';
      });
    }
  }

  Future<void> _markAlertRead(_BypassAlertItem alert) async {
    try {
      await alert.reference.set(
        <String, dynamic>{
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _markAllRead() async {
    try {
      final unreadAlerts = _lastLoadedAlerts
          .where((alert) => !alert.read)
          .toList(growable: false);
      if (unreadAlerts.isEmpty) {
        return;
      }

      WriteBatch batch = _resolvedFirestore.batch();
      var batchCount = 0;
      for (final alert in unreadAlerts) {
        batch.set(
          alert.reference,
          <String, dynamic>{
            'read': true,
            'readAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        batchCount++;
        if (batchCount == 400) {
          await batch.commit();
          batch = _resolvedFirestore.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) {
        await batch.commit();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark all alerts as read.')),
      );
    }
  }

  void _showContactHint(String childLabel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Talk with $childLabel about this event.')),
    );
  }

  String _formatAlertTime(BuildContext context, DateTime timestamp) {
    if (timestamp.millisecondsSinceEpoch <= 0) {
      return 'just now';
    }

    final now = DateTime.now();
    final date = DateUtils.dateOnly(timestamp);
    final today = DateUtils.dateOnly(now);
    final timeLabel = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(timestamp));

    if (date == today) {
      return 'Today $timeLabel';
    }
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $timeLabel';
    }
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    return '$day/$month $timeLabel';
  }
}

class _BypassAlertItem {
  const _BypassAlertItem({
    required this.id,
    required this.type,
    required this.deviceId,
    required this.childId,
    required this.childLabel,
    required this.timestamp,
    required this.read,
    required this.reference,
  });

  final String id;
  final String type;
  final String deviceId;
  final String childId;
  final String childLabel;
  final DateTime timestamp;
  final bool read;
  final DocumentReference<Map<String, dynamic>> reference;

  static const List<String> supportedTypes = <String>[
    'uninstall_attempt',
    'vpn_disabled',
    'private_dns_changed',
    'device_offline_30m',
    'device_offline_24h',
  ];

  static _BypassAlertItem fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, [
    Map<String, String>? fallbackChildLabelById,
  ]) {
    final fallbackLabels = fallbackChildLabelById ?? const <String, String>{};
    final data = doc.data();
    final type = (data['type'] as String?)?.trim();
    final timestamp = _readDateTime(data['timestamp']) ??
        DateTime.fromMillisecondsSinceEpoch(
          _readInt(data['timestampEpochMs']),
        );
    final deviceId = (data['deviceId'] as String?)?.trim().isNotEmpty == true
        ? (data['deviceId'] as String).trim()
        : (doc.reference.parent.parent?.id ?? 'Unknown device');
    final childId = (data['childId'] as String?)?.trim() ?? '';
    final childNickname = (data['childNickname'] as String?)?.trim();
    final fallbackChildLabel = fallbackLabels[childId]?.trim();

    return _BypassAlertItem(
      id: doc.id,
      type: type == null || type.isEmpty ? 'unknown' : type,
      deviceId: deviceId,
      childId: childId,
      childLabel: (childNickname != null && childNickname.isNotEmpty)
          ? childNickname
          : (fallbackChildLabel != null && fallbackChildLabel.isNotEmpty)
              ? fallbackChildLabel
              : 'Child device',
      timestamp: timestamp,
      read: data['read'] == true,
      reference: doc.reference,
    );
  }

  static String labelForType(String type) {
    switch (type) {
      case 'uninstall_attempt':
        return 'Uninstall attempt';
      case 'vpn_disabled':
        return 'Protection turned off';
      case 'private_dns_changed':
        return 'Network settings changed';
      case 'device_offline_30m':
        return 'Device not seen recently';
      case 'device_offline_24h':
        return 'Device offline for 24+ hours';
      default:
        return 'Protection event';
    }
  }

  static String severityIcon(String type) {
    switch (type) {
      case 'uninstall_attempt':
      case 'device_offline_24h':
        return 'CRITICAL';
      case 'vpn_disabled':
      case 'device_offline_30m':
        return 'WARNING';
      case 'private_dns_changed':
        return 'INFO';
      default:
        return 'ALERT';
    }
  }

  static Color severityColor(String type) {
    switch (type) {
      case 'uninstall_attempt':
      case 'device_offline_24h':
        return Colors.red;
      case 'vpn_disabled':
      case 'device_offline_30m':
        return Colors.orange;
      case 'private_dns_changed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  static DateTime? _readDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return null;
  }

  static int _readInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return 0;
  }
}
