import 'translation_segment.dart';

enum EntryAiProcessingState { none, pending, failed, skipped }

class EntryRecord {
  const EntryRecord({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    this.sourceIconUrl,
    this.author,
    required this.title,
    required this.link,
    required this.publishedAt,
    required this.summary,
    required this.isRead,
    this.isSaved = false,
    this.readingProgress = 0,
    this.isNoise = false,
    required this.foreign,
    this.filterStatus,
    this.summaryStatus,
    this.translationStatus,
    required this.coverImageUrl,
    required this.contentHtml,
    required this.filterReason,
    required this.translationSegments,
  });

  final int id;
  final int sourceId;
  final String sourceName;
  final String? sourceIconUrl;
  final String? author;
  final String title;
  final String link;
  final DateTime publishedAt;
  final String? summary;
  final bool isRead;
  final bool isSaved;
  final double readingProgress;
  final bool isNoise;
  final bool foreign;
  final String? filterStatus;
  final String? summaryStatus;
  final String? translationStatus;
  final String? coverImageUrl;
  final String? contentHtml;
  final String? filterReason;
  final List<TranslationSegment> translationSegments;

  bool get isInProgress =>
      !isRead && readingProgress > 0.02 && readingProgress < 0.98;

  EntryAiProcessingState get aiProcessingState {
    final statuses = [
      filterStatus,
      summaryStatus,
      translationStatus,
    ].whereType<String>().toList(growable: false);
    if (statuses.any((status) => status == 'PENDING')) {
      return EntryAiProcessingState.pending;
    }
    if (statuses.any((status) => status == 'FAILED')) {
      return EntryAiProcessingState.failed;
    }
    if (statuses.isNotEmpty &&
        statuses.every((status) => status == 'SKIPPED')) {
      return EntryAiProcessingState.skipped;
    }
    return EntryAiProcessingState.none;
  }

  factory EntryRecord.fromJson(Map<String, dynamic> json) {
    return EntryRecord(
      id: json['id'] as int,
      sourceId: json['sourceId'] as int,
      sourceName: json['sourceName'] as String? ?? '',
      sourceIconUrl: _normalizeOptionalString(json['sourceIconUrl'] as String?),
      author: _normalizeOptionalString(json['author'] as String?),
      title: json['title'] as String? ?? '',
      link: json['link'] as String? ?? '',
      publishedAt: DateTime.parse(json['publishedAt'] as String).toUtc(),
      summary: json['summary'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      isSaved: json['isSaved'] as bool? ?? false,
      readingProgress: _normalizeReadingProgress(
        (json['readingProgress'] as num?)?.toDouble() ?? 0,
      ),
      isNoise: json['isNoise'] as bool? ?? false,
      foreign: json['foreign'] as bool? ?? false,
      filterStatus: _normalizeAiStatus(json['filterStatus'] as String?),
      summaryStatus: _normalizeAiStatus(json['summaryStatus'] as String?),
      translationStatus: _normalizeAiStatus(
        json['translationStatus'] as String?,
      ),
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
    String? sourceIconUrl,
    bool clearSourceIconUrl = false,
    String? author,
    bool clearAuthor = false,
    String? title,
    String? link,
    DateTime? publishedAt,
    String? summary,
    bool clearSummary = false,
    bool? isRead,
    bool? isSaved,
    double? readingProgress,
    bool? isNoise,
    bool? foreign,
    String? filterStatus,
    bool clearFilterStatus = false,
    String? summaryStatus,
    bool clearSummaryStatus = false,
    String? translationStatus,
    bool clearTranslationStatus = false,
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
      sourceIconUrl: clearSourceIconUrl
          ? null
          : sourceIconUrl ?? this.sourceIconUrl,
      author: clearAuthor ? null : author ?? this.author,
      title: title ?? this.title,
      link: link ?? this.link,
      publishedAt: publishedAt ?? this.publishedAt,
      summary: clearSummary ? null : summary ?? this.summary,
      isRead: isRead ?? this.isRead,
      isSaved: isSaved ?? this.isSaved,
      readingProgress: _normalizeReadingProgress(
        readingProgress ?? this.readingProgress,
      ),
      isNoise: isNoise ?? this.isNoise,
      foreign: foreign ?? this.foreign,
      filterStatus: clearFilterStatus
          ? null
          : _normalizeAiStatus(filterStatus) ?? this.filterStatus,
      summaryStatus: clearSummaryStatus
          ? null
          : _normalizeAiStatus(summaryStatus) ?? this.summaryStatus,
      translationStatus: clearTranslationStatus
          ? null
          : _normalizeAiStatus(translationStatus) ?? this.translationStatus,
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
      'sourceIconUrl': sourceIconUrl,
      'author': author,
      'title': title,
      'link': link,
      'publishedAt': publishedAt.toUtc().toIso8601String(),
      'summary': summary,
      'isRead': isRead,
      'isSaved': isSaved,
      'readingProgress': readingProgress,
      'isNoise': isNoise,
      'foreign': foreign,
      'filterStatus': filterStatus,
      'summaryStatus': summaryStatus,
      'translationStatus': translationStatus,
      'coverImageUrl': coverImageUrl,
      'contentHtml': contentHtml,
      'filterReason': filterReason,
      'translationSegments': translationSegments
          .map((segment) => segment.toJson())
          .toList(),
    };
  }
}

String? _normalizeAiStatus(String? value) {
  final normalized = value?.trim().toUpperCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

double _normalizeReadingProgress(double value) {
  if (value.isNaN || value.isInfinite) {
    return 0;
  }
  return value.clamp(0, 1).toDouble();
}

String? _normalizeOptionalString(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
