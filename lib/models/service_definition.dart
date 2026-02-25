class ServiceDefinition {
  const ServiceDefinition({
    required this.serviceId,
    required this.categoryId,
    required this.displayName,
    required this.domains,
    required this.androidPackages,
    this.criticalDomains = const <String>[],
  });

  final String serviceId;
  final String categoryId;
  final String displayName;
  final List<String> domains;
  final List<String> androidPackages;
  final List<String> criticalDomains;

  bool matchesDomain(String domain) {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final candidate in domains) {
      final normalizedCandidate = candidate.trim().toLowerCase();
      if (normalizedCandidate.isEmpty) {
        continue;
      }
      if (normalized == normalizedCandidate ||
          normalized.endsWith('.$normalizedCandidate')) {
        return true;
      }
    }
    return false;
  }
}
