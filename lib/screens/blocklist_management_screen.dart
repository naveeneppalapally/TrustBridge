import 'package:flutter/material.dart';

import '../core/utils/responsive.dart';
import '../models/blocklist_source.dart';
import '../services/blocklist_sync_service.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

class BlocklistManagementScreen extends StatefulWidget {
  const BlocklistManagementScreen({super.key});

  @override
  State<BlocklistManagementScreen> createState() =>
      _BlocklistManagementScreenState();
}

class _BlocklistManagementScreenState extends State<BlocklistManagementScreen> {
  final BlocklistSyncService _syncService = BlocklistSyncService();
  bool _loading = true;
  List<BlocklistSyncStatus> _statuses = const <BlocklistSyncStatus>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statuses = await _syncService.getStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _statuses = statuses;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(R.sp(8), R.sp(8), R.sp(8), 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(R.sp(20), R.sp(4), R.sp(20), 0),
              child: Text(
                'Open-Source Blocklists',
                style: AppTextStyles.displayMedium(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadStatuses,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    R.sp(20), 0, R.sp(20), R.sp(24),
                  ),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDim,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Automatic updates are on',
                            style: AppTextStyles.headingMedium(
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Blocklists refresh every day in the background. '
                            'You do not need to press Sync Now.',
                            style: AppTextStyles.bodySmall(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warningDim,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unable to load blocklist status right now.',
                              style: AppTextStyles.headingMedium(
                                color: AppColors.warning,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _error!,
                              style: AppTextStyles.bodySmall(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: _loadStatuses,
                              child: Text(
                                'Retry',
                                style: AppTextStyles.label(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._statuses.map(
                        (status) => _SourceStatusTile(status: status),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceStatusTile extends StatelessWidget {
  const _SourceStatusTile({required this.status});

  final BlocklistSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final syncedLabel = status.lastSynced == null
        ? 'Not synced yet'
        : '${localizations.formatMediumDate(status.lastSynced!)} '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(status.lastSynced!))}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iconFor(status.source.category),
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.source.name,
                  style: AppTextStyles.body(),
                ),
                const SizedBox(height: 1),
                Text(
                  '${status.domainCount} domains • Updated $syncedLabel',
                  style: AppTextStyles.bodySmall(
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            status.isStale
                ? Icons.error_outline
                : Icons.check_circle_outline,
            color: status.isStale ? AppColors.warning : AppColors.success,
            size: 18,
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
