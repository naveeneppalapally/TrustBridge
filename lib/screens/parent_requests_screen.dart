import 'package:flutter/material.dart';
import 'package:trustbridge_app/l10n/app_localizations.dart';
import 'package:trustbridge_app/l10n/app_localizations_en.dart';

import '../models/access_request.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/expiry_label_utils.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_loaders.dart';
import 'approval_success_screen.dart';

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
    final l10n = _l10n(context);
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
      return _buildRequestsLoadingState();
    }

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>(
          'parent_requests_pending_${_streamsParentId ?? 'none'}'),
      stream: pendingRequestsStream,
      builder:
          (BuildContext context, AsyncSnapshot<List<AccessRequest>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildRequestsLoadingState();
        }

        if (snapshot.hasError) {
          final l10n = _l10n(context);
          return Center(
            child: Text(l10n.errorWithValue('${snapshot.error}')),
          );
        }

        final requests = snapshot.data ?? const <AccessRequest>[];
        if (requests.isEmpty) {
          return _buildEmptyState(
            emoji: '\u2705',
            title: _l10n(context).allCaughtUpTitle,
            subtitle: _l10n(context).noPendingRequestsSubtitle,
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
      return _buildRequestsLoadingState();
    }

    return StreamBuilder<List<AccessRequest>>(
      key: ValueKey<String>(
          'parent_requests_history_${_streamsParentId ?? 'none'}'),
      stream: allRequestsStream,
      builder:
          (BuildContext context, AsyncSnapshot<List<AccessRequest>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildRequestsLoadingState();
        }

        if (snapshot.hasError) {
          final l10n = _l10n(context);
          return Center(
            child: Text(l10n.errorWithValue('${snapshot.error}')),
          );
        }

        final allRequests = snapshot.data ?? const <AccessRequest>[];
        final history = allRequests
            .where(
              (request) => request.effectiveStatus() != RequestStatus.pending,
            )
            .toList();

        if (history.isEmpty) {
          return _buildEmptyState(
            emoji: '\u{1F4CB}',
            title: _l10n(context).noHistoryYetTitle,
            subtitle: _l10n(context).noHistoryYetSubtitle,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: history.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (BuildContext context, int index) {
            return _HistoryCard(
              request: history[index],
              parentId: parentId,
              firestoreService: _resolvedFirestoreService,
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsLoadingState() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const SkeletonListTile(),
    );
  }

  Widget _buildEmptyState({
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    return EmptyState(
      icon: Text(emoji),
      title: title,
      subtitle: subtitle,
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
  bool _isResponding = false;
  bool _hiddenOptimistically = false;
  RequestStatus? _pendingAction;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _respond(
    RequestStatus status, {
    required String reply,
    RequestDuration? approvedDurationOverride,
  }) async {
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
        reply: reply,
        approvedDurationOverride: approvedDurationOverride,
      );
      if (!mounted) {
        return;
      }
      if (status == RequestStatus.approved) {
        final resolvedDuration =
            approvedDurationOverride ?? widget.request.duration;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ApprovalSuccessScreen(
              appName: widget.request.appOrSite,
              durationLabel: _durationLabel(_l10n(context), resolvedDuration),
              childName: widget.request.childNickname,
            ),
          ),
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == RequestStatus.approved
                ? _l10n(context).requestApprovedMessage
                : _l10n(context).requestDeniedMessage,
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
            _l10n(context).errorWithValue('$error'),
          ),
        ),
      );
    }
  }

  Future<void> _openDecisionModal(RequestStatus status) async {
    if (_isResponding) {
      return;
    }

    final request = widget.request;
    final l10n = _l10n(context);
    _replyController.text = '';
    var selectedDuration = request.duration;
    var selectedStatus = status;

    final result = await showModalBottomSheet<RequestStatus?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final quickReplies = _quickReplyOptions(l10n, selectedStatus);
            final childInitial = request.childNickname.isEmpty
                ? '?'
                : request.childNickname[0].toUpperCase();

            return Container(
              key: Key('request_decision_dialog_${request.id}'),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'NEW REQUEST',
                          style: TextStyle(
                            color: Color(0xFF207CF8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'Access Request',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: CircleAvatar(
                        radius: 38,
                        backgroundColor: Colors.blue.withValues(alpha: 0.12),
                        child: Text(
                          childInitial,
                          style: const TextStyle(
                            color: Color(0xFF207CF8),
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.black87,
                                    height: 1.4,
                                  ),
                          children: [
                            TextSpan(
                              text:
                                  '${request.childNickname} is asking to use ',
                            ),
                            TextSpan(
                              text: request.appOrSite,
                              style: const TextStyle(
                                color: Color(0xFF207CF8),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.schedule_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text('Requested ${request.duration.label}'),
                      ],
                    ),
                    if (request.reason != null &&
                        request.reason!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '"${request.reason}"',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey[700],
                                  ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      l10n.quickRepliesLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickReplies
                          .asMap()
                          .entries
                          .map(
                            (entry) => ActionChip(
                              key: Key(
                                'request_quick_reply_${request.id}_${entry.key}',
                              ),
                              label: Text(entry.value),
                              onPressed: () {
                                setSheetState(() {
                                  _replyController.text = entry.value;
                                  _replyController.selection =
                                      TextSelection.collapsed(
                                    offset: _replyController.text.length,
                                  );
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: Key('request_modal_reply_input_${request.id}'),
                      controller: _replyController,
                      maxLines: 3,
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: l10n.parentReplyOptionalLabel,
                        hintText: l10n.requestReplyHint(request.childNickname),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (selectedStatus == RequestStatus.approved) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        l10n.approvalDurationLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: RequestDuration.values
                            .map(
                              (duration) => ChoiceChip(
                                key: Key(
                                  'request_duration_option_${request.id}_${duration.name}',
                                ),
                                label: Text(_durationLabel(l10n, duration)),
                                selected: selectedDuration == duration,
                                onSelected: (_) {
                                  setSheetState(() {
                                    selectedDuration = duration;
                                  });
                                },
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _approvalExpiryPreview(context, l10n, selectedDuration),
                        key: Key('request_expiry_preview_${request.id}'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        key:
                            Key('request_confirm_approve_button_${request.id}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF68B901),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () {
                          setSheetState(() {
                            selectedStatus = RequestStatus.approved;
                          });
                          Navigator.of(sheetContext).pop(
                            RequestStatus.approved,
                          );
                        },
                        child: const Text('Approve Request'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: Key('request_confirm_deny_button_${request.id}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () {
                          setSheetState(() {
                            selectedStatus = RequestStatus.denied;
                          });
                          Navigator.of(sheetContext).pop(
                            RequestStatus.denied,
                          );
                        },
                        child: const Text('Deny'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(null),
                        child: Text(l10n.keepPendingButton),
                      ),
                    ),
                    Center(
                      child: Text(
                        'REQUESTED ${_timeAgo(context, request.requestedAt).toUpperCase()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    final reply = _replyController.text.trim();
    await _respond(
      result,
      reply: reply,
      approvedDurationOverride:
          result == RequestStatus.approved ? selectedDuration : null,
    );
  }

  String _durationLabel(AppLocalizations l10n, RequestDuration duration) {
    switch (duration) {
      case RequestDuration.fifteenMin:
        return l10n.durationFifteenMin;
      case RequestDuration.thirtyMin:
        return l10n.durationThirtyMin;
      case RequestDuration.oneHour:
        return l10n.durationOneHour;
      case RequestDuration.twoHours:
        return '2 hours';
      case RequestDuration.untilScheduleEnds:
        return l10n.durationUntilEnd;
    }
  }

  String _approvalExpiryPreview(
    BuildContext context,
    AppLocalizations l10n,
    RequestDuration duration,
  ) {
    final minutes = duration.minutes;
    if (minutes == null || minutes <= 0) {
      return l10n.approvalUntilSchedulePreview;
    }
    final materialLocalizations = MaterialLocalizations.of(context);
    final expiresAt = DateTime.now().add(Duration(minutes: minutes));
    final formattedTime = materialLocalizations
        .formatTimeOfDay(TimeOfDay.fromDateTime(expiresAt));
    return l10n.approvalExpiresPreview(formattedTime);
  }

  List<String> _quickReplyOptions(AppLocalizations l10n, RequestStatus status) {
    if (status == RequestStatus.approved) {
      return <String>[
        l10n.quickReplyApproveStudy,
        l10n.quickReplyApproveTakeBreak,
        l10n.quickReplyApproveCareful,
      ];
    }
    return <String>[
      l10n.quickReplyDenyNotNow,
      l10n.quickReplyDenyHomework,
      l10n.quickReplyDenyLaterToday,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
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
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isResponding
            ? null
            : () => _openDecisionModal(RequestStatus.approved),
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
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const Spacer(),
                  OutlinedButton(
                    key: Key('request_deny_button_${request.id}'),
                    onPressed: _isResponding
                        ? null
                        : () => _openDecisionModal(RequestStatus.denied),
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
                    child: _isResponding &&
                            _pendingAction == RequestStatus.denied
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
                        : () => _openDecisionModal(RequestStatus.approved),
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
                    child: _isResponding &&
                            _pendingAction == RequestStatus.approved
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
      ),
    );
  }
}

class _HistoryCard extends StatefulWidget {
  const _HistoryCard({
    required this.request,
    required this.parentId,
    required this.firestoreService,
  });

  final AccessRequest request;
  final String parentId;
  final FirestoreService firestoreService;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _isEndingAccess = false;

  bool _canEndAccessNow(AccessRequest request) {
    if (request.status != RequestStatus.approved) {
      return false;
    }
    final expiresAt = request.expiresAt;
    return expiresAt == null || expiresAt.isAfter(DateTime.now());
  }

  Future<void> _endAccessNow() async {
    if (_isEndingAccess) {
      return;
    }

    final request = widget.request;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final l10n = _l10n(dialogContext);
        return AlertDialog(
          key: Key('request_end_access_dialog_${request.id}'),
          title: Text(l10n.endAccessDialogTitle),
          content: Text(
            l10n.endAccessDialogSummary(
              request.childNickname,
              request.appOrSite,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              key: Key('request_confirm_end_access_button_${request.id}'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.endAccessNowButton),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isEndingAccess = true;
    });

    try {
      await widget.firestoreService.expireApprovedAccessRequestNow(
        parentId: widget.parentId,
        requestId: request.id,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n(context).accessEndedMessage),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n(context).errorWithValue('$error')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isEndingAccess = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final effectiveStatus = request.effectiveStatus();
    final color = _statusColor(effectiveStatus);

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
              Text(effectiveStatus.emoji, style: const TextStyle(fontSize: 18)),
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
                _statusText(context, effectiveStatus),
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
          ..._buildExpiryMeta(context, request, effectiveStatus),
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
          if (_canEndAccessNow(request)) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: Key('request_end_access_button_${request.id}'),
                onPressed: _isEndingAccess ? null : _endAccessNow,
                icon: _isEndingAccess
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.block, size: 16),
                label: Text(_l10n(context).endAccessNowButton),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[700],
                  side: BorderSide(
                    color: Colors.red.withValues(alpha: 0.40),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildExpiryMeta(
    BuildContext context,
    AccessRequest request,
    RequestStatus effectiveStatus,
  ) {
    final expiresAt = request.expiresAt;
    if (expiresAt == null) {
      if (effectiveStatus == RequestStatus.approved) {
        return <Widget>[
          const SizedBox(height: 6),
          Text(
            'No fixed expiry (until schedule ends)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.green[700],
                ),
          ),
        ];
      }
      return const <Widget>[];
    }

    final label = buildExpiryRelativeLabel(expiresAt);
    final color = effectiveStatus == RequestStatus.expired
        ? Colors.grey[700]
        : Colors.green[700];

    return <Widget>[
      const SizedBox(height: 6),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    ];
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
    final l10n = _l10n(context);
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
  final l10n = _l10n(context);
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

AppLocalizations _l10n(BuildContext context) {
  return AppLocalizations.of(context) ?? AppLocalizationsEn();
}
