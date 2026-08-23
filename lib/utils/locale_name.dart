/// Extracts a locale-aware display name from a bilingual JSON map
/// e.g. {"ar": "منتج", "en": "Product"}.
/// Falls back to 'en', then the first non-empty value, then ''.
String localeName(Map<String, dynamic>? nameMap, String languageCode) {
  if (nameMap == null || nameMap.isEmpty) return '';
  final localized = nameMap[languageCode];
  if (localized is String && localized.isNotEmpty) return localized;
  final en = nameMap['en'];
  if (en is String && en.isNotEmpty) return en;
  for (final v in nameMap.values) {
    if (v is String && v.isNotEmpty) return v;
  }
  return '';
}
