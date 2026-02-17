import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/support_ticket.dart';
import 'package:trustbridge_app/screens/beta_feedback_screen.dart';
import 'package:trustbridge_app/services/auth_service.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

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
            return _buildEmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: tickets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int index) {
              final ticket = tickets[index];
              return _buildTicketCard(ticket);
            },
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.forum_outlined, size: 64, color: Colors.blueGrey),
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

  Widget _buildTicketCard(SupportTicket ticket) {
    final color = _statusColor(ticket.status);
    return Card(
      key: Key('feedback_history_ticket_${ticket.id}'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openTicketDetails(ticket),
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

  Future<void> _openTicketDetails(SupportTicket ticket) async {
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
}
