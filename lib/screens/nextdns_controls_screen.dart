import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';

class NextDnsControlsScreen extends StatefulWidget {
  const NextDnsControlsScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.nextDnsApiService,
    this.parentIdOverride,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final NextDnsApiService? nextDnsApiService;
  final String? parentIdOverride;

  @override
  State<NextDnsControlsScreen> createState() => _NextDnsControlsScreenState();
}

class _NextDnsControlsScreenState extends State<NextDnsControlsScreen> {
  static const List<String> _serviceIds = <String>[
    'youtube',
    'instagram',
    'tiktok',
    'facebook',
    'netflix',
    'roblox',
  ];

  static const List<String> _categoryIds = <String>[
    'social-networks',
    'games',
    'porn',
    'gambling',
    'dating',
    'streaming',
  ];

  AuthService? _authService;
  FirestoreService? _firestoreService;
  NextDnsApiService? _nextDnsApiService;

  late Map<String, bool> _serviceToggles;
  late Map<String, bool> _categoryToggles;
  late bool _safeSearchEnabled;
  late bool _youtubeRestrictedModeEnabled;
  late bool _blockBypassEnabled;

  final List<_PendingWrite> _pendingWrites = <_PendingWrite>[];
  bool _busy = false;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  NextDnsApiService get _resolvedNextDnsApiService {
    _nextDnsApiService ??= widget.nextDnsApiService ?? NextDnsApiService();
    return _nextDnsApiService!;
  }

  String? get _parentId {
    final override = widget.parentIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return _resolvedAuthService.currentUser?.uid;
  }

  String? get _profileId {
    final value = widget.child.nextDnsProfileId?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    _serviceToggles = <String, bool>{
      for (final id in _serviceIds) id: false,
    };
    _categoryToggles = <String, bool>{
      for (final id in _categoryIds) id: false,
    };
    _safeSearchEnabled = widget.child.policy.safeSearchEnabled;
    _youtubeRestrictedModeEnabled = false;
    _blockBypassEnabled = true;
    _hydrateFromExistingControls();
  }

  void _hydrateFromExistingControls() {
    final controls = widget.child.nextDnsControls;
    final services = controls['services'];
    if (services is Map) {
      for (final entry in services.entries) {
        final key = entry.key.toString();
        if (_serviceToggles.containsKey(key)) {
          _serviceToggles[key] = entry.value == true;
        }
      }
    }
    final categories = controls['categories'];
    if (categories is Map) {
      for (final entry in categories.entries) {
        final key = entry.key.toString();
        if (_categoryToggles.containsKey(key)) {
          _categoryToggles[key] = entry.value == true;
        }
      }
    }
    _safeSearchEnabled =
        controls['safeSearchEnabled'] == true || _safeSearchEnabled;
    _youtubeRestrictedModeEnabled =
        controls['youtubeRestrictedModeEnabled'] == true;
    _blockBypassEnabled = controls['blockBypassEnabled'] != false;
  }

  Future<void> _persistControls() async {
    final parentId = _parentId;
    if (parentId == null) {
      return;
    }
    await _resolvedFirestoreService.saveChildNextDnsControls(
      parentId: parentId,
      childId: widget.child.id,
      controls: <String, dynamic>{
        'services': _serviceToggles,
        'categories': _categoryToggles,
        'safeSearchEnabled': _safeSearchEnabled,
        'youtubeRestrictedModeEnabled': _youtubeRestrictedModeEnabled,
        'blockBypassEnabled': _blockBypassEnabled,
        'updatedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> _runWrite(
    _PendingWrite write, {
    bool queueOnFailure = true,
  }) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });

    try {
      await write.run();
      await _persistControls();
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingWrites.removeWhere((item) => item.id == write.id);
        _busy = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        if (queueOnFailure &&
            !_pendingWrites.any((item) => item.id == write.id)) {
          _pendingWrites.add(write);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed. Saved for retry. ($error)'),
        ),
      );
    }
  }

  Future<void> _toggleService(String serviceId, bool blocked) async {
    final profileId = _profileId;
    if (profileId == null) {
      return;
    }
    final previous = _serviceToggles[serviceId] ?? false;
    setState(() {
      _serviceToggles[serviceId] = blocked;
    });
    final write = _PendingWrite(
      id: 'service:$serviceId',
      run: () => _resolvedNextDnsApiService.setServiceBlocked(
        profileId: profileId,
        serviceId: serviceId,
        blocked: blocked,
      ),
      rollback: () => setState(() {
        _serviceToggles[serviceId] = previous;
      }),
    );
    await _runWrite(write);
    if (_pendingWrites.any((item) => item.id == write.id)) {
      write.rollback();
    }
  }

  Future<void> _toggleCategory(String categoryId, bool blocked) async {
    final profileId = _profileId;
    if (profileId == null) {
      return;
    }
    final previous = _categoryToggles[categoryId] ?? false;
    setState(() {
      _categoryToggles[categoryId] = blocked;
    });
    final write = _PendingWrite(
      id: 'category:$categoryId',
      run: () => _resolvedNextDnsApiService.setCategoryBlocked(
        profileId: profileId,
        categoryId: categoryId,
        blocked: blocked,
      ),
      rollback: () => setState(() {
        _categoryToggles[categoryId] = previous;
      }),
    );
    await _runWrite(write);
    if (_pendingWrites.any((item) => item.id == write.id)) {
      write.rollback();
    }
  }

  Future<void> _toggleParentalControls({
    required bool? safeSearch,
    required bool? youtubeRestricted,
    required bool? blockBypass,
    required VoidCallback optimisticUpdate,
    required VoidCallback rollback,
    required String writeId,
  }) async {
    final profileId = _profileId;
    if (profileId == null) {
      return;
    }
    optimisticUpdate();

    final write = _PendingWrite(
      id: writeId,
      run: () => _resolvedNextDnsApiService.setParentalControlToggles(
        profileId: profileId,
        safeSearchEnabled: safeSearch,
        youtubeRestrictedModeEnabled: youtubeRestricted,
        blockBypassEnabled: blockBypass,
      ),
      rollback: rollback,
    );

    await _runWrite(write);
    if (_pendingWrites.any((item) => item.id == write.id)) {
      write.rollback();
    }
  }

  Future<void> _retryPendingWrites() async {
    if (_pendingWrites.isEmpty || _busy) {
      return;
    }
    final writes = List<_PendingWrite>.from(_pendingWrites);
    for (final write in writes) {
      await _runWrite(write, queueOnFailure: false);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingWrites.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Retry completed.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileId = _profileId;
    if (profileId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('NextDNS Controls')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This child is not linked to a NextDNS profile yet.\n'
              'Open NextDNS Setup first.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('NextDNS Controls'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.link),
              title: Text('${widget.child.nickname} profile'),
              subtitle: Text(profileId),
            ),
          ),
          if (_pendingWrites.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Card(
              color: Colors.orange.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.sync_problem, color: Colors.orange),
                title: Text('${_pendingWrites.length} changes pending sync'),
                subtitle: const Text('Retry to push failed writes to NextDNS'),
                trailing: TextButton(
                  onPressed: _busy ? null : _retryPendingWrites,
                  child: const Text('Retry'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _buildTogglesCard(
            title: 'Service Blocking',
            subtitle: 'Block specific services instantly.',
            values: _serviceToggles,
            onToggle: _toggleService,
          ),
          const SizedBox(height: 10),
          _buildTogglesCard(
            title: 'Category Blocking',
            subtitle: 'Apply category-level restrictions.',
            values: _categoryToggles,
            onToggle: _toggleCategory,
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  key: const Key('nextdns_safe_search_switch'),
                  title: const Text('SafeSearch'),
                  subtitle: const Text('Filter explicit search results'),
                  value: _safeSearchEnabled,
                  onChanged: _busy
                      ? null
                      : (value) {
                          final previous = _safeSearchEnabled;
                          _toggleParentalControls(
                            safeSearch: value,
                            youtubeRestricted: null,
                            blockBypass: null,
                            writeId: 'parental:safeSearch',
                            optimisticUpdate: () {
                              setState(() {
                                _safeSearchEnabled = value;
                              });
                            },
                            rollback: () {
                              setState(() {
                                _safeSearchEnabled = previous;
                              });
                            },
                          );
                        },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('nextdns_youtube_restricted_switch'),
                  title: const Text('YouTube Restricted Mode'),
                  subtitle: const Text('Limit mature content on YouTube'),
                  value: _youtubeRestrictedModeEnabled,
                  onChanged: _busy
                      ? null
                      : (value) {
                          final previous = _youtubeRestrictedModeEnabled;
                          _toggleParentalControls(
                            safeSearch: null,
                            youtubeRestricted: value,
                            blockBypass: null,
                            writeId: 'parental:youtubeRestrictedMode',
                            optimisticUpdate: () {
                              setState(() {
                                _youtubeRestrictedModeEnabled = value;
                              });
                            },
                            rollback: () {
                              setState(() {
                                _youtubeRestrictedModeEnabled = previous;
                              });
                            },
                          );
                        },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('nextdns_block_bypass_switch'),
                  title: const Text('Block Bypass'),
                  subtitle: const Text('Prevent simple DNS bypass tricks'),
                  value: _blockBypassEnabled,
                  onChanged: _busy
                      ? null
                      : (value) {
                          final previous = _blockBypassEnabled;
                          _toggleParentalControls(
                            safeSearch: null,
                            youtubeRestricted: null,
                            blockBypass: value,
                            writeId: 'parental:blockBypass',
                            optimisticUpdate: () {
                              setState(() {
                                _blockBypassEnabled = value;
                              });
                            },
                            rollback: () {
                              setState(() {
                                _blockBypassEnabled = previous;
                              });
                            },
                          );
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTogglesCard({
    required String title,
    required String subtitle,
    required Map<String, bool> values,
    required Future<void> Function(String id, bool enabled) onToggle,
  }) {
    final items = values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => SwitchListTile(
                key: Key('nextdns_toggle_${item.key}'),
                dense: true,
                title: Text(_prettyLabel(item.key)),
                value: item.value,
                onChanged: _busy ? null : (value) => onToggle(item.key, value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _prettyLabel(String raw) {
    return raw
        .split(RegExp(r'[-_]'))
        .where((word) => word.trim().isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}

class _PendingWrite {
  _PendingWrite({
    required this.id,
    required this.run,
    required this.rollback,
  });

  final String id;
  final Future<void> Function() run;
  final VoidCallback rollback;
}
