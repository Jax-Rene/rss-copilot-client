import 'package:test/test.dart';
import 'package:rss_copilot_client/src/core/article_queries.dart';
import 'package:rss_copilot_client/src/models/app_section.dart';
import 'package:rss_copilot_client/src/models/entry_record.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';

void main() {
  group('ArticleQueries', () {
    final snapshot = AppSnapshot(
      sources: const [
        FeedSource(
          id: 1,
          name: 'Source',
          folder: 'Engineering',
          rssUrl: 'https://example.com/source.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 1,
        ),
        FeedSource(
          id: 2,
          name: 'Noise',
          folder: 'Design',
          rssUrl: 'https://example.com/noise.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 1,
        ),
      ],
      settings: SettingsBundle.empty(),
      entries: {
        1: EntryRecord(
          id: 1,
          sourceId: 1,
          sourceName: 'Source',
          author: 'Jane Analyst',
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
          readingProgress: 0.45,
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
        4: EntryRecord(
          id: 4,
          sourceId: 2,
          sourceName: 'Noise',
          title: 'Remote folder saved item',
          link: 'https://example.com/4',
          publishedAt: DateTime.utc(2026, 4, 10, 6),
          summary: 'remote folder summary',
          isRead: false,
          foreign: false,
          coverImageUrl: null,
          contentHtml: null,
          filterReason: null,
          translationSegments: const [],
        ),
      },
      listSnapshots: const {
        'feed': [2, 1],
        'noise': [3],
        'saved': [1, 3],
        'source:1': [2, 1],
      },
      listHasMore: const {},
      listCursors: const {},
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

    test('filters entries with local search query', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.feed,
        unreadOnly: false,
        searchQuery: 'unread',
      );

      expect(entries.map((entry) => entry.id).toList(), [1]);
    });

    test('excludes read entries from continue reading results', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.feed,
        unreadOnly: false,
        inProgressOnly: true,
      );

      expect(entries, isEmpty);
    });

    test('matches local search query against author', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.feed,
        unreadOnly: false,
        searchQuery: 'jane analyst',
      );

      expect(entries.map((entry) => entry.id).toList(), [1]);
    });

    test('matches local search query by all whitespace-separated tokens', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.feed,
        unreadOnly: false,
        searchQuery: 'jane unread',
      );

      expect(entries.map((entry) => entry.id).toList(), [1]);
    });

    test('rejects local search when any token is missing', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.feed,
        unreadOnly: false,
        searchQuery: 'jane missing',
      );

      expect(entries, isEmpty);
    });

    test('limits local search to the first eight tokens', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.feed,
        unreadOnly: false,
        searchQuery:
            'jane analyst unread feed item source summary example.com/1 missing',
      );

      expect(entries.map((entry) => entry.id).toList(), [1]);
    });

    test('matches local search query against original link', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.feed,
        unreadOnly: false,
        searchQuery: 'example.com/2',
      );

      expect(entries.map((entry) => entry.id).toList(), [2]);
    });

    test('uses remote search snapshots when available', () {
      final searchKey = ListKey.searchInView('feed', 'summary');
      final remoteSearchSnapshot = snapshot.copyWith(
        listSnapshots: {
          ...snapshot.listSnapshots,
          searchKey.value: [2],
        },
      );

      final entries = ArticleQueries.resolve(
        snapshot: remoteSearchSnapshot,
        section: AppSection.feed,
        unreadOnly: false,
        searchQuery: 'summary',
      );

      expect(entries.map((entry) => entry.id).toList(), [2]);
    });

    test('filters resolved entries by source id', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.saved,
        unreadOnly: false,
        sourceFilterId: 2,
      );

      expect(entries.map((entry) => entry.id).toList(), [3]);
    });

    test('uses remote source snapshots when available', () {
      final sourceKey = ListKey.sourceInView('saved', 2);
      final remoteSourceSnapshot = snapshot.copyWith(
        listSnapshots: {
          ...snapshot.listSnapshots,
          sourceKey.value: [4],
        },
      );

      final entries = ArticleQueries.resolve(
        snapshot: remoteSourceSnapshot,
        section: AppSection.saved,
        unreadOnly: false,
        sourceFilterId: 2,
      );

      expect(entries.map((entry) => entry.id).toList(), [4]);
    });

    test('uses remote source search snapshots when available', () {
      final searchKey = ListKey.searchSourceInView('saved', 2, 'remote');
      final remoteSearchSnapshot = snapshot.copyWith(
        listSnapshots: {
          ...snapshot.listSnapshots,
          searchKey.value: [4],
        },
      );

      final entries = ArticleQueries.resolve(
        snapshot: remoteSearchSnapshot,
        section: AppSection.saved,
        unreadOnly: false,
        sourceFilterId: 2,
        searchQuery: 'remote',
      );

      expect(entries.map((entry) => entry.id).toList(), [4]);
    });

    test('uses remote unread source snapshots when available', () {
      final sourceKey = ListKey.unreadSourceInView('saved', 2);
      final remoteSourceSnapshot = snapshot.copyWith(
        listSnapshots: {
          ...snapshot.listSnapshots,
          sourceKey.value: [4],
        },
      );

      final entries = ArticleQueries.resolve(
        snapshot: remoteSourceSnapshot,
        section: AppSection.saved,
        unreadOnly: true,
        sourceFilterId: 2,
      );

      expect(entries.map((entry) => entry.id).toList(), [4]);
    });

    test('uses remote unread search snapshots when available', () {
      final searchKey = ListKey.searchUnreadInView('feed', 'remote');
      final remoteSearchSnapshot = snapshot.copyWith(
        listSnapshots: {
          ...snapshot.listSnapshots,
          searchKey.value: [4],
        },
      );

      final entries = ArticleQueries.resolve(
        snapshot: remoteSearchSnapshot,
        section: AppSection.feed,
        unreadOnly: true,
        searchQuery: 'remote',
      );

      expect(entries.map((entry) => entry.id).toList(), [4]);
    });

    test('filters resolved entries by source folder', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.saved,
        unreadOnly: false,
        folderFilter: 'Design',
      );

      expect(entries.map((entry) => entry.id).toList(), [3]);
    });

    test('uses remote folder snapshots when available', () {
      final folderKey = ListKey.folderInView('saved', 'Design');
      final remoteFolderSnapshot = snapshot.copyWith(
        listSnapshots: {
          ...snapshot.listSnapshots,
          folderKey.value: [4],
        },
      );

      final entries = ArticleQueries.resolve(
        snapshot: remoteFolderSnapshot,
        section: AppSection.saved,
        unreadOnly: false,
        folderFilter: 'Design',
      );

      expect(entries.map((entry) => entry.id).toList(), [4]);
    });

    test('uses remote folder search snapshots when available', () {
      final searchKey = ListKey.searchFolderInView('saved', 'Design', 'remote');
      final remoteSearchSnapshot = snapshot.copyWith(
        listSnapshots: {
          ...snapshot.listSnapshots,
          searchKey.value: [4],
        },
      );

      final entries = ArticleQueries.resolve(
        snapshot: remoteSearchSnapshot,
        section: AppSection.saved,
        unreadOnly: false,
        folderFilter: 'Design',
        searchQuery: 'remote',
      );

      expect(entries.map((entry) => entry.id).toList(), [4]);
    });

    test('resolves saved entries from the saved snapshot', () {
      final entries = ArticleQueries.resolve(
        snapshot: snapshot,
        section: AppSection.saved,
        unreadOnly: false,
      );

      expect(entries.map((entry) => entry.id).toList(), [1, 3]);
    });

    test('filters entries by partial reading progress', () {
      final inProgressSnapshot = snapshot.copyWith(
        entries: {
          ...snapshot.entries,
          5: EntryRecord(
            id: 5,
            sourceId: 1,
            sourceName: 'Source',
            title: 'Unread in-progress item',
            link: 'https://example.com/5',
            publishedAt: DateTime.utc(2026, 4, 10, 5),
            summary: 'summary 5',
            isRead: false,
            readingProgress: 0.45,
            foreign: false,
            coverImageUrl: null,
            contentHtml: null,
            filterReason: null,
            translationSegments: const [],
          ),
        },
        listSnapshots: {
          ...snapshot.listSnapshots,
          'feed': [5, 2, 1],
        },
      );

      final entries = ArticleQueries.resolve(
        snapshot: inProgressSnapshot,
        section: AppSection.feed,
        unreadOnly: false,
        inProgressOnly: true,
      );

      expect(entries.map((entry) => entry.id).toList(), [5]);
    });
  });
}
