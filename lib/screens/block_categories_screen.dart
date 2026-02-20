import 'package:flutter/material.dart';
import 'package:trustbridge_app/config/feature_gates.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/content_categories.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/screens/upgrade_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/feature_gate_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/nextdns_api_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';
import 'package:trustbridge_app/utils/parent_pin_gate.dart';
import 'package:trustbridge_app/widgets/empty_state.dart';

class BlockCategoriesScreen extends StatefulWidget {
  const BlockCategoriesScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.vpnService,
    this.nextDnsApiService,
    this.parentIdOverride,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final VpnServiceBase? vpnService;
  final NextDnsApiService? nextDnsApiService;
  final String? parentIdOverride;

  @override
  State<BlockCategoriesScreen> createState() => _BlockCategoriesScreenState();
}

class _BlockCategoriesScreenState extends State<BlockCategoriesScreen> {
  static const List<String> _nextDnsServiceIds = <String>[
    'youtube',
    'instagram',
    'tiktok',
    'facebook',
    'netflix',
    'roblox',
  ];

  static const Map<String, String> _localToNextDnsCategoryMap =
      <String, String>{
    'social-networks': 'social-networks',
    'games': 'games',
    'streaming': 'streaming',
    'adult-content': 'porn',
  };

  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;
  NextDnsApiService? _nextDnsApiService;
  final FeatureGateService _featureGateService = FeatureGateService();

  late final Set<String> _initialBlockedCategories;
  late final Set<String> _initialBlockedDomains;
  late Set<String> _blockedCategories;
  late Set<String> _blockedDomains;
  late Map<String, bool> _nextDnsServiceToggles;
  late bool _nextDnsSafeSearchEnabled;
  late bool _nextDnsYoutubeRestrictedModeEnabled;
  late bool _nextDnsBlockBypassEnabled;

  bool _isLoading = false;
  bool _isSyncingNextDns = false;
  String _query = '';

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  VpnServiceBase get _resolvedVpnService {
    _vpnService ??= widget.vpnService ?? VpnService();
    return _vpnService!;
  }

  NextDnsApiService get _resolvedNextDnsApiService {
    _nextDnsApiService ??= widget.nextDnsApiService ?? NextDnsApiService();
    return _nextDnsApiService!;
  }

  String? get _nextDnsProfileId {
    final value = widget.child.nextDnsProfileId?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  bool get _hasNextDnsProfile => _nextDnsProfileId != null;

  bool get _hasChanges {
    return !_setEquals(_initialBlockedCategories, _blockedCategories) ||
        !_setEquals(_initialBlockedDomains, _blockedDomains);
  }

  int get _blockedKnownCategoryCount {
    final knownIds = ContentCategories.allCategories.map((c) => c.id).toSet();
    return _blockedCategories.where(knownIds.contains).length;
  }

  List<ContentCategory> get _visibleCategories {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return ContentCategories.allCategories;
    }
    return ContentCategories.allCategories.where((category) {
      final haystack = '${category.name} ${category.description}'.toLowerCase();
      return haystack.contains(normalized);
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _initialBlockedCategories = widget.child.policy.blockedCategories.toSet();
    _initialBlockedDomains = widget.child.policy.blockedDomains.toSet();
    _blockedCategories = widget.child.policy.blockedCategories.toSet();
    _blockedDomains = widget.child.policy.blockedDomains.toSet();
    _nextDnsServiceToggles = <String, bool>{
      for (final id in _nextDnsServiceIds) id: false,
    };
    _nextDnsSafeSearchEnabled = widget.child.policy.safeSearchEnabled;
    _nextDnsYoutubeRestrictedModeEnabled = false;
    _nextDnsBlockBypassEnabled = true;
    _hydrateNextDnsControls();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Blocking'),
      ),
      bottomNavigationBar: _hasChanges ? _buildSaveBar() : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            key: const Key('block_categories_search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search categories or apps',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'APP CATEGORIES',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 10),
          if (_query.trim().isEmpty && _blockedKnownCategoryCount == 0) ...[
            Card(
              key: const Key('block_categories_empty_state'),
              margin: const EdgeInsets.only(bottom: 12),
              child: EmptyState(
                icon: const Text('\u{1F6E1}'),
                title: 'No categories blocked',
                subtitle: 'Toggle categories to start filtering.',
                actionLabel: 'Block First Category',
                onAction: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _blockedCategories
                              .add(ContentCategories.allCategories.first.id);
                        });
                      },
              ),
            ),
          ],
          if (_visibleCategories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No categories match your search.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            )
          else
            ..._visibleCategories
                .map((category) => _buildCategoryCard(category)),
          const SizedBox(height: 18),
          Text(
            'CUSTOM BLOCKED SITES',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 10),
          ..._buildCustomDomains(),
          const SizedBox(height: 10),
          _buildAddDomainButton(),
          if (_hasNextDnsProfile) ...[
            const SizedBox(height: 18),
            _buildNextDnsCard(context),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryCard(ContentCategory category) {
    final isBlocked = _blockedCategories.contains(category.id);
    final iconColor = _categoryColor(category.id);
    final enforcementBadge = _buildEnforcementBadgeForCategory(category.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(category.icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (enforcementBadge != null) enforcementBadge,
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _categoryExamples(category.id),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: isBlocked,
              onChanged: _isLoading || _isSyncingNextDns
                  ? null
                  : (enabled) => _toggleCategoryWithPin(
                        categoryId: category.id,
                        enabled: enabled,
                      ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCustomDomains() {
    final sorted = _blockedDomains.toList()..sort();
    if (sorted.isEmpty) {
      return [
        Text(
          'No custom blocked sites yet.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ];
    }

    return sorted
        .map(
          (domain) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.public_rounded, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(domain),
                ),
                _buildInstantBadge(),
                const SizedBox(width: 8),
                InkWell(
                  key: Key('custom_domain_remove_$domain'),
                  onTap: _isLoading || _isSyncingNextDns
                      ? null
                      : () => _removeDomain(domain),
                  child: const Icon(Icons.remove_circle_outline, size: 20),
                ),
              ],
            ),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildAddDomainButton() {
    return InkWell(
      key: const Key('block_categories_add_domain'),
      onTap: _isLoading || _isSyncingNextDns ? null : _showAddDomainDialog,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.55),
            style: BorderStyle.solid,
          ),
        ),
        child: const Text(
          '+ Add Custom Site',
          style: TextStyle(
            color: Color(0xFF207CF8),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
              top: BorderSide(color: Colors.grey.withValues(alpha: 0.25))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Safe Mode Active - $_blockedKnownCategoryCount Categories Restricted',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              key: const Key('block_categories_save_button'),
              onPressed:
                  (_isLoading || _isSyncingNextDns) ? null : _saveChanges,
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDomainDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Custom Site'),
          content: TextField(
            key: const Key('block_categories_domain_input'),
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'e.g., reddit.com',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('block_categories_add_domain_confirm'),
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (value == null || value.isEmpty) {
      return;
    }
    final normalized = _normalizeDomain(value);
    if (!_isValidDomain(normalized)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid domain, e.g. reddit.com')),
      );
      return;
    }

    setState(() {
      _blockedDomains.add(normalized);
    });
    await _syncNextDnsDomain(normalized, blocked: true);
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final parentId =
          widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
      if (parentId == null) {
        throw Exception('Not logged in');
      }

      final updatedPolicy = widget.child.policy.copyWith(
        blockedCategories: _orderedBlockedCategories(_blockedCategories),
        blockedDomains: _orderedBlockedDomains(_blockedDomains),
      );
      final updatedChild = widget.child.copyWith(
        policy: updatedPolicy,
        nextDnsControls: _hasNextDnsProfile
            ? _buildNextDnsControlsPayload()
            : widget.child.nextDnsControls,
      );

      await _resolvedFirestoreService.updateChild(
        parentId: parentId,
        child: updatedChild,
      );
      await _syncVpnRulesIfRunning(updatedPolicy);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category blocks updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(updatedChild);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save Failed'),
          content: Text('Failed to update categories: $error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _toggleCategoryWithPin({
    required String categoryId,
    required bool enabled,
  }) async {
    if (_isProOnlyCategory(categoryId)) {
      final gate = await () async {
        try {
          return await _featureGateService
              .checkGate(AppFeature.categoryBlocking);
        } catch (_) {
          // Fail-open for non-Firebase test contexts.
          return const GateResult(allowed: true);
        }
      }();
      if (!gate.allowed) {
        if (mounted) {
          await UpgradeScreen.maybeShow(
            context,
            feature: AppFeature.categoryBlocking,
            reason: gate.upgradeReason,
          );
        }
        return;
      }
    }

    if (!mounted) {
      return;
    }
    final authorized = await requireParentPin(context);
    if (!authorized) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Parent PIN required to change protection.')),
      );
      return;
    }

    setState(() {
      if (enabled) {
        _blockedCategories.add(categoryId);
      } else {
        _blockedCategories.remove(categoryId);
      }
    });
    await _syncNextDnsCategoryForLocalToggle(
      localCategoryId: categoryId,
      blocked: enabled,
    );
  }

  bool _isProOnlyCategory(String categoryId) {
    return categoryId == 'adult-content' ||
        categoryId == 'gambling' ||
        categoryId == 'malware';
  }

  Future<void> _syncVpnRulesIfRunning(Policy updatedPolicy) async {
    try {
      final status = await _resolvedVpnService.getStatus();
      if (!status.supported || !status.isRunning) {
        return;
      }

      await _resolvedVpnService.updateFilterRules(
        blockedCategories: updatedPolicy.blockedCategories,
        blockedDomains: updatedPolicy.blockedDomains,
      );
    } catch (_) {
      // Saving policy should still succeed if runtime VPN sync is unavailable.
    }
  }

  String _normalizeDomain(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.startsWith('http://')) {
      normalized = normalized.substring(7);
    } else if (normalized.startsWith('https://')) {
      normalized = normalized.substring(8);
    }
    if (normalized.startsWith('www.')) {
      normalized = normalized.substring(4);
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _isValidDomain(String value) {
    final pattern = RegExp(r'^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$');
    return pattern.hasMatch(value) && !value.contains('..');
  }

  String _categoryExamples(String categoryId) {
    switch (categoryId) {
      case 'social-networks':
        return 'Instagram, TikTok, Snapchat';
      case 'games':
        return 'Roblox, Minecraft, Fortnite';
      case 'streaming':
        return 'YouTube, Twitch, Netflix';
      case 'adult-content':
        return 'Adult websites and explicit portals';
      case 'shopping':
        return 'Amazon, Flipkart, Myntra';
      default:
        final category = ContentCategories.findById(categoryId);
        return category?.description ?? 'Restricted by policy';
    }
  }

  Color _categoryColor(String categoryId) {
    switch (categoryId) {
      case 'social-networks':
        return const Color(0xFF1E88E5);
      case 'games':
        return const Color(0xFF2E7D32);
      case 'streaming':
        return const Color(0xFFD32F2F);
      case 'adult-content':
        return const Color(0xFFF57C00);
      case 'shopping':
        return const Color(0xFFF9A825);
      default:
        final category = ContentCategories.findById(categoryId);
        return category?.riskLevel.color ?? Colors.blueGrey;
    }
  }

  List<String> _orderedBlockedCategories(Set<String> selectedIds) {
    final knownOrder = ContentCategories.allCategories
        .where((category) => selectedIds.contains(category.id))
        .map((category) => category.id)
        .toList(growable: false);

    final extras = selectedIds
        .where((id) => !ContentCategories.allCategories.any((c) => c.id == id))
        .toList()
      ..sort();
    return [...knownOrder, ...extras];
  }

  List<String> _orderedBlockedDomains(Set<String> selectedDomains) {
    final ordered = selectedDomains.map(_normalizeDomain).toSet().toList();
    ordered.sort();
    return ordered;
  }

  bool _setEquals(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final value in left) {
      if (!right.contains(value)) {
        return false;
      }
    }
    return true;
  }

  void _hydrateNextDnsControls() {
    final controls = widget.child.nextDnsControls;
    final services = controls['services'];
    if (services is Map) {
      for (final entry in services.entries) {
        final key = entry.key.toString();
        if (_nextDnsServiceToggles.containsKey(key)) {
          _nextDnsServiceToggles[key] = entry.value == true;
        }
      }
    }
    _nextDnsSafeSearchEnabled =
        controls['safeSearchEnabled'] == true || _nextDnsSafeSearchEnabled;
    _nextDnsYoutubeRestrictedModeEnabled =
        controls['youtubeRestrictedModeEnabled'] == true;
    _nextDnsBlockBypassEnabled = controls['blockBypassEnabled'] != false;
  }

  Map<String, dynamic> _buildNextDnsControlsPayload() {
    final categories = <String, bool>{};
    for (final entry in _localToNextDnsCategoryMap.entries) {
      categories[entry.value] = _blockedCategories.contains(entry.key);
    }

    return <String, dynamic>{
      'services': _nextDnsServiceToggles,
      'categories': categories,
      'safeSearchEnabled': _nextDnsSafeSearchEnabled,
      'youtubeRestrictedModeEnabled': _nextDnsYoutubeRestrictedModeEnabled,
      'blockBypassEnabled': _nextDnsBlockBypassEnabled,
      'updatedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> _persistNextDnsControlsOnly() async {
    final profileId = _nextDnsProfileId;
    final parentId =
        widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
    if (profileId == null || parentId == null) {
      return;
    }
    await _resolvedFirestoreService.saveChildNextDnsControls(
      parentId: parentId,
      childId: widget.child.id,
      controls: _buildNextDnsControlsPayload(),
    );
  }

  Future<void> _syncNextDnsCategoryForLocalToggle({
    required String localCategoryId,
    required bool blocked,
  }) async {
    final profileId = _nextDnsProfileId;
    final nextDnsCategoryId = _localToNextDnsCategoryMap[localCategoryId];
    if (profileId == null || nextDnsCategoryId == null) {
      return;
    }

    try {
      setState(() => _isSyncingNextDns = true);
      await _resolvedNextDnsApiService.setCategoryBlocked(
        profileId: profileId,
        categoryId: nextDnsCategoryId,
        blocked: blocked,
      );
      await _persistNextDnsControlsOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'NextDNS category sync failed for $_prettyLabel(localCategoryId): $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingNextDns = false);
      }
    }
  }

  Future<void> _syncNextDnsDomain(String domain,
      {required bool blocked}) async {
    final profileId = _nextDnsProfileId;
    if (profileId == null) {
      return;
    }

    try {
      setState(() => _isSyncingNextDns = true);
      if (blocked) {
        await _resolvedNextDnsApiService.addToDenylist(
          profileId: profileId,
          domain: domain,
        );
      } else {
        await _resolvedNextDnsApiService.removeFromDenylist(
          profileId: profileId,
          domain: domain,
        );
      }
      await _persistNextDnsControlsOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? 'NextDNS denylist add failed for $domain: $error'
                : 'NextDNS denylist remove failed for $domain: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingNextDns = false);
      }
    }
  }

  Future<void> _toggleNextDnsService(String serviceId, bool blocked) async {
    final profileId = _nextDnsProfileId;
    if (profileId == null) {
      return;
    }
    final previous = _nextDnsServiceToggles[serviceId] ?? false;
    setState(() {
      _nextDnsServiceToggles[serviceId] = blocked;
      _isSyncingNextDns = true;
    });

    try {
      await _resolvedNextDnsApiService.setServiceBlocked(
        profileId: profileId,
        serviceId: serviceId,
        blocked: blocked,
      );
      await _persistNextDnsControlsOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nextDnsServiceToggles[serviceId] = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('NextDNS service sync failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingNextDns = false);
      }
    }
  }

  Future<void> _toggleNextDnsParental({
    required bool? safeSearch,
    required bool? youtubeRestricted,
    required bool? blockBypass,
    required VoidCallback optimisticUpdate,
    required VoidCallback rollback,
  }) async {
    final profileId = _nextDnsProfileId;
    if (profileId == null) {
      return;
    }
    optimisticUpdate();
    setState(() => _isSyncingNextDns = true);

    try {
      await _resolvedNextDnsApiService.setParentalControlToggles(
        profileId: profileId,
        safeSearchEnabled: safeSearch,
        youtubeRestrictedModeEnabled: youtubeRestricted,
        blockBypassEnabled: blockBypass,
      );
      await _persistNextDnsControlsOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      rollback();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('NextDNS parental controls sync failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingNextDns = false);
      }
    }
  }

  Future<void> _removeDomain(String domain) async {
    setState(() {
      _blockedDomains.remove(domain);
    });
    await _syncNextDnsDomain(domain, blocked: false);
  }

  Widget _buildNextDnsCard(BuildContext context) {
    final profileId = _nextDnsProfileId!;
    final serviceEntries = _nextDnsServiceToggles.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      key: const Key('block_categories_nextdns_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEXTDNS LIVE CONTROLS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Profile: $profileId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 10),
            ...serviceEntries.map(
              (entry) => SwitchListTile(
                key: Key('nextdns_service_switch_${entry.key}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_prettyLabel(entry.key)),
                value: entry.value,
                onChanged: _isLoading || _isSyncingNextDns
                    ? null
                    : (value) => _toggleNextDnsService(entry.key, value),
              ),
            ),
            const Divider(),
            SwitchListTile(
              key: const Key('nextdns_safe_search_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('SafeSearch'),
              subtitle: const Text('Filter explicit search results'),
              value: _nextDnsSafeSearchEnabled,
              onChanged: _isLoading || _isSyncingNextDns
                  ? null
                  : (value) {
                      final previous = _nextDnsSafeSearchEnabled;
                      _toggleNextDnsParental(
                        safeSearch: value,
                        youtubeRestricted: null,
                        blockBypass: null,
                        optimisticUpdate: () => setState(() {
                          _nextDnsSafeSearchEnabled = value;
                        }),
                        rollback: () => setState(() {
                          _nextDnsSafeSearchEnabled = previous;
                        }),
                      );
                    },
            ),
            SwitchListTile(
              key: const Key('nextdns_youtube_restricted_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('YouTube Restricted Mode'),
              subtitle: const Text('Limit mature content on YouTube'),
              value: _nextDnsYoutubeRestrictedModeEnabled,
              onChanged: _isLoading || _isSyncingNextDns
                  ? null
                  : (value) {
                      final previous = _nextDnsYoutubeRestrictedModeEnabled;
                      _toggleNextDnsParental(
                        safeSearch: null,
                        youtubeRestricted: value,
                        blockBypass: null,
                        optimisticUpdate: () => setState(() {
                          _nextDnsYoutubeRestrictedModeEnabled = value;
                        }),
                        rollback: () => setState(() {
                          _nextDnsYoutubeRestrictedModeEnabled = previous;
                        }),
                      );
                    },
            ),
            SwitchListTile(
              key: const Key('nextdns_block_bypass_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Block Bypass'),
              subtitle: const Text('Prevent simple DNS bypass tricks'),
              value: _nextDnsBlockBypassEnabled,
              onChanged: _isLoading || _isSyncingNextDns
                  ? null
                  : (value) {
                      final previous = _nextDnsBlockBypassEnabled;
                      _toggleNextDnsParental(
                        safeSearch: null,
                        youtubeRestricted: null,
                        blockBypass: value,
                        optimisticUpdate: () => setState(() {
                          _nextDnsBlockBypassEnabled = value;
                        }),
                        rollback: () => setState(() {
                          _nextDnsBlockBypassEnabled = previous;
                        }),
                      );
                    },
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

  Widget? _buildEnforcementBadgeForCategory(String categoryId) {
    if (_isInstantCategory(categoryId)) {
      return _buildInstantBadge();
    }
    if (_isNextDnsCategory(categoryId)) {
      return _buildNextDnsBadge();
    }
    return null;
  }

  bool _isInstantCategory(String categoryId) {
    return categoryId == 'social-networks';
  }

  bool _isNextDnsCategory(String categoryId) {
    return categoryId == 'adult-content' ||
        categoryId == 'gambling' ||
        categoryId == 'malware';
  }

  Widget _buildInstantBadge() {
    return Tooltip(
      message: 'Changes apply in under 1 second',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          '\u26a1 Instant',
          style: TextStyle(
            color: Colors.green,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildNextDnsBadge() {
    final enabled = _hasNextDnsProfile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: enabled ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '\u2601\ufe0f NextDNS',
        style: TextStyle(
          color: enabled ? Colors.blue.shade700 : Colors.blueGrey,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
