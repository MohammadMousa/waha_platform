class Store {
  final int id;
  final String name;
  final Map<String, String>? displayName; // {"ar": "...", "en": "..."} — raw i18n blob, pick key client-side
  final String? currency;

  const Store({
    required this.id,
    required this.name,
    this.displayName,
    this.currency,
  });

  /// Picks the display name for the given language code, falling back to
  /// `en`, then the raw store name — never null, always something to show.
  String label(String languageCode) {
    final map = displayName;
    if (map == null) return name;
    return map[languageCode] ?? map['en'] ?? name;
  }

  factory Store.fromJson(Map<String, dynamic> json) => Store(
        id: json['id'] as int,
        name: json['name'] as String,
        displayName: (json['displayName'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        currency: json['currency'] as String?,
      );
}
