class NextDnsService {
  static final RegExp _profileIdPattern = RegExp(r'^[a-f0-9]{6}$');

  const NextDnsService();

  String normalizeProfileId(String value) {
    return value.trim().toLowerCase();
  }

  bool isValidProfileId(String value) {
    final normalized = normalizeProfileId(value);
    return _profileIdPattern.hasMatch(normalized);
  }

  String? sanitizedProfileIdOrNull(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = normalizeProfileId(value);
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String dohEndpoint(String profileId) {
    final normalized = normalizeProfileId(profileId);
    return 'https://dns.nextdns.io/$normalized';
  }

  String dotEndpoint(String profileId) {
    final normalized = normalizeProfileId(profileId);
    return '$normalized.dns.nextdns.io';
  }

  String upstreamDnsHost(String profileId) {
    return dotEndpoint(profileId);
  }
}
