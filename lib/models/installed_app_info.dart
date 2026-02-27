class InstalledAppInfo {
  const InstalledAppInfo({
    required this.packageName,
    required this.appName,
    this.appIconBase64,
    this.isSystemApp = false,
    this.isLaunchable = true,
    this.firstSeenAt,
    this.lastSeenAt,
  });

  final String packageName;
  final String appName;
  final String? appIconBase64;
  final bool isSystemApp;
  final bool isLaunchable;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;

  bool get isValid => packageName.trim().isNotEmpty;

  factory InstalledAppInfo.fromMap(Map<String, dynamic> map) {
    return InstalledAppInfo(
      packageName: (map['packageName'] as String? ?? '').trim().toLowerCase(),
      appName: (map['appName'] as String? ?? '').trim(),
      appIconBase64: (map['appIconBase64'] as String?)?.trim(),
      isSystemApp: map['isSystemApp'] == true,
      isLaunchable: map['isLaunchable'] != false,
      firstSeenAt: _asDateTime(map['firstSeenAt']),
      lastSeenAt: _asDateTime(map['lastSeenAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'packageName': packageName.trim().toLowerCase(),
      'appName': appName.trim(),
      if (appIconBase64 != null && appIconBase64!.trim().isNotEmpty)
        'appIconBase64': appIconBase64!.trim(),
      'isSystemApp': isSystemApp,
      'isLaunchable': isLaunchable,
      if (firstSeenAt != null) 'firstSeenAt': firstSeenAt,
      if (lastSeenAt != null) 'lastSeenAt': lastSeenAt,
    };
  }

  InstalledAppInfo copyWith({
    String? packageName,
    String? appName,
    String? appIconBase64,
    bool? isSystemApp,
    bool? isLaunchable,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
  }) {
    return InstalledAppInfo(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      appIconBase64: appIconBase64 ?? this.appIconBase64,
      isSystemApp: isSystemApp ?? this.isSystemApp,
      isLaunchable: isLaunchable ?? this.isLaunchable,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  static DateTime? _asDateTime(Object? raw) {
    if (raw is DateTime) {
      return raw;
    }
    if (raw is int && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is num && raw.toInt() > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    return null;
  }
}
