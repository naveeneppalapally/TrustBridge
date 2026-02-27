import '../models/service_definition.dart';
import 'category_ids.dart';

class ServiceDefinitions {
  const ServiceDefinitions._();

  static const List<ServiceDefinition> all = <ServiceDefinition>[
    ServiceDefinition(
      serviceId: 'instagram',
      categoryId: 'social-networks',
      displayName: 'Instagram',
      domains: <String>[
        'instagram.com',
        'cdninstagram.com',
        'i.instagram.com',
        'graph.instagram.com',
        'scontent.cdninstagram.com',
        'edge-chat.instagram.com',
        'z-p42-instagram.c10r.facebook.com',
      ],
      criticalDomains: <String>['instagram.com', 'i.instagram.com'],
      androidPackages: <String>['com.instagram.android'],
    ),
    ServiceDefinition(
      serviceId: 'tiktok',
      categoryId: 'social-networks',
      displayName: 'TikTok',
      domains: <String>[
        'tiktok.com',
        'tiktokcdn.com',
        'muscdn.com',
        'tiktokv.com',
        'byteoversea.com',
      ],
      criticalDomains: <String>['tiktok.com'],
      androidPackages: <String>['com.zhiliaoapp.musically'],
    ),
    ServiceDefinition(
      serviceId: 'facebook',
      categoryId: 'social-networks',
      displayName: 'Facebook',
      domains: <String>[
        'facebook.com',
        'fb.com',
        'fbcdn.net',
        'connect.facebook.net',
        'facebook.net',
      ],
      criticalDomains: <String>['facebook.com'],
      androidPackages: <String>['com.facebook.katana', 'com.facebook.lite'],
    ),
    ServiceDefinition(
      serviceId: 'snapchat',
      categoryId: 'social-networks',
      displayName: 'Snapchat',
      domains: <String>[
        'snapchat.com',
        'snap.com',
        'sc-cdn.net',
        'snapkit.com',
      ],
      criticalDomains: <String>['snapchat.com'],
      androidPackages: <String>['com.snapchat.android'],
    ),
    ServiceDefinition(
      serviceId: 'twitter',
      categoryId: 'social-networks',
      displayName: 'Twitter / X',
      domains: <String>[
        'twitter.com',
        't.co',
        'twimg.com',
        'api.twitter.com',
        'x.com',
        'abs.twimg.com',
      ],
      criticalDomains: <String>['x.com', 'twitter.com'],
      androidPackages: <String>[
        'com.twitter.android',
        'com.xcorp.android',
      ],
    ),
    ServiceDefinition(
      serviceId: 'youtube',
      categoryId: 'streaming',
      displayName: 'YouTube',
      domains: <String>[
        'youtube.com',
        'm.youtube.com',
        'youtu.be',
        'googlevideo.com',
        'ytimg.com',
        'youtube-nocookie.com',
        'youtubei.googleapis.com',
        'youtube.googleapis.com',
        'youtubeandroidplayer.googleapis.com',
        'yt3.ggpht.com',
      ],
      criticalDomains: <String>[
        'youtube.com',
        'googlevideo.com',
        'youtubei.googleapis.com',
      ],
      androidPackages: <String>[
        'com.google.android.youtube',
        'app.revanced.android.youtube',
        'com.google.android.apps.youtube.music',
        'com.google.android.apps.kids.familylinkhelper',
      ],
    ),
    ServiceDefinition(
      serviceId: 'reddit',
      categoryId: 'forums',
      displayName: 'Reddit',
      domains: <String>[
        'reddit.com',
        'redd.it',
        'redditmedia.com',
        'reddituploads.com',
        'redditstatic.com',
      ],
      criticalDomains: <String>['reddit.com'],
      androidPackages: <String>['com.reddit.frontpage'],
    ),
    ServiceDefinition(
      serviceId: 'roblox',
      categoryId: 'games',
      displayName: 'Roblox',
      domains: <String>['roblox.com', 'rbxcdn.com', 'robloxlabs.com'],
      criticalDomains: <String>['roblox.com'],
      androidPackages: <String>['com.roblox.client'],
    ),
    ServiceDefinition(
      serviceId: 'whatsapp',
      categoryId: 'chat',
      displayName: 'WhatsApp',
      domains: <String>['whatsapp.com', 'web.whatsapp.com', 'whatsapp.net'],
      criticalDomains: <String>['whatsapp.com'],
      androidPackages: <String>['com.whatsapp', 'com.whatsapp.w4b'],
    ),
    ServiceDefinition(
      serviceId: 'telegram',
      categoryId: 'chat',
      displayName: 'Telegram',
      domains: <String>['telegram.org', 't.me'],
      criticalDomains: <String>['telegram.org'],
      androidPackages: <String>['org.telegram.messenger'],
    ),
    ServiceDefinition(
      serviceId: 'discord',
      categoryId: 'chat',
      displayName: 'Discord',
      domains: <String>['discord.com', 'discord.gg', 'discordapp.com'],
      criticalDomains: <String>['discord.com'],
      androidPackages: <String>['com.discord'],
    ),
  ];

  static final Map<String, ServiceDefinition> byId =
      <String, ServiceDefinition>{
    for (final service in all) service.serviceId: service,
  };

  static final Map<String, ServiceDefinition> _byPackage =
      <String, ServiceDefinition>{
    for (final service in all)
      for (final pkg in service.androidPackages)
        pkg.trim().toLowerCase(): service,
  };

  static List<String> servicesForCategory(String rawCategoryId) {
    final categoryId = normalizeCategoryId(rawCategoryId);
    if (categoryId.isEmpty) {
      return const <String>[];
    }
    final unique = <String>{};
    for (final service in all) {
      if (normalizeCategoryId(service.categoryId) == categoryId) {
        unique.add(service.serviceId);
      }
    }
    final ordered = unique.toList()..sort();
    return ordered;
  }

  static Set<String> resolveEffectiveServices({
    required Iterable<String> blockedCategories,
    required Iterable<String> blockedServices,
  }) {
    final effective = <String>{};
    final normalizedCategories =
        normalizeCategoryIds(blockedCategories).toSet();

    for (final raw in blockedServices) {
      final serviceId = raw.trim().toLowerCase();
      if (serviceId.isNotEmpty && byId.containsKey(serviceId)) {
        effective.add(serviceId);
      }
    }

    for (final category in normalizedCategories) {
      effective.addAll(servicesForCategory(category));
    }
    return effective;
  }

  static Set<String> resolveDomains({
    required Iterable<String> blockedCategories,
    required Iterable<String> blockedServices,
    required Iterable<String> customBlockedDomains,
  }) {
    final result = <String>{};
    final normalizedCategories =
        normalizeCategoryIds(blockedCategories).toSet();
    result.addAll(
      customBlockedDomains
          .map((d) => d.trim().toLowerCase())
          .where((d) => d.isNotEmpty),
    );

    final serviceIds = resolveEffectiveServices(
      blockedCategories: blockedCategories,
      blockedServices: blockedServices,
    );
    for (final serviceId in serviceIds) {
      final service = byId[serviceId];
      if (service == null) {
        continue;
      }
      final blockedByCategory =
          normalizedCategories.contains(service.categoryId);
      final domainsSource =
          (!blockedByCategory && service.criticalDomains.isNotEmpty)
              ? service.criticalDomains
              : service.domains;
      result.addAll(
        domainsSource
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty),
      );
    }
    return result;
  }

  static Set<String> resolvePackages({
    required Iterable<String> blockedCategories,
    required Iterable<String> blockedServices,
  }) {
    final result = <String>{};
    final serviceIds = resolveEffectiveServices(
      blockedCategories: blockedCategories,
      blockedServices: blockedServices,
    );
    for (final serviceId in serviceIds) {
      final service = byId[serviceId];
      if (service == null) {
        continue;
      }
      result.addAll(
        service.androidPackages
            .map((pkg) => pkg.trim().toLowerCase())
            .where((pkg) => pkg.isNotEmpty),
      );
    }
    return result;
  }

  static Set<String> resolveDomainsForPackages(
    Iterable<String> blockedPackages,
  ) {
    final result = <String>{};
    for (final rawPackage in blockedPackages) {
      final packageName = rawPackage.trim().toLowerCase();
      if (packageName.isEmpty) {
        continue;
      }
      final service = _byPackage[packageName];
      if (service == null) {
        continue;
      }
      result.addAll(
        service.domains
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty),
      );
    }
    return result;
  }

  static Set<String> inferServicesFromLegacyDomains(Iterable<String> domains) {
    final normalized = domains
        .map((domain) => domain.trim().toLowerCase())
        .where((domain) => domain.isNotEmpty)
        .toSet();
    final inferred = <String>{};

    for (final service in all) {
      if (service.domains.isEmpty) {
        continue;
      }
      var allCovered = true;
      for (final domain in service.domains) {
        if (!normalized.contains(domain.trim().toLowerCase())) {
          allCovered = false;
          break;
        }
      }
      if (allCovered) {
        inferred.add(service.serviceId);
      }
    }
    return inferred;
  }
}
