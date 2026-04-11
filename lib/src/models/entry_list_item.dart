import 'entry_record.dart';

class EntryListItem {
  const EntryListItem({
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

  factory EntryListItem.fromJson(Map<String, dynamic> json) {
    return EntryListItem(
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
      coverImageUrl: coverImageUrl ?? previous?.coverImageUrl,
      contentHtml: previous?.contentHtml,
      filterReason: previous?.filterReason,
      translationSegments: previous?.translationSegments ?? const [],
    );
  }
}
