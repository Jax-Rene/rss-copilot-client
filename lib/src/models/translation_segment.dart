class TranslationSegment {
  const TranslationSegment({required this.source, required this.translation});

  final String source;
  final String translation;

  factory TranslationSegment.fromJson(Map<String, dynamic> json) {
    return TranslationSegment(
      source: json['source'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'source': source, 'translation': translation};
  }
}
