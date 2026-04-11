import 'package:test/test.dart';
import 'package:rss_copilot_client/src/core/article_queries.dart';
import 'package:rss_copilot_client/src/models/app_section.dart';
import 'package:rss_copilot_client/src/models/entry_record.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';

void main() {
  group('ArticleQueries', () {
    final snapshot = AppSnapshot(
      sources: const [],
      settings: SettingsBundle.empty(),
      entries: {
        1: EntryRecord(
          id: 1,
          sourceId: 1,
          sourceName: 'Source',
          title: 'Unread feed item',
          link: 'https://example.com/1',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: 'summary 1',
          isRead: false,
          foreign: false,
          coverImageUrl: null,
          contentHtml: null,
          filterReason: null,
          translationSegments: const [],
        ),
        2: EntryRecord(
          id: 2,
          sourceId: 1,
          sourceName: 'Source',
          title: 'Read feed item',
          link: 'https://example.com/2',
          publishedAt: DateTime.utc(2026, 4, 10, 8),
          summary: 'summary 2',
          isRead: true,
          foreign: false,
          coverImageUrl: null,
          contentHtml: null,
          filterReason: null,
          translationSegments: const [],
        ),
        3: EntryRecord(
          id: 3,
          sourceId: 2,
          sourceName: 'Noise',
          title: 'Noise item',
          link: 'https://example.com/3',
          publishedAt: DateTime.utc(2026, 4, 10, 7),
          summary: 'summary 3',
          isRead: false,
          foreign: true,
          coverImageUrl: null,
          contentHtml: null,
          filterReason: 'noise',
          translationSegments: const [],
        ),
      },
      listSnapshots: const {
        'feed': [2, 1],
        'noise': [3],
        'source:1': [2, 1],
      },
    );

    test('resolves unread feed entries from the feed snapshot', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.feed,
        unreadOnly: true,
      );

      expect(entries.map((entry) => entry.id).toList(), [1]);
    });

    test('resolves source entries from the source-specific snapshot', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.sourceEntries,
        selectedSourceId: 1,
        unreadOnly: false,
      );

      expect(entries.map((entry) => entry.id).toList(), [2, 1]);
    });
  });
}
