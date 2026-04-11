import 'package:test/test.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/entry_detail.dart';
import 'package:rss_copilot_client/src/models/entry_list_item.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:rss_copilot_client/src/models/translation_segment.dart';

void main() {
  group('LocalStore', () {
    test('merges list snapshots into cached entry fields', () async {
      final store = await LocalStore.inMemory();

      await store.saveSettings(SettingsBundle.empty());
      await store.upsertSources([
        FeedSource(
          id: 1,
          name: 'Source One',
          rssUrl: 'https://example.com/feed.xml',
          siteUrl: 'https://example.com',
          iconUrl: 'https://example.com/icon.png',
          enabled: true,
          lastFetchedAt: DateTime.utc(2026, 4, 10, 12),
          hasError: false,
          unreadCount: 1,
        ),
      ]);
      await store.upsertEntryDetails([
        EntryDetail(
          id: 42,
          sourceId: 1,
          sourceName: 'Source One',
          title: 'Deep analysis',
          link: 'https://example.com/a',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: 'detail summary',
          isRead: false,
          foreign: true,
          coverImageUrl: null,
          contentHtml: '<p>hello</p>',
          filterReason: 'high signal',
          translationSegments: const [
            TranslationSegment(source: 'hello', translation: '你好'),
          ],
        ),
      ]);

      await store.applyListSnapshot(ListKey.feed, [
        EntryListItem(
          id: 42,
          sourceId: 1,
          sourceName: 'Source One',
          title: 'Deep analysis',
          link: 'https://example.com/a',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: 'list summary',
          isRead: true,
          foreign: true,
          coverImageUrl: 'https://example.com/cover.png',
        ),
      ]);

      final snapshot = await store.loadSnapshot();
      final entry = snapshot.entries[42];

      expect(snapshot.listIds(ListKey.feed), [42]);
      expect(entry, isNotNull);
      expect(entry!.coverImageUrl, 'https://example.com/cover.png');
      expect(entry.summary, 'list summary');
      expect(entry.isRead, isTrue);

      await store.close();
    });

    test('deletes sources and cascades related entries and list ids', () async {
      final store = await LocalStore.inMemory();

      await store.saveSettings(SettingsBundle.empty());
      await store.upsertSources([
        FeedSource(
          id: 9,
          name: 'Noise Source',
          rssUrl: 'https://example.com/noise.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 0,
        ),
      ]);
      await store.upsertEntryDetails([
        EntryDetail(
          id: 99,
          sourceId: 9,
          sourceName: 'Noise Source',
          title: 'Short update',
          link: 'https://example.com/n',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
          contentHtml: null,
          filterReason: null,
          translationSegments: const [],
        ),
      ]);
      await store.applyListSnapshot(ListKey.feed, [
        EntryListItem(
          id: 99,
          sourceId: 9,
          sourceName: 'Noise Source',
          title: 'Short update',
          link: 'https://example.com/n',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
      ]);

      await store.deleteSources([9]);
      final snapshot = await store.loadSnapshot();

      expect(snapshot.sources, isEmpty);
      expect(snapshot.entries, isEmpty);
      expect(snapshot.listIds(ListKey.feed), isEmpty);

      await store.close();
    });
  });
}
