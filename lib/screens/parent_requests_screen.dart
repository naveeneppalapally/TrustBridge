import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/access_request.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class ParentRequestsScreen extends StatefulWidget {
  const ParentRequestsScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.parentIdOverride,
  });

  final AuthService? authService;
  final FirestoreService? firestoreService;
  final String? parentIdOverride;

  @override
  State<ParentRequestsScreen> createState() => _ParentRequestsScreenState();
}

class _ParentRequestsScreenState extends State<ParentRequestsScreen>
    with SingleTickerProviderStateMixin {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  late final TabController _tabController;
  Stream<List<AccessRequest>>? _pendingRequestsStream;
  Stream<List<AccessRequest>>? _allRequestsStream;
  String? _streamsParentId;

  AuthService get _resolvedAuthService {
    _authService ??= widget.authService ?? AuthService();
    return _authService!;
  }

  FirestoreService get _resolvedFirestoreService {
    _firestoreService ??= widget.firestoreService ?? FirestoreService();
    return _firestoreService!;
  }

  void _ensureRequestStreams(String parentId) {
    if (_streamsParentId == parentId &&
        _pendingRequestsStream != null &&
        _allRequestsStream != null) {
      return;
    }

    _streamsParentId = parentId;
    _pendingRequestsStream =
        _resolvedFirestoreService.getPendingRequestsStream(parentId);
    _allRequestsStream =
        _resolvedFirestoreService.getAllRequestsStream(parentId);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parentId =
        widget.parentIdOverride ?? _resolvedAuthService.currentUser?.uid;
    if (parentId != null) {
      _ensureRequestStreams(parentId);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accessRequestsTitle),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: <Tab>[
            Tab(text: l10n.pendingTabTitle),
            Tab(text: l10n.historyTitle),
          ],
        ),
      ),
      body: parentId == null
          ? Center(
              child: Text(l10n.notLoggedInMessage),
            )
          : TabBarView(
              controller: _tabController,
              children: <Widget>[
                _buildPendingTab(parentId),
                _buildHistoryTab(parentId),
              ],
            ),
    );
  }

  Widget _buildPendingTab(String parentId) {
    final pendingRequestsStream = _pendingRequestsStream;
    if (pendingRequestsStream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>(
          'parent_requests_pending_${_streamsParentId ?? 'none'}'),
      stream: pendingRequestsStream,
      builder:
          (BuildContext context, AsyncSnapshot<List<AccessRequest>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final l10n = AppLocalizations.of(context)!;
          return Center(
            child: Text(l10n.errorWithValue('${snapshot.error}')),
          );
        }

        final requests = snapshot.data ?? const <AccessRequest>[];
        if (requests.isEmpty) {
          return _buildEmptyState(
            emoji: '\u2705',
            title: AppLocalizations.of(context)!.allCaughtUpTitle,
            subtitle: AppLocalizations.of(context)!.noPendingRequestsSubtitle,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (BuildContext context, int index) {
            return _RequestCard(
              key: ValueKey<String>('request_card_${requests[index].id}'),
              request: requests[index],
              parentId: parentId,
              firestoreService: _resolvedFirestoreService,
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryTab(String parentId) {
    final allRequestsStream = _allRequestsStream;
    if (allRequestsStream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>(
          'parent_requests_history_${_streamsParentId ?? 'none'}'),
      stream: allRequestsStream,
      builder:
          (BuildContext context, AsyncSnapshot<List<AccessRequest>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final l10n = AppLocalizations.of(context)!;
          return Center(
            child: Text(l10n.errorWithValue('${snapshot.error}')),
          );
        }

        final allRequests = snapshot.data ?? const <AccessRequest>[];
        final history = allRequests
            .where((request) => request.status != RequestStatus.pending)
            .toList();

        if (history.isEmpty) {
          return _buildEmptyState(
            emoji: '\u{1F4CB}',
            title: AppLocalizations.of(context)!.noHistoryYetTitle,
            subtitle: AppLocalizations.of(context)!.noHistoryYetSubtitle,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: history.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (BuildContext context, int index) {
            return _HistoryCard(request: history[index]);
          },
        );
      },
    );
  }

  Widget _buildEmptyState({
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({
    super.key,
    required this.request,
    required this.parentId,
    required this.firestoreService,
  });

  final AccessRequest request;
  final String parentId;
  final FirestoreService firestoreService;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  final TextEditingController _replyController = TextEditingController();
  bool _showReplyField = false;
  bool _isResponding = false;
  bool _hiddenOptimistically = false;
  RequestStatus? _pendingAction;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _respond(RequestStatus status) async {
    if (_isResponding) {
      return;
    }

    setState(() {
      _isResponding = true;
      _pendingAction = status;
      _hiddenOptimistically = true;
    });

    try {
      await widget.firestoreService.respondToAccessRequest(
        parentId: widget.parentId,
        requestId: widget.request.id,
        status: status,
        reply: _replyController.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == RequestStatus.approved
                ? AppLocalizations.of(context)!.requestApprovedMessage
                : AppLocalizations.of(context)!.requestDeniedMessage,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isResponding = false;
        _pendingAction = null;
        _hiddenOptimistically = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.errorWithValue('$error'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_hiddenOptimistically) {
      return const SizedBox.shrink();
    }

    final request = widget.request;
    final childInitial = request.childNickname.isEmpty
        ? '?'
        : request.childNickname[0].toUpperCase();

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.orange.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.blue.withValues(alpha: 0.15),
                  child: Text(
                    childInitial,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      request.childNickname,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      _timeAgo(context, request.requestedAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[500],
                          ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '⏳ ${l10n.statusPending}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange[800],
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.wantsAccessToLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[500],
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.appOrSite,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            if (request.reason != null &&
                request.reason!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('\u{1F4AC}', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '"${request.reason}"',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_showReplyField) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                key: Key('request_reply_input_${request.id}'),
                controller: _replyController,
                maxLines: 2,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: l10n.requestReplyHint(request.childNickname),
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showReplyField = !_showReplyField;
                    });
                  },
                  icon: Icon(_showReplyField ? Icons.close : Icons.reply,
                      size: 16),
                  label: Text(
                    _showReplyField
                        ? l10n.cancelReplyButton
                        : l10n.addReplyButton,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  key: Key('request_deny_button_${request.id}'),
                  onPressed: _isResponding
                      ? null
                      : () => _respond(RequestStatus.denied),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange[800],
                    side: BorderSide(
                        color: Colors.orange.withValues(alpha: 0.50)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  child: _isResponding && _pendingAction == RequestStatus.denied
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.denyButton),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  key: Key('request_approve_button_${request.id}'),
                  onPressed: _isResponding
                      ? null
                      : () => _respond(RequestStatus.approved),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  child:
                      _isResponding && _pendingAction == RequestStatus.approved
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(l10n.approveButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.request});

  final AccessRequest request;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(request.status);

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(request.status.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${request.childNickname} -> ${request.appOrSite}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Text(
                _statusText(context, request.status),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Text(
                request.duration.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                    ),
              ),
              const SizedBox(width: 12),
              Text(
                _timeAgo(context, request.requestedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                    ),
              ),
            ],
          ),
          if (request.parentReply != null &&
              request.parentReply!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '\u{1F4AC} "${request.parentReply}"',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ],
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
        return Colors.orange;
      case RequestStatus.expired:
        return Colors.grey;
    }
  }

  String _statusText(BuildContext context, RequestStatus status) {
    final l10n = AppLocalizations.of(context)!;
    switch (status) {
      case RequestStatus.pending:
        return l10n.statusPending;
      case RequestStatus.approved:
        return l10n.statusApproved;
      case RequestStatus.denied:
        return l10n.statusDenied;
      case RequestStatus.expired:
        return l10n.statusExpired;
    }
  }
}

String _timeAgo(BuildContext context, DateTime timestamp) {
  final l10n = AppLocalizations.of(context)!;
  final difference = DateTime.now().difference(timestamp);
  if (difference.inSeconds < 60) {
    return l10n.justNow;
  }
  if (difference.inMinutes < 60) {
    return l10n.minutesAgo(difference.inMinutes);
  }
  if (difference.inHours < 24) {
    return l10n.hoursAgo(difference.inHours);
  }
  return l10n.daysAgo(difference.inDays);
}
