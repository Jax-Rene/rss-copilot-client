import 'translation_segment.dart';

class EntryRecord {
  const EntryRecord({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.link,
    required this.publishedAt,
    required this.summary,
    required this.isRead,
    required this.foreign,
    required this.coverImageUrl,
    required this.contentHtml,
    required this.filterReason,
    required this.translationSegments,
  });

  final int id;
  final int sourceId;
  final String sourceName;
  final String title;
  final String link;
  final DateTime publishedAt;
  final String? summary;
  final bool isRead;
  final bool foreign;
  final String? coverImageUrl;
  final String? contentHtml;
  final String? filterReason;
  final List<TranslationSegment> translationSegments;

  factory EntryRecord.fromJson(Map<String, dynamic> json) {
    return EntryRecord(
      id: json['id'] as int,
      sourceId: json['sourceId'] as int,
      sourceName: json['sourceName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      link: json['link'] as String? ?? '',
      publishedAt: DateTime.parse(json['publishedAt'] as String).toUtc(),
      summary: json['summary'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      foreign: json['foreign'] as bool? ?? false,
      coverImageUrl: json['coverImageUrl'] as String?,
      contentHtml: json['contentHtml'] as String?,
      filterReason: json['filterReason'] as String?,
      translationSegments:
          ((json['translationSegments'] as List<dynamic>?) ?? const [])
              .map(
                (item) =>
                    TranslationSegment.fromJson(item as Map<String, dynamic>),
              )
              .toList(growable: false),
    );
  }

  EntryRecord copyWith({
    int? id,
    int? sourceId,
    String? sourceName,
    String? title,
    String? link,
    DateTime? publishedAt,
    String? summary,
    bool clearSummary = false,
    bool? isRead,
    bool? foreign,
    String? coverImageUrl,
    bool clearCoverImageUrl = false,
    String? contentHtml,
    bool clearContentHtml = false,
    String? filterReason,
    bool clearFilterReason = false,
    List<TranslationSegment>? translationSegments,
  }) {
    return EntryRecord(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      title: title ?? this.title,
      link: link ?? this.link,
      publishedAt: publishedAt ?? this.publishedAt,
      summary: clearSummary ? null : summary ?? this.summary,
      isRead: isRead ?? this.isRead,
      foreign: foreign ?? this.foreign,
      coverImageUrl: clearCoverImageUrl
          ? null
          : coverImageUrl ?? this.coverImageUrl,
      contentHtml: clearContentHtml ? null : contentHtml ?? this.contentHtml,
      filterReason: clearFilterReason
          ? null
          : filterReason ?? this.filterReason,
      translationSegments: translationSegments ?? this.translationSegments,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'sourceId': sourceId,
      'sourceName': sourceName,
      'title': title,
      'link': link,
      'publishedAt': publishedAt.toUtc().toIso8601String(),
      'summary': summary,
      'isRead': isRead,
      'foreign': foreign,
      'coverImageUrl': coverImageUrl,
      'contentHtml': contentHtml,
      'filterReason': filterReason,
      'translationSegments': translationSegments
          .map((segment) => segment.toJson())
          .toList(),
    };
  }
}
