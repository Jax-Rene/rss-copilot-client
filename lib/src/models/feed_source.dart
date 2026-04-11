class FeedSource {
  const FeedSource({
    required this.id,
    required this.name,
    required this.rssUrl,
    required this.siteUrl,
    required this.iconUrl,
    required this.enabled,
    required this.lastFetchedAt,
    required this.hasError,
    required this.unreadCount,
  });

  final int id;
  final String name;
  final String rssUrl;
  final String? siteUrl;
  final String? iconUrl;
  final bool enabled;
  final DateTime? lastFetchedAt;
  final bool hasError;
  final int unreadCount;

  factory FeedSource.fromJson(Map<String, dynamic> json) {
    return FeedSource(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      rssUrl: json['rssUrl'] as String? ?? '',
      siteUrl: json['siteUrl'] as String?,
      iconUrl: json['iconUrl'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      lastFetchedAt: _parseDateTime(json['lastFetchedAt'] as String?),
      hasError: json['hasError'] as bool? ?? false,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  FeedSource copyWith({
    int? id,
    String? name,
    String? rssUrl,
    String? siteUrl,
    String? iconUrl,
    bool? enabled,
    DateTime? lastFetchedAt,
    bool clearLastFetchedAt = false,
    bool? hasError,
    int? unreadCount,
  }) {
    return FeedSource(
      id: id ?? this.id,
      name: name ?? this.name,
      rssUrl: rssUrl ?? this.rssUrl,
      siteUrl: siteUrl ?? this.siteUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      enabled: enabled ?? this.enabled,
      lastFetchedAt: clearLastFetchedAt
          ? null
          : lastFetchedAt ?? this.lastFetchedAt,
      hasError: hasError ?? this.hasError,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'rssUrl': rssUrl,
      'siteUrl': siteUrl,
      'iconUrl': iconUrl,
      'enabled': enabled,
      'lastFetchedAt': lastFetchedAt?.toUtc().toIso8601String(),
      'hasError': hasError,
      'unreadCount': unreadCount,
    };
  }
}

DateTime? _parseDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  return DateTime.tryParse(value)?.toUtc();
}
