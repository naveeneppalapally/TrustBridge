import '../models/blocklist_source.dart';

/// Registry of bundled open-source blocklist sources used by TrustBridge.
class BlocklistSources {
  BlocklistSources._();

  static const String _mit = 'MIT';
  static const String _attribution =
      'Copyright (c) Steven Black - https://github.com/StevenBlack/hosts';

  /// Complete source registry.
  static const List<BlocklistSource> all = <BlocklistSource>[
    BlocklistSource(
      id: 'stevenblack_social',
      name: 'Social Media',
      category: BlocklistCategory.social,
      url:
          'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social/hosts',
      license: _mit,
      attribution: _attribution,
      lastSynced: null,
      domainCount: 0,
    ),
    BlocklistSource(
      id: 'stevenblack_ads',
      name: 'Ads',
      category: BlocklistCategory.ads,
      url: 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts',
      license: _mit,
      attribution: _attribution,
      lastSynced: null,
      domainCount: 0,
    ),
    BlocklistSource(
      id: 'stevenblack_adult',
      name: 'Adult Content',
      category: BlocklistCategory.adult,
      url:
          'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts',
      license: _mit,
      attribution: _attribution,
      lastSynced: null,
      domainCount: 0,
    ),
    BlocklistSource(
      id: 'stevenblack_gambling',
      name: 'Gambling',
      category: BlocklistCategory.gambling,
      url:
          'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling/hosts',
      license: _mit,
      attribution: _attribution,
      lastSynced: null,
      domainCount: 0,
    ),
    BlocklistSource(
      id: 'stevenblack_malware',
      name: 'Malware',
      category: BlocklistCategory.malware,
      url:
          'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts',
      license: _mit,
      attribution: _attribution,
      lastSynced: null,
      domainCount: 0,
    ),
  ];

  /// Returns the first source matching a category, or null when missing.
  static BlocklistSource? forCategory(BlocklistCategory category) {
    for (final source in all) {
      if (source.category == category) {
        return source;
      }
    }
    return null;
  }
}
