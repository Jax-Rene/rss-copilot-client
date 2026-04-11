import 'entry_record.dart';
import 'translation_segment.dart';

class EntryDetail {
  const EntryDetail({
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

  factory EntryDetail.fromJson(Map<String, dynamic> json) {
    return EntryDetail(
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

  EntryRecord toRecord({EntryRecord? previous}) {
    return EntryRecord(
      id: id,
      sourceId: sourceId,
      sourceName: sourceName,
      title: title,
      link: link,
      publishedAt: publishedAt,
      summary: summary ?? previous?.summary,
      isRead: isRead,
      foreign: foreign,
      coverImageUrl: previous?.coverImageUrl ?? coverImageUrl,
      contentHtml: contentHtml ?? previous?.contentHtml,
      filterReason: filterReason ?? previous?.filterReason,
      translationSegments: translationSegments.isEmpty
          ? previous?.translationSegments ?? const []
          : translationSegments,
    );
  }
}
