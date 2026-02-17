import 'package:flutter/material.dart';

import '../models/access_request.dart';
import '../models/child_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

enum _RequestFilter {
  all,
  pending,
  responded,
}

class ChildRequestsScreen extends StatefulWidget {
  const ChildRequestsScreen({
    super.key,
    required this.child,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final ChildProfile child;
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<ChildRequestsScreen> createState() => _ChildRequestsScreenState();
}

class _ChildRequestsScreenState extends State<ChildRequestsScreen> {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  _RequestFilter _filter = _RequestFilter.all;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  @override
  Widget build(BuildContext context) {
    final parentId =
        widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Updates'),
        centerTitle: true,
      ),
      body: parentId == null || parentId.trim().isEmpty
          ? _buildAuthRequiredState(context)
          : Column(
              children: [
                _buildHeader(context),
                _buildFilterRow(context),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<List<AccessRequest>>(
                    stream: _resolvedFirestoreService.getChildRequestsStream(
                      parentId: parentId,
                      childId: widget.child.id,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        return _buildErrorState(
                          context,
                          'Could not load request updates.',
                        );
                      }

                      final requests = snapshot.data ?? const <AccessRequest>[];
                      final filteredRequests = _applyFilter(requests);

                      if (filteredRequests.isEmpty) {
                        return _buildEmptyState(context);
                      }

                      return ListView.separated(
                        key: const Key('child_requests_list'),
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final request = filteredRequests[index];
                          return _RequestStatusCard(
                            key: ValueKey<String>(
                              'child_request_history_card_${request.id}',
                            ),
                            request: request,
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: filteredRequests.length,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAuthRequiredState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          'Please sign in to see request updates.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.mark_email_read_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'See when your parent responds to access requests.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            key: const Key('child_requests_filter_all'),
            label: const Text('All'),
            selected: _filter == _RequestFilter.all,
            onSelected: (_) => setState(() => _filter = _RequestFilter.all),
          ),
          ChoiceChip(
            key: const Key('child_requests_filter_pending'),
            label: const Text('Pending'),
            selected: _filter == _RequestFilter.pending,
            onSelected: (_) => setState(() => _filter = _RequestFilter.pending),
          ),
          ChoiceChip(
            key: const Key('child_requests_filter_responded'),
            label: const Text('Responded'),
            selected: _filter == _RequestFilter.responded,
            onSelected: (_) =>
                setState(() => _filter = _RequestFilter.responded),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    String message;
    switch (_filter) {
      case _RequestFilter.all:
        message = 'No requests yet. You can ask for access anytime.';
        break;
      case _RequestFilter.pending:
        message = 'No pending requests right now.';
        break;
      case _RequestFilter.responded:
        message = 'No responded requests yet.';
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          key: const Key('child_requests_empty_state'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.red[700],
              ),
        ),
      ),
    );
  }

  List<AccessRequest> _applyFilter(List<AccessRequest> requests) {
    switch (_filter) {
      case _RequestFilter.all:
        return requests;
      case _RequestFilter.pending:
        return requests
            .where((request) => request.status == RequestStatus.pending)
            .toList();
      case _RequestFilter.responded:
        return requests
            .where((request) => request.status != RequestStatus.pending)
            .toList();
    }
  }
}

class _RequestStatusCard extends StatelessWidget {
  const _RequestStatusCard({
    super.key,
    required this.request,
  });

  final AccessRequest request;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(request.status);
    final requestAge = _timeAgo(request.requestedAt);
    final hasReply =
        request.parentReply != null && request.parentReply!.trim().isNotEmpty;
    final expiryLabel = _buildExpiryLabel(request.expiresAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${request.status.emoji} ${request.status.displayName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const Spacer(),
                Text(
                  requestAge,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.appOrSite,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    request.duration.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            if (request.reason != null && request.reason!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Reason: ${request.reason}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                    ),
              ),
            ],
            if (hasReply) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  'Message from parent: ${request.parentReply}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green[800],
                      ),
                ),
              ),
            ],
            if (expiryLabel != null) ...[
              const SizedBox(height: 10),
              Text(
                expiryLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(RequestStatus status) {
    switch (status) {
      case RequestStatus.pending:
        return Colors.orange;
      case RequestStatus.approved:
        return Colors.green;
      case RequestStatus.denied:
        return Colors.red;
      case RequestStatus.expired:
        return Colors.grey;
    }
  }

  String? _buildExpiryLabel(DateTime? expiresAt) {
    if (expiresAt == null) {
      return null;
    }
    if (DateTime.now().isAfter(expiresAt)) {
      return 'This access window has ended.';
    }
    final time = TimeOfDay.fromDateTime(expiresAt);
    final hourLabel = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minuteLabel = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return 'Access available until $hourLabel:$minuteLabel $period';
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    return '${diff.inDays}d ago';
  }
}
