import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/content_categories.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';
import 'package:trustbridge_app/services/vpn_service.dart';

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
  late Set<String> _blockedCategories;

  bool _isLoading = false;

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

  bool get _hasChanges =>
      !_setEquals(_initialBlockedCategories, _blockedCategories);

  int get _knownBlockedCount {
    final knownIds = ContentCategories.allCategories.map((c) => c.id).toSet();
    return _blockedCategories.where(knownIds.contains).length;
  }

  @override
  void initState() {
    super.initState();
    _initialBlockedCategories = widget.child.policy.blockedCategories.toSet();
    _blockedCategories = widget.child.policy.blockedCategories.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Block Categories'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveChanges,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'SAVE',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Choose Content to Block',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_knownBlockedCount of ${ContentCategories.allCategories.length} categories blocked',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _selectAll,
                  icon: const Icon(Icons.check_box_outlined, size: 18),
                  label: const Text('Select All'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _clearAll,
                  icon: const Icon(Icons.check_box_outline_blank, size: 18),
                  label: const Text('Clear All'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildCategorySection(
            context,
            title: 'High Risk',
            subtitle: 'Recommended to block for all children',
            categories: ContentCategories.highRisk,
          ),
          const SizedBox(height: 20),
          _buildCategorySection(
            context,
            title: 'Medium Risk',
            subtitle: 'Age-dependent, based on child maturity',
            categories: ContentCategories.mediumRisk,
          ),
          const SizedBox(height: 20),
          _buildCategorySection(
            context,
            title: 'Low Risk',
            subtitle: 'Optional based on family preference',
            categories: ContentCategories.lowRisk,
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<ContentCategory> categories,
  }) {
    final color = categories.first.riskLevel.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...categories.map((category) => _buildCategoryTile(context, category)),
      ],
    );
  }

  Widget _buildCategoryTile(BuildContext context, ContentCategory category) {
    final isBlocked = _blockedCategories.contains(category.id);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
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
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: category.riskLevel.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            category.icon,
            color: category.riskLevel.color,
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(category.description),
      ),
    );
  }

  void _selectAll() {
    setState(() {
      _blockedCategories = ContentCategories.allCategories
          .map((category) => category.id)
          .toSet();
    });
  }

  void _clearAll() {
    if (_blockedCategories.isEmpty) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear All Categories?'),
          content: const Text(
            'This will unblock all content categories. Your child may get unrestricted access to all content types.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _blockedCategories.clear();
                });
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
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
        builder: (context) {
          return AlertDialog(
            title: const Text('Save Failed'),
            content: Text('Failed to update categories: $error'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
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
      // Saving policy should succeed even if VPN sync is unavailable.
    }
  }

  List<String> _orderedBlockedCategories(Set<String> selectedIds) {
    final knownOrder = ContentCategories.allCategories
        .where((category) => selectedIds.contains(category.id))
        .map((category) => category.id)
        .toList();

    final extras = selectedIds
        .where((id) => !ContentCategories.allCategories
            .any((category) => category.id == id))
        .toList()
      ..sort();

    return [...knownOrder, ...extras];
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
