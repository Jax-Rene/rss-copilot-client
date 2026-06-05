class EntryPageCursor {
  const EntryPageCursor({required this.publishedAt, required this.id});

  final DateTime publishedAt;
  final int id;

  factory EntryPageCursor.fromJson(Map<String, dynamic> json) {
    return EntryPageCursor(
      publishedAt: DateTime.parse(json['publishedAt'] as String).toUtc(),
      id: json['id'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'publishedAt': publishedAt.toUtc().toIso8601String(),
      'id': id,
    };
  }
}
