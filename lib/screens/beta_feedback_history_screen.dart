import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/support_ticket.dart';
import 'package:trustbridge_app/screens/beta_feedback_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

enum _TicketSourceFilter {
  beta,
  support,
  all;

  String get label {
    switch (this) {
      case _TicketSourceFilter.beta:
        return 'Beta';
      case _TicketSourceFilter.support:
        return 'Support';
      case _TicketSourceFilter.all:
        return 'All';
    }
  }
}

enum _TicketSortOrder {
  newestFirst,
  oldestFirst,
  highestSeverity,
  highestDuplicateCluster;

  String get label {
    switch (this) {
      case _TicketSortOrder.newestFirst:
        return 'Newest';
      case _TicketSortOrder.oldestFirst:
        return 'Oldest';
      case _TicketSortOrder.highestSeverity:
        return 'Severity';
      case _TicketSortOrder.highestDuplicateCluster:
        return 'Dup clusters';
    }
  }
}

enum _AttentionFilter {
  all,
  attention,
  stale;

  String get label {
    switch (this) {
      case _AttentionFilter.all:
        return 'All urgency';
      case _AttentionFilter.attention:
        return 'Needs attention';
      case _AttentionFilter.stale:
        return 'Stale 72h+';
    }
  }
}

enum _DuplicateFilter {
  all,
  duplicates;

  String get label {
    switch (this) {
      case _DuplicateFilter.all:
        return 'All reports';
      case _DuplicateFilter.duplicates:
        return 'Duplicates';
    }
  }
}

class BetaFeedbackHistoryScreen extends StatefulWidget {
  const BetaFeedbackHistoryScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<BetaFeedbackHistoryScreen> createState() =>
      _BetaFeedbackHistoryScreenState();
}

class _BetaFeedbackHistoryScreenState extends State<BetaFeedbackHistoryScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  Stream<List<SupportTicket>>? _ticketStream;
  String? _streamParentId;

  final TextEditingController _searchController = TextEditingController();

  _TicketSourceFilter _sourceFilter = _TicketSourceFilter.beta;
  SupportTicketStatus? _statusFilter;
  SupportTicketSeverity? _severityFilter;
  _AttentionFilter _attentionFilter = _AttentionFilter.all;
  _DuplicateFilter _duplicateFilter = _DuplicateFilter.all;
  _TicketSortOrder _sortOrder = _TicketSortOrder.newestFirst;
  String _searchQuery = '';

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  String? get _parentId {
    return widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
  }

  Stream<List<SupportTicket>> _getTicketStream(String parentId) {
    if (_ticketStream == null || _streamParentId != parentId) {
      _streamParentId = parentId;
      _ticketStream =
          _resolvedFirestoreService.getSupportTicketsStream(parentId);
    }
    return _ticketStream!;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshStream() {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return;
    }
    setState(() {
      _streamParentId = null;
      _ticketStream = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parentId = _parentId;
    if (parentId == null || parentId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Feedback History')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback History'),
        actions: [
          IconButton(
            key: const Key('feedback_history_refresh_button'),
            onPressed: _refreshStream,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: StreamBuilder<List<SupportTicket>>(
        stream: _getTicketStream(parentId),
        builder: (BuildContext context,
            AsyncSnapshot<List<SupportTicket>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          final tickets = snapshot.data ?? const <SupportTicket>[];
          if (tickets.isEmpty) {
            return _buildEmptyState(hasAnyTickets: false);
          }

          final duplicateCounts = _duplicateCountsByKey(tickets);
          final filteredTickets = _applyFilters(tickets, duplicateCounts);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              _buildFilterCard(
                tickets: tickets,
                filteredCount: filteredTickets.length,
                duplicateCounts: duplicateCounts,
              ),
              const SizedBox(height: 12),
              if (filteredTickets.isEmpty)
                _buildEmptyState(hasAnyTickets: true)
              else
                ...filteredTickets.map((ticket) {
                  final duplicateCount =
                      duplicateCounts[ticket.duplicateKey] ?? 1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildTicketCard(
                      ticket,
                      duplicateCount: duplicateCount,
                    ),
                  );
                }),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('feedback_history_new_button'),
        onPressed: _openFeedbackForm,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Send Feedback'),
      ),
    );
  }

  List<SupportTicket> _applyFilters(
    List<SupportTicket> tickets,
    Map<String, int> duplicateCounts,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    final now = DateTime.now();

    final filtered = tickets.where((ticket) {
      switch (_sourceFilter) {
        case _TicketSourceFilter.beta:
          if (!ticket.isBetaFeedback) {
            return false;
          }
          break;
        case _TicketSourceFilter.support:
          if (ticket.isBetaFeedback) {
            return false;
          }
          break;
        case _TicketSourceFilter.all:
          break;
      }

      if (_statusFilter != null && ticket.status != _statusFilter) {
        return false;
      }

      if (_severityFilter != null && ticket.severity != _severityFilter) {
        return false;
      }

      switch (_duplicateFilter) {
        case _DuplicateFilter.all:
          break;
        case _DuplicateFilter.duplicates:
          if ((duplicateCounts[ticket.duplicateKey] ?? 0) < 2) {
            return false;
          }
          break;
      }

      switch (_attentionFilter) {
        case _AttentionFilter.all:
          break;
        case _AttentionFilter.attention:
          if (!ticket.needsAttention(now: now)) {
            return false;
          }
          break;
        case _AttentionFilter.stale:
          if (!ticket.isStale(now: now)) {
            return false;
          }
          break;
      }

      if (query.isNotEmpty) {
        final subject = ticket.subject.toLowerCase();
        final message = ticket.message.toLowerCase();
        final childId = (ticket.childId ?? '').toLowerCase();
        if (!subject.contains(query) &&
            !message.contains(query) &&
            !childId.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    switch (_sortOrder) {
      case _TicketSortOrder.newestFirst:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _TicketSortOrder.oldestFirst:
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _TicketSortOrder.highestSeverity:
        filtered.sort((a, b) {
          final severityComparison = a.severity.rank.compareTo(b.severity.rank);
          if (severityComparison != 0) {
            return severityComparison;
          }
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case _TicketSortOrder.highestDuplicateCluster:
        filtered.sort((a, b) {
          final aCluster = duplicateCounts[a.duplicateKey] ?? 1;
          final bCluster = duplicateCounts[b.duplicateKey] ?? 1;
          final clusterComparison = bCluster.compareTo(aCluster);
          if (clusterComparison != 0) {
            return clusterComparison;
          }

          final severityComparison = a.severity.rank.compareTo(b.severity.rank);
          if (severityComparison != 0) {
            return severityComparison;
          }

          return b.createdAt.compareTo(a.createdAt);
        });
        break;
    }

    return filtered;
  }

  Widget _buildFilterCard({
    required List<SupportTicket> tickets,
    required int filteredCount,
    required Map<String, int> duplicateCounts,
  }) {
    final now = DateTime.now();
    final openCount = tickets
        .where((ticket) => ticket.status == SupportTicketStatus.open)
        .length;
    final inProgressCount = tickets
        .where((ticket) => ticket.status == SupportTicketStatus.inProgress)
        .length;
    final criticalCount = tickets
        .where((ticket) => ticket.severity == SupportTicketSeverity.critical)
        .length;
    final attentionCount =
        tickets.where((ticket) => ticket.needsAttention(now: now)).length;
    final staleCount =
        tickets.where((ticket) => ticket.isStale(now: now)).length;
    final duplicateTicketsCount = duplicateCounts.values
        .where((count) => count > 1)
        .fold<int>(0, (total, count) => total + count);
    final duplicateClusterCount =
        duplicateCounts.values.where((count) => count > 1).length;
    final largestClusterSize = duplicateCounts.values.isEmpty
        ? 1
        : duplicateCounts.values.reduce((a, b) => a > b ? a : b);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Triage',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMetricPill(
                  label: 'Open',
                  value: '$openCount',
                  color: Colors.orange.shade700,
                ),
                _buildMetricPill(
                  label: 'In Progress',
                  value: '$inProgressCount',
                  color: Colors.blue.shade700,
                ),
                _buildMetricPill(
                  label: 'Critical',
                  value: '$criticalCount',
                  color: Colors.red.shade700,
                ),
                _buildMetricPill(
                  label: 'Attention',
                  value: '$attentionCount',
                  color: Colors.deepPurple.shade700,
                ),
                _buildMetricPill(
                  label: 'Stale 72h+',
                  value: '$staleCount',
                  color: Colors.brown.shade700,
                ),
                _buildMetricPill(
                  label: 'Dup clusters',
                  value: '$duplicateClusterCount',
                  color: Colors.deepPurple.shade700,
                ),
                _buildMetricPill(
                  label: 'Dup reports',
                  value: '$duplicateTicketsCount',
                  color: Colors.indigo.shade700,
                ),
                _buildMetricPill(
                  label: 'Largest cluster',
                  value: '$largestClusterSize',
                  color: Colors.deepPurple.shade400,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _TicketSourceFilter.values.map((filter) {
                final selected = _sourceFilter == filter;
                return ChoiceChip(
                  key: Key('feedback_history_source_${filter.name}'),
                  label: Text(filter.label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _sourceFilter = filter;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('feedback_history_status_all'),
                  label: const Text('All statuses'),
                  selected: _statusFilter == null,
                  onSelected: (_) {
                    setState(() {
                      _statusFilter = null;
                    });
                  },
                ),
                ...[
                  SupportTicketStatus.open,
                  SupportTicketStatus.inProgress,
                  SupportTicketStatus.resolved,
                  SupportTicketStatus.closed,
                ].map((status) {
                  return ChoiceChip(
                    key: Key('feedback_history_status_${status.name}'),
                    label: Text(status.label),
                    selected: _statusFilter == status,
                    onSelected: (_) {
                      setState(() {
                        _statusFilter = status;
                      });
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('feedback_history_severity_all'),
                  label: const Text('All severities'),
                  selected: _severityFilter == null,
                  onSelected: (_) {
                    setState(() {
                      _severityFilter = null;
                    });
                  },
                ),
                ...[
                  SupportTicketSeverity.critical,
                  SupportTicketSeverity.high,
                  SupportTicketSeverity.medium,
                  SupportTicketSeverity.low,
                ].map((severity) {
                  return ChoiceChip(
                    key: Key('feedback_history_severity_${severity.name}'),
                    label: Text(severity.label),
                    selected: _severityFilter == severity,
                    onSelected: (_) {
                      setState(() {
                        _severityFilter = severity;
                      });
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _DuplicateFilter.values.map((filter) {
                return ChoiceChip(
                  key: Key('feedback_history_duplicate_${filter.name}'),
                  label: Text(filter.label),
                  selected: _duplicateFilter == filter,
                  onSelected: (_) {
                    setState(() {
                      _duplicateFilter = filter;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _AttentionFilter.values.map((filter) {
                return ChoiceChip(
                  key: Key('feedback_history_attention_${filter.name}'),
                  label: Text(filter.label),
                  selected: _attentionFilter == filter,
                  onSelected: (_) {
                    setState(() {
                      _attentionFilter = filter;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _TicketSortOrder.values.map((order) {
                return ChoiceChip(
                  key: Key('feedback_history_sort_${order.name}'),
                  label: Text(order.label),
                  selected: _sortOrder == order,
                  onSelected: (_) {
                    setState(() {
                      _sortOrder = order;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('feedback_history_search_input'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search subject, details, or child id',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Showing $filteredCount of ${tickets.length} tickets',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Unable to load feedback history',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('feedback_history_retry_button'),
              onPressed: _refreshStream,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool hasAnyTickets}) {
    if (!hasAnyTickets) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.forum_outlined,
                size: 64,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 16),
              const Text(
                'No feedback yet',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Send your first feedback to help improve TrustBridge before beta.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('feedback_history_empty_cta'),
                onPressed: _openFeedbackForm,
                child: const Text('Send your first feedback'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.filter_alt_off, size: 40, color: Colors.blueGrey),
            const SizedBox(height: 10),
            const Text(
              'No tickets match these filters',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different status, source, or search term.',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            TextButton(
              key: const Key('feedback_history_clear_filters'),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _sourceFilter = _TicketSourceFilter.beta;
                  _statusFilter = null;
                  _severityFilter = null;
                  _duplicateFilter = _DuplicateFilter.all;
                  _attentionFilter = _AttentionFilter.all;
                  _sortOrder = _TicketSortOrder.newestFirst;
                  _searchQuery = '';
                });
              },
              child: const Text('Reset filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketCard(
    SupportTicket ticket, {
    required int duplicateCount,
  }) {
    final color = _statusColor(ticket.status);
    final similarCount = duplicateCount - 1;
    return Card(
      key: Key('feedback_history_ticket_${ticket.id}'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openTicketDetails(
          ticket,
          duplicateCount: duplicateCount,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.subject,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildStatusChip(ticket.status, color),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ticket.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildSourceChip(ticket),
                  if (ticket.severity != SupportTicketSeverity.unknown) ...[
                    const SizedBox(width: 8),
                    _buildSeverityChip(ticket.severity),
                  ],
                  if (similarCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildDuplicateChip(similarCount),
                  ],
                  if (ticket.isStale()) ...[
                    const SizedBox(width: 8),
                    _buildAgingChip(
                        label: 'Stale', color: Colors.brown.shade700),
                  ] else if (ticket.needsAttention()) ...[
                    const SizedBox(width: 8),
                    _buildAgingChip(
                      label: 'Needs attention',
                      color: Colors.deepPurple.shade700,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(Icons.schedule, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _formatTimestamp(ticket.createdAt),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (ticket.childId != null) ...[
                    Icon(Icons.child_care,
                        size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      ticket.childId!,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceChip(SupportTicket ticket) {
    final isBeta = ticket.isBetaFeedback;
    final color = isBeta ? Colors.teal : Colors.indigo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ticket.source.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatusChip(SupportTicketStatus status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSeverityChip(SupportTicketSeverity severity) {
    final color = _severityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        severity.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMetricPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildAgingChip({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDuplicateChip(int similarCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$similarCount similar',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.indigo.shade700,
        ),
      ),
    );
  }

  Future<void> _openTicketDetails(
    SupportTicket ticket, {
    required int duplicateCount,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final color = _statusColor(ticket.status);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ticket Details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ticket.subject,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _buildStatusChip(ticket.status, color),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildSourceChip(ticket),
                      if (ticket.severity != SupportTicketSeverity.unknown) ...[
                        const SizedBox(width: 8),
                        _buildSeverityChip(ticket.severity),
                      ],
                      if (duplicateCount > 1) ...[
                        const SizedBox(width: 8),
                        _buildDuplicateChip(duplicateCount - 1),
                      ],
                      if (ticket.isStale()) ...[
                        const SizedBox(width: 8),
                        _buildAgingChip(
                          label: 'Stale',
                          color: Colors.brown.shade700,
                        ),
                      ] else if (ticket.needsAttention()) ...[
                        const SizedBox(width: 8),
                        _buildAgingChip(
                          label: 'Needs attention',
                          color: Colors.deepPurple.shade700,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Created: ${_formatTimestamp(ticket.createdAt)}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Updated: ${_formatTimestamp(ticket.updatedAt)}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  if (ticket.childId != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Child: ${ticket.childId}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Message',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(ticket.message),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFeedbackForm() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BetaFeedbackScreen(
          authService: widget.authService,
          firestoreService: widget.firestoreService,
          parentIdOverride: widget.parentIdOverride,
        ),
      ),
    );
  }

  Color _statusColor(SupportTicketStatus status) {
    switch (status) {
      case SupportTicketStatus.open:
        return Colors.orange.shade700;
      case SupportTicketStatus.inProgress:
        return Colors.blue.shade700;
      case SupportTicketStatus.resolved:
      case SupportTicketStatus.closed:
        return Colors.green.shade700;
      case SupportTicketStatus.unknown:
        return Colors.grey.shade700;
    }
  }

  Color _severityColor(SupportTicketSeverity severity) {
    switch (severity) {
      case SupportTicketSeverity.critical:
        return Colors.red.shade700;
      case SupportTicketSeverity.high:
        return Colors.deepOrange.shade700;
      case SupportTicketSeverity.medium:
        return Colors.amber.shade800;
      case SupportTicketSeverity.low:
        return Colors.teal.shade700;
      case SupportTicketSeverity.unknown:
        return Colors.grey.shade700;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    if (isToday) {
      return 'Today $hour:$minute';
    }
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  Map<String, int> _duplicateCountsByKey(List<SupportTicket> tickets) {
    final counts = <String, int>{};
    for (final ticket in tickets) {
      final key = ticket.duplicateKey;
      if (key.isEmpty) {
        continue;
      }
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }
}
