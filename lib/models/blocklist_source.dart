/// Categories supported by bundled open-source blocklist sources.
enum BlocklistCategory {
  /// Social media domains.
  social,

  /// Ad and tracker domains.
  ads,

  /// Malware/phishing related domains.
  malware,

  /// Adult-content domains.
  adult,

  /// Gambling domains.
  gambling,
}

/// Represents a blocklist source definition and sync metadata.
class BlocklistSource {
  /// Creates a blocklist source instance.
  const BlocklistSource({
    required this.id,
    required this.name,
    required this.category,
    required this.url,
    required this.license,
    required this.attribution,
    required this.lastSynced,
    required this.domainCount,
  });

  /// Stable source identifier.
  final String id;

  /// Human readable source name.
  final String name;

  /// Category represented by this source.
  final BlocklistCategory category;

  /// Download URL for the source.
  final String url;

  /// Source license text.
  final String license;

  /// Source attribution text.
  final String attribution;

  /// Last successful sync timestamp.
  final DateTime? lastSynced;

  /// Last known domain count for this source.
  final int domainCount;

  /// Returns a copy with updated fields.
  BlocklistSource copyWith({
    String? id,
    String? name,
    BlocklistCategory? category,
    String? url,
    String? license,
    String? attribution,
    DateTime? lastSynced,
    bool clearLastSynced = false,
    int? domainCount,
  }) {
    return BlocklistSource(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      url: url ?? this.url,
      license: license ?? this.license,
      attribution: attribution ?? this.attribution,
      lastSynced: clearLastSynced ? null : (lastSynced ?? this.lastSynced),
      domainCount: domainCount ?? this.domainCount,
    );
  }

  /// Serializes this instance into a map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'category': category.name,
      'url': url,
      'license': license,
      'attribution': attribution,
      'lastSynced': lastSynced?.millisecondsSinceEpoch,
      'domainCount': domainCount,
    };
  }

  /// Deserializes a blocklist source from a map.
  factory BlocklistSource.fromMap(Map<String, dynamic> map) {
    final rawCategory = map['category']?.toString().trim() ?? '';
    final category = BlocklistCategory.values.firstWhere(
      (value) => value.name == rawCategory,
      orElse: () => BlocklistCategory.social,
    );
    final rawLastSynced = map['lastSynced'];
    final rawDomainCount = map['domainCount'];

    return BlocklistSource(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      category: category,
      url: map['url']?.toString() ?? '',
      license: map['license']?.toString() ?? '',
      attribution: map['attribution']?.toString() ?? '',
      lastSynced: rawLastSynced is int
          ? DateTime.fromMillisecondsSinceEpoch(rawLastSynced)
          : null,
      domainCount: rawDomainCount is int
          ? rawDomainCount
          : rawDomainCount is num
              ? rawDomainCount.toInt()
              : 0,
    );
  }
}
