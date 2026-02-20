/// Parser for hosts-format blocklist files.
class BlocklistParser {
  BlocklistParser._();

  static const Set<String> _ignoredHosts = <String>{
    'localhost',
    'broadcasthost',
    'local',
    'ip6-localhost',
    'ip6-loopback',
    'ip6-localnet',
    'ip6-mcastprefix',
    'ip6-allnodes',
    'ip6-allrouters',
    'ip6-allhosts',
  };

  static final RegExp _ipOnlyDomainPattern = RegExp(r'^\d+(?:\.\d+)+$');
  static final RegExp _whitespacePattern = RegExp(r'\s+');

  /// Parses hosts-content text into normalized domain strings.
  ///
  /// This processes input line-by-line to avoid creating a full list of all
  /// lines in memory at once.
  static List<String> parse(String hostsContent) {
    final domains = <String>[];
    if (hostsContent.isEmpty) {
      return domains;
    }

    var lineStart = 0;
    for (var i = 0; i < hostsContent.length; i++) {
      if (hostsContent.codeUnitAt(i) == 10) {
        _consumeLine(
          hostsContent,
          lineStart,
          i,
          domains,
        );
        lineStart = i + 1;
      }
    }

    if (lineStart <= hostsContent.length - 1) {
      _consumeLine(
        hostsContent,
        lineStart,
        hostsContent.length,
        domains,
      );
    }

    return domains;
  }

  static void _consumeLine(
    String source,
    int start,
    int end,
    List<String> output,
  ) {
    if (start > end) {
      return;
    }

    var line = source.substring(start, end).trim();
    if (line.isEmpty || line.startsWith('#')) {
      return;
    }

    final commentIndex = line.indexOf('#');
    if (commentIndex >= 0) {
      line = line.substring(0, commentIndex).trim();
      if (line.isEmpty) {
        return;
      }
    }

    final tokens = line.split(_whitespacePattern);
    if (tokens.length < 2) {
      return;
    }

    final ip = tokens[0];
    if (ip != '0.0.0.0' && ip != '127.0.0.1') {
      return;
    }

    final domain = tokens[1].trim().toLowerCase();
    if (_shouldSkipDomain(domain)) {
      return;
    }

    output.add(domain);
  }

  /// Returns true when a parsed host token should be skipped.
  static bool _shouldSkipDomain(String domain) {
    if (domain.isEmpty) {
      return true;
    }
    if (_ignoredHosts.contains(domain)) {
      return true;
    }
    if (_ipOnlyDomainPattern.hasMatch(domain)) {
      return true;
    }
    return false;
  }
}
