import 'package:rss_copilot_client/src/core/reading_metrics.dart';
import 'package:rss_copilot_client/src/models/entry_record.dart';
import 'package:rss_copilot_client/src/models/translation_segment.dart';
import 'package:test/test.dart';

void main() {
  group('ReadingMetrics', () {
    test('estimates minutes from cleaned HTML body', () {
      final body = List.filled(440, 'word').join(' ');
      final entry = _entry(contentHtml: '<article><p>$body</p></article>');

      expect(ReadingMetrics.estimateReadingMinutes(entry), 2);
      expect(ReadingMetrics.readingTimeLabel(entry), '2 分钟');
    });

    test('uses CJK character count for Chinese content', () {
      final body = List.filled(70, '这是一段中文内容').join();
      final entry = _entry(contentHtml: '<p>$body</p>');

      expect(ReadingMetrics.estimateReadingMinutes(entry), 2);
    });

    test('falls back to translated source, summary, then title', () {
      final entry = _entry(
        summary: 'short summary',
        translationSegments: [
          TranslationSegment(
            source: List.filled(221, 'source').join(' '),
            translation: '译文不参与估算',
          ),
        ],
      );

      expect(ReadingMetrics.estimateReadingMinutes(entry), 2);
    });

    test('returns at least one minute for tiny entries', () {
      expect(ReadingMetrics.estimateReadingMinutes(_entry(title: 'Hi')), 1);
    });

    test('summarizes reading time for a queue', () {
      final entries = [
        _entry(id: 1, title: 'One'),
        _entry(
          id: 2,
          contentHtml: '<p>${List.filled(440, 'word').join(' ')}</p>',
        ),
      ];

      expect(ReadingMetrics.estimateTotalMinutes(entries), 3);
      expect(ReadingMetrics.durationLabel(0), '0 分钟');
      expect(ReadingMetrics.durationLabel(45), '45 分钟');
      expect(ReadingMetrics.durationLabel(60), '1 小时');
      expect(ReadingMetrics.durationLabel(75), '1 小时 15 分钟');
    });

    test('estimates remaining minutes from reading progress', () {
      final longEntry = _entry(
        contentHtml: '<p>${List.filled(440, 'word').join(' ')}</p>',
      );
      final halfRead = _entry(
        contentHtml: '<p>${List.filled(440, 'word').join(' ')}</p>',
        readingProgress: 0.5,
      );
      final almostDone = _entry(
        contentHtml: '<p>${List.filled(440, 'word').join(' ')}</p>',
        readingProgress: 0.99,
      );
      final readEntry = _entry(
        contentHtml: '<p>${List.filled(440, 'word').join(' ')}</p>',
        isRead: true,
      );
      final readButInProgress = _entry(
        contentHtml: '<p>${List.filled(440, 'word').join(' ')}</p>',
        isRead: true,
        readingProgress: 0.5,
      );

      expect(ReadingMetrics.estimateReadingMinutes(longEntry), 2);
      expect(ReadingMetrics.estimateRemainingReadingMinutes(longEntry), 2);
      expect(ReadingMetrics.estimateRemainingReadingMinutes(halfRead), 1);
      expect(ReadingMetrics.remainingReadingTimeLabel(halfRead), '剩余 1 分钟');
      expect(ReadingMetrics.estimateRemainingReadingMinutes(almostDone), 0);
      expect(ReadingMetrics.estimateRemainingReadingMinutes(readEntry), 0);
      expect(
        ReadingMetrics.estimateRemainingReadingMinutes(readButInProgress),
        0,
      );
      expect(
        ReadingMetrics.estimateRemainingTotalMinutes([
          longEntry,
          halfRead,
          readEntry,
        ]),
        3,
      );
    });
  });
}

EntryRecord _entry({
  int id = 1,
  String title = 'Entry',
  String? summary,
  String? contentHtml,
  bool isRead = false,
  double readingProgress = 0,
  List<TranslationSegment> translationSegments = const [],
}) {
  return EntryRecord(
    id: id,
    sourceId: 1,
    sourceName: 'Example',
    title: title,
    link: 'https://example.com/1',
    publishedAt: DateTime.utc(2026, 5, 24, 10),
    summary: summary,
    isRead: isRead,
    readingProgress: readingProgress,
    foreign: false,
    coverImageUrl: null,
    contentHtml: contentHtml,
    filterReason: null,
    translationSegments: translationSegments,
  );
}
