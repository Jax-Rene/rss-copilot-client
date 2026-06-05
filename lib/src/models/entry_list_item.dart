import 'entry_record.dart';

class EntryListItem {
  const EntryListItem({
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

  factory EntryListItem.fromJson(Map<String, dynamic> json) {
    return EntryListItem(
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
    );
  }

  EntryRecord toRecord({EntryRecord? previous}) {
    return EntryRecord(
      id: id,
      sourceId: sourceId,
      sourceName: sourceName,
      sourceIconUrl: sourceIconUrl ?? previous?.sourceIconUrl,
      author: author ?? previous?.author,
      title: title,
      link: link,
      publishedAt: publishedAt,
      summary: summary ?? previous?.summary,
      isRead: isRead,
      isSaved: isSaved,
      readingProgress: readingProgress,
      isNoise: isNoise,
      foreign: foreign,
      filterStatus: filterStatus ?? previous?.filterStatus,
      summaryStatus: summaryStatus ?? previous?.summaryStatus,
      translationStatus: translationStatus ?? previous?.translationStatus,
      coverImageUrl: coverImageUrl ?? previous?.coverImageUrl,
      contentHtml: previous?.contentHtml,
      filterReason: previous?.filterReason,
      translationSegments: previous?.translationSegments ?? const [],
    );
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
