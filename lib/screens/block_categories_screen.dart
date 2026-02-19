import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/content_categories.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';
import 'package:trustbridge_app/widgets/empty_state.dart';

class BlockCategoriesScreen extends StatefulWidget {
  const BlockCategoriesScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.vpnService,
    this.parentIdOverride,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final VpnServiceBase? vpnService;
  final String? parentIdOverride;

  @override
  State<BlockCategoriesScreen> createState() => _BlockCategoriesScreenState();
}

class _BlockCategoriesScreenState extends State<BlockCategoriesScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  VpnServiceBase? _vpnService;

  late final Set<String> _initialBlockedCategories;
  late final Set<String> _initialBlockedDomains;
  late Set<String> _blockedCategories;
  late Set<String> _blockedDomains;

  bool _isLoading = false;
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
        ],
      ),
    );
  }

  Widget _buildCategoryCard(ContentCategory category) {
    final isBlocked = _blockedCategories.contains(category.id);
    final iconColor = _categoryColor(category.id);

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
                  Text(
                    category.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
              onChanged: _isLoading
                  ? null
                  : (enabled) {
                      setState(() {
                        if (enabled) {
                          _blockedCategories.add(category.id);
                        } else {
                          _blockedCategories.remove(category.id);
                        }
                      });
                    },
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
                InkWell(
                  key: Key('custom_domain_remove_$domain'),
                  onTap: _isLoading
                      ? null
                      : () => setState(() {
                            _blockedDomains.remove(domain);
                          }),
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
      onTap: _isLoading ? null : _showAddDomainDialog,
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
              onPressed: _isLoading ? null : _saveChanges,
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
      final updatedChild = widget.child.copyWith(policy: updatedPolicy);

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
}
