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
