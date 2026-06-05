const defaultSourceFolder = '未分组';

class FeedSource {
  const FeedSource({
    required this.id,
    required this.name,
    this.folder = defaultSourceFolder,
    required this.rssUrl,
    required this.siteUrl,
    required this.iconUrl,
    required this.enabled,
    required this.lastFetchedAt,
    required this.hasError,
    this.lastErrorAt,
    this.lastErrorMessage,
    required this.unreadCount,
  });

  final int id;
  final String name;
  final String folder;
  final String rssUrl;
  final String? siteUrl;
  final String? iconUrl;
  final bool enabled;
  final DateTime? lastFetchedAt;
  final bool hasError;
  final DateTime? lastErrorAt;
  final String? lastErrorMessage;
  final int unreadCount;

  factory FeedSource.fromJson(Map<String, dynamic> json) {
    return FeedSource(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      folder: _normalizeFolder(json['folder'] as String?),
      rssUrl: json['rssUrl'] as String? ?? '',
      siteUrl: json['siteUrl'] as String?,
      iconUrl: json['iconUrl'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      lastFetchedAt: _parseDateTime(json['lastFetchedAt'] as String?),
      hasError: json['hasError'] as bool? ?? false,
      lastErrorAt: _parseDateTime(json['lastErrorAt'] as String?),
      lastErrorMessage: _normalizeOptionalString(
        json['lastErrorMessage'] as String?,
      ),
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  FeedSource copyWith({
    int? id,
    String? name,
    String? folder,
    String? rssUrl,
    String? siteUrl,
    String? iconUrl,
    bool clearIconUrl = false,
    bool? enabled,
    DateTime? lastFetchedAt,
    bool clearLastFetchedAt = false,
    bool? hasError,
    DateTime? lastErrorAt,
    bool clearLastErrorAt = false,
    String? lastErrorMessage,
    bool clearLastErrorMessage = false,
    int? unreadCount,
  }) {
    return FeedSource(
      id: id ?? this.id,
      name: name ?? this.name,
      folder: folder ?? this.folder,
      rssUrl: rssUrl ?? this.rssUrl,
      siteUrl: siteUrl ?? this.siteUrl,
      iconUrl: clearIconUrl ? null : iconUrl ?? this.iconUrl,
      enabled: enabled ?? this.enabled,
      lastFetchedAt: clearLastFetchedAt
          ? null
          : lastFetchedAt ?? this.lastFetchedAt,
      hasError: hasError ?? this.hasError,
      lastErrorAt: clearLastErrorAt ? null : lastErrorAt ?? this.lastErrorAt,
      lastErrorMessage: clearLastErrorMessage
          ? null
          : lastErrorMessage ?? this.lastErrorMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'folder': folder,
      'rssUrl': rssUrl,
      'siteUrl': siteUrl,
      'iconUrl': iconUrl,
      'enabled': enabled,
      'lastFetchedAt': lastFetchedAt?.toUtc().toIso8601String(),
      'hasError': hasError,
      'lastErrorAt': lastErrorAt?.toUtc().toIso8601String(),
      'lastErrorMessage': lastErrorMessage,
      'unreadCount': unreadCount,
    };
  }
}

String _normalizeFolder(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty
      ? defaultSourceFolder
      : normalized;
}

DateTime? _parseDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  return DateTime.tryParse(value)?.toUtc();
}

String? _normalizeOptionalString(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
