import 'service_definitions.dart';

/// Backward-compatible accessors for app domains.
///
/// Canonical source of truth now lives in [ServiceDefinitions].
class SocialMediaDomains {
  SocialMediaDomains._();

  static final Map<String, List<String>> byApp = <String, List<String>>{
    for (final service in ServiceDefinitions.all)
      service.serviceId: List<String>.unmodifiable(
        service.domains
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty),
      ),
  };

  static final Set<String> all = byApp.values
      .expand((domains) => domains)
      .map((domain) => domain.toLowerCase())
      .toSet();

  static String? appForDomain(String domain) {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final service in ServiceDefinitions.all) {
      if (service.matchesDomain(normalized)) {
        return service.serviceId;
      }
    }
    return null;
  }
}
