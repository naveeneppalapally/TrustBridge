import 'package:cloud_firestore/cloud_firestore.dart';

enum SupportTicketStatus {
  open,
  inProgress,
  resolved,
  closed,
  unknown;

  static SupportTicketStatus fromRaw(String? rawStatus) {
    switch (rawStatus) {
      case 'open':
        return SupportTicketStatus.open;
      case 'in_progress':
      case 'inProgress':
        return SupportTicketStatus.inProgress;
      case 'resolved':
        return SupportTicketStatus.resolved;
      case 'closed':
        return SupportTicketStatus.closed;
      default:
        return SupportTicketStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case SupportTicketStatus.open:
        return 'Open';
      case SupportTicketStatus.inProgress:
        return 'In Progress';
      case SupportTicketStatus.resolved:
        return 'Resolved';
      case SupportTicketStatus.closed:
        return 'Closed';
      case SupportTicketStatus.unknown:
        return 'Unknown';
    }
  }
}

enum SupportTicketSource {
  betaFeedback,
  helpSupport;

  String get label {
    switch (this) {
      case SupportTicketSource.betaFeedback:
        return 'Beta';
      case SupportTicketSource.helpSupport:
        return 'Support';
    }
  }
}

enum SupportTicketSeverity {
  critical,
  high,
  medium,
  low,
  unknown;

  static SupportTicketSeverity fromSubject(String subject) {
    final normalized = subject.trim();
    final match = RegExp(
      r'^\[Beta\]\[(Critical|High|Medium|Low)\]',
      caseSensitive: false,
    ).firstMatch(normalized);
    final raw = match?.group(1)?.toLowerCase();
    switch (raw) {
      case 'critical':
        return SupportTicketSeverity.critical;
      case 'high':
        return SupportTicketSeverity.high;
      case 'medium':
        return SupportTicketSeverity.medium;
      case 'low':
        return SupportTicketSeverity.low;
      default:
        return SupportTicketSeverity.unknown;
    }
  }

  String get label {
    switch (this) {
      case SupportTicketSeverity.critical:
        return 'Critical';
      case SupportTicketSeverity.high:
        return 'High';
      case SupportTicketSeverity.medium:
        return 'Medium';
      case SupportTicketSeverity.low:
        return 'Low';
      case SupportTicketSeverity.unknown:
        return 'Unknown';
    }
  }

  int get rank {
    switch (this) {
      case SupportTicketSeverity.critical:
        return 0;
      case SupportTicketSeverity.high:
        return 1;
      case SupportTicketSeverity.medium:
        return 2;
      case SupportTicketSeverity.low:
        return 3;
      case SupportTicketSeverity.unknown:
        return 4;
    }
  }
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.parentId,
    required this.subject,
    required this.message,
    this.childId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String parentId;
  final String subject;
  final String message;
  final String? childId;
  final SupportTicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isBetaFeedback => subject.startsWith('[Beta]');

  SupportTicketSource get source {
    return isBetaFeedback
        ? SupportTicketSource.betaFeedback
        : SupportTicketSource.helpSupport;
  }

  SupportTicketSeverity get severity {
    return SupportTicketSeverity.fromSubject(subject);
  }

  bool get isResolved {
    return status == SupportTicketStatus.resolved ||
        status == SupportTicketStatus.closed;
  }

  Duration age({DateTime? now}) {
    final reference = now ?? DateTime.now();
    return reference.difference(createdAt);
  }

  bool needsAttention({DateTime? now}) {
    if (isResolved) {
      return false;
    }
    return age(now: now).inHours >= 24;
  }

  bool isStale({DateTime? now}) {
    if (isResolved) {
      return false;
    }
    return age(now: now).inHours >= 72;
  }

  factory SupportTicket.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};

    final childIdValue = data['childId'];
    final normalizedChildId =
        childIdValue is String && childIdValue.trim().isNotEmpty
            ? childIdValue.trim()
            : null;

    return SupportTicket(
      id: snapshot.id,
      parentId: (data['parentId'] as String? ?? '').trim(),
      subject: (data['subject'] as String? ?? '').trim(),
      message: (data['message'] as String? ?? '').trim(),
      childId: normalizedChildId,
      status: SupportTicketStatus.fromRaw(data['status'] as String?),
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
