const String categorySocialNetworks = 'social-networks';
const String categoryAdultContent = 'adult-content';

const Map<String, String> _legacyCategoryAliases = <String, String>{
  'social': categorySocialNetworks,
  'adult': categoryAdultContent,
};

String normalizeCategoryId(String rawCategoryId) {
  final normalized = rawCategoryId.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  return _legacyCategoryAliases[normalized] ?? normalized;
}

List<String> normalizeCategoryIds(Iterable<String> rawCategoryIds) {
  final unique = <String>{};
  for (final rawCategoryId in rawCategoryIds) {
    final normalized = normalizeCategoryId(rawCategoryId);
    if (normalized.isNotEmpty) {
      unique.add(normalized);
    }
  }
  return unique.toList(growable: false);
}

Set<String> categoryIdVariants(String rawCategoryId) {
  final canonical = normalizeCategoryId(rawCategoryId);
  if (canonical.isEmpty) {
    return const <String>{};
  }
  final variants = <String>{canonical};
  _legacyCategoryAliases.forEach((legacy, mapped) {
    if (mapped == canonical) {
      variants.add(legacy);
    }
  });
  return variants;
}

void removeCategoryAndAliases(Set<String> categories, String categoryId) {
  final variants = categoryIdVariants(categoryId);
  if (variants.isEmpty) {
    return;
  }
  categories.removeWhere((value) {
    final normalized = normalizeCategoryId(value);
    return variants.contains(normalized);
  });
}
