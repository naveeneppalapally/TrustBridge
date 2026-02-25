/// Curated social media/app domains for instant local blocking.
class SocialMediaDomains {
  SocialMediaDomains._();

  /// Domain list grouped by app.
  static const Map<String, List<String>> byApp = <String, List<String>>{
    'instagram': <String>[
      'instagram.com',
      'cdninstagram.com',
      'i.instagram.com',
      'graph.instagram.com',
      'scontent.cdninstagram.com',
      'edge-chat.instagram.com',
      'z-p42-instagram.c10r.facebook.com',
      'www.instagram.com',
      'b.i.instagram.com',
      'static.cdninstagram.com',
      'scontent-del1-1.cdninstagram.com',
    ],
    'tiktok': <String>[
      'tiktok.com',
      'tiktokcdn.com',
      'muscdn.com',
      'tiktokv.com',
      'byteoversea.com',
    ],
    'twitter': <String>[
      'twitter.com',
      't.co',
      'twimg.com',
      'api.twitter.com',
      'x.com',
      'abs.twimg.com',
    ],
    'snapchat': <String>[
      'snapchat.com',
      'snap.com',
      'sc-cdn.net',
      'snapkit.com',
    ],
    'facebook': <String>[
      'facebook.com',
      'fb.com',
      'fbcdn.net',
      'connect.facebook.net',
      'facebook.net',
    ],
    'youtube': <String>[
      'youtube.com',
      'youtu.be',
      'googlevideo.com',
      'ytimg.com',
      'youtube-nocookie.com',
      'youtubei.googleapis.com',
      'youtube.googleapis.com',
      'youtubeandroidplayer.googleapis.com',
      'yt3.ggpht.com',
    ],
    'reddit': <String>[
      'reddit.com',
      'redd.it',
      'redditmedia.com',
      'reddituploads.com',
      'redditstatic.com',
    ],
    'roblox': <String>[
      'roblox.com',
      'rbxcdn.com',
      'robloxlabs.com',
    ],
  };

  /// Flat set for constant-time membership checks.
  static final Set<String> all = byApp.values
      .expand((domains) => domains)
      .map((domain) => domain.toLowerCase())
      .toSet();

  /// Returns app key for a domain when found, else null.
  static String? appForDomain(String domain) {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final entry in byApp.entries) {
      if (entry.value.contains(normalized)) {
        return entry.key;
      }
    }
    return null;
  }
}
