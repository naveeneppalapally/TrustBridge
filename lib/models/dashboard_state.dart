import 'package:cloud_firestore/cloud_firestore.dart';

class DashboardChildSummary {
  const DashboardChildSummary({
    required this.childId,
    required this.name,
    required this.protectionEnabled,
    required this.protectionStatus,
    required this.activeMode,
    required this.screenTimeTodayMs,
    required this.pendingRequestCount,
    required this.online,
    required this.vpnActive,
    required this.lastSeenEpochMs,
    required this.updatedAtEpochMs,
  });

  final String childId;
  final String name;
  final bool protectionEnabled;
  final String protectionStatus;
  final String activeMode;
  final int screenTimeTodayMs;
  final int pendingRequestCount;
  final bool online;
  final bool vpnActive;
  final int? lastSeenEpochMs;
  final int updatedAtEpochMs;

  bool get isPaused => activeMode == 'paused';
}

class DashboardStateSnapshot {
  const DashboardStateSnapshot({
    required this.parentId,
    required this.children,
    required this.totalPendingRequests,
    required this.totalScreenTimeTodayMs,
    required this.generatedAtEpochMs,
    required this.updatedAt,
  });

  final String parentId;
  final List<DashboardChildSummary> children;
  final int totalPendingRequests;
  final int totalScreenTimeTodayMs;
  final int generatedAtEpochMs;
  final DateTime? updatedAt;

  static DashboardStateSnapshot? fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return null;
    }

    final parentId = _stringValue(data['parentId']);
    final rawChildren = data['children'];
    final children = <DashboardChildSummary>[];
    if (rawChildren is List) {
      for (final rawChild in rawChildren) {
        final child = _childFromRaw(rawChild);
        if (child != null) {
          children.add(child);
        }
      }
    }
    children.sort((a, b) => a.name.compareTo(b.name));

    return DashboardStateSnapshot(
      parentId: parentId,
      children: List<DashboardChildSummary>.unmodifiable(children),
      totalPendingRequests: _intValue(
        data['totalPendingRequests'],
        fallback: children.fold<int>(
          0,
          (acc, child) => acc + child.pendingRequestCount,
        ),
      ),
      totalScreenTimeTodayMs: _intValue(
        data['totalScreenTimeTodayMs'],
        fallback: children.fold<int>(
          0,
          (acc, child) => acc + child.screenTimeTodayMs,
        ),
      ),
      generatedAtEpochMs: _intValue(data['generatedAtEpochMs']),
      updatedAt: _dateTimeValue(data['updatedAt']),
    );
  }

  static DashboardChildSummary? _childFromRaw(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final childId = _stringValue(map['childId']);
    if (childId.isEmpty) {
      return null;
    }
    return DashboardChildSummary(
      childId: childId,
      name: _stringValue(map['name'], fallback: 'Child'),
      protectionEnabled: _boolValue(map['protectionEnabled'], fallback: true),
      protectionStatus: _stringValue(map['protectionStatus']),
      activeMode: _stringValue(map['activeMode']),
      screenTimeTodayMs: _intValue(map['screenTimeTodayMs']),
      pendingRequestCount: _intValue(map['pendingRequestCount']),
      online: _boolValue(map['online']),
      vpnActive: _boolValue(map['vpnActive']),
      lastSeenEpochMs: _nullableIntValue(map['lastSeenEpochMs']),
      updatedAtEpochMs: _intValue(map['updatedAtEpochMs']),
    );
  }

  static String _stringValue(
    Object? value, {
    String fallback = '',
  }) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static int _intValue(
    Object? value, {
    int fallback = 0,
  }) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
  }

  static int? _nullableIntValue(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = _intValue(value, fallback: -1);
    return parsed >= 0 ? parsed : null;
  }

  static bool _boolValue(
    Object? value, {
    bool fallback = false,
  }) {
    if (value is bool) {
      return value;
    }
    return fallback;
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
