import 'package:test/test.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/entry_detail.dart';
import 'package:rss_copilot_client/src/models/entry_list_item.dart';
import 'package:rss_copilot_client/src/models/entry_page_cursor.dart';
import 'package:rss_copilot_client/src/models/entry_record.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/pending_entry_action.dart';
import 'package:rss_copilot_client/src/models/reader_preferences.dart';
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
          lastErrorAt: DateTime.utc(2026, 4, 10, 11),
          lastErrorMessage: 'previous timeout',
          unreadCount: 1,
        ),
      ]);
      await store.upsertEntryDetails([
        EntryDetail(
          id: 42,
          sourceId: 1,
          sourceName: 'Source One',
          author: 'Jane Analyst',
          title: 'Deep analysis',
          link: 'https://example.com/a',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: 'detail summary',
          isRead: false,
          foreign: true,
          filterStatus: 'SUCCESS',
          summaryStatus: 'PENDING',
          translationStatus: 'SUCCESS',
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
          author: 'Jane Analyst',
          title: 'Deep analysis',
          link: 'https://example.com/a',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: 'list summary',
          isRead: true,
          foreign: true,
          filterStatus: 'SUCCESS',
          summaryStatus: 'SUCCESS',
          translationStatus: 'SUCCESS',
          coverImageUrl: 'https://example.com/cover.png',
        ),
      ]);

      final snapshot = await store.loadSnapshot();
      final entry = snapshot.entries[42];

      expect(snapshot.listIds(ListKey.feed), [42]);
      expect(
        snapshot.sources.single.lastErrorAt,
        DateTime.utc(2026, 4, 10, 11),
      );
      expect(snapshot.sources.single.lastErrorMessage, 'previous timeout');
      expect(entry, isNotNull);
      expect(entry!.coverImageUrl, 'https://example.com/cover.png');
      expect(entry.author, 'Jane Analyst');
      expect(entry.summary, 'list summary');
      expect(entry.isRead, isTrue);
      expect(entry.summaryStatus, 'SUCCESS');
      expect(entry.aiProcessingState, EntryAiProcessingState.none);

      await store.close();
    });

    test('stores cover image from detail snapshots', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.upsertEntryDetails([
        EntryDetail(
          id: 7,
          sourceId: 1,
          sourceName: 'Source One',
          title: 'Visual essay',
          link: 'https://example.com/visual',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: 'detail summary',
          isRead: false,
          foreign: true,
          filterStatus: 'SUCCESS',
          summaryStatus: 'FAILED',
          translationStatus: 'SUCCESS',
          coverImageUrl: 'https://example.com/detail-cover.png',
          contentHtml: '<p>hello</p>',
          filterReason: null,
          translationSegments: const [],
        ),
      ]);

      final snapshot = await store.loadSnapshot();

      expect(
        snapshot.entries[7]?.coverImageUrl,
        'https://example.com/detail-cover.png',
      );
      expect(
        snapshot.entries[7]?.aiProcessingState,
        EntryAiProcessingState.failed,
      );
    });

    test('marks cached AI processing state pending for manual retry', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.upsertEntryDetails([
        EntryDetail(
          id: 8,
          sourceId: 1,
          sourceName: 'Source One',
          title: 'Retryable analysis',
          link: 'https://example.com/retry',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: 'previous summary',
          isRead: false,
          foreign: true,
          filterStatus: 'SUCCESS',
          summaryStatus: 'FAILED',
          translationStatus: 'SKIPPED',
          coverImageUrl: null,
          contentHtml: '<p>hello</p>',
          filterReason: null,
          translationSegments: const [],
        ),
      ]);

      await store.setEntryAiProcessingPending(8);

      final entry = (await store.loadSnapshot()).entries[8];

      expect(entry?.summary, 'previous summary');
      expect(entry?.filterStatus, 'PENDING');
      expect(entry?.summaryStatus, 'PENDING');
      expect(entry?.translationStatus, 'PENDING');
      expect(entry?.aiProcessingState, EntryAiProcessingState.pending);
    });

    test('deletes sources and cascades related entries and list ids', () async {
      final store = await LocalStore.inMemory();

      await store.saveSettings(SettingsBundle.empty());
      await store.upsertSources([
        FeedSource(
          id: 9,
          name: 'Noise Source',
          folder: 'Retired',
          rssUrl: 'https://example.com/noise.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 0,
        ),
        FeedSource(
          id: 10,
          name: 'Kept Source',
          folder: 'Inbox',
          rssUrl: 'https://example.com/kept.xml',
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
        EntryDetail(
          id: 100,
          sourceId: 10,
          sourceName: 'Kept Source',
          title: 'Kept update',
          link: 'https://example.com/kept',
          publishedAt: DateTime.utc(2026, 4, 10, 8),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
          contentHtml: null,
          filterReason: null,
          translationSegments: const [],
        ),
      ]);
      await store.applyListSnapshot(
        ListKey.feed,
        [
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
          EntryListItem(
            id: 100,
            sourceId: 10,
            sourceName: 'Kept Source',
            title: 'Kept update',
            link: 'https://example.com/kept',
            publishedAt: DateTime.utc(2026, 4, 10, 8),
            summary: null,
            isRead: false,
            foreign: false,
            coverImageUrl: null,
          ),
        ],
        hasMore: true,
        nextCursor: EntryPageCursor(
          publishedAt: DateTime.utc(2026, 4, 10, 8),
          id: 100,
        ),
      );
      final deletedScopedItem = _localStoreItem(
        99,
        sourceId: 9,
        sourceName: 'Noise Source',
      );
      final keptScopedItem = _localStoreItem(
        100,
        sourceId: 10,
        sourceName: 'Kept Source',
      );
      await store.applyListSnapshot(
        ListKey.source(9),
        [deletedScopedItem],
        hasMore: true,
        nextCursor: EntryPageCursor(
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          id: 99,
        ),
      );
      await store.applyListSnapshot(ListKey.sourceInView('feed', 9), [
        deletedScopedItem,
      ]);
      await store.applyListSnapshot(ListKey.unreadSourceInView('feed', 9), [
        deletedScopedItem,
      ]);
      await store.applyListSnapshot(ListKey.searchSource(9, 'update'), [
        deletedScopedItem,
      ]);
      await store.applyListSnapshot(
        ListKey.searchSourceInView('feed', 9, 'update'),
        [deletedScopedItem],
      );
      await store.applyListSnapshot(
        ListKey.searchUnreadSourceInView('feed', 9, 'update'),
        [deletedScopedItem],
      );
      await store.applyListSnapshot(
        ListKey.folderInView('feed', 'Retired'),
        [deletedScopedItem],
        hasMore: true,
        nextCursor: EntryPageCursor(
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          id: 99,
        ),
      );
      await store.applyListSnapshot(
        ListKey.unreadFolderInView('feed', 'Retired'),
        [deletedScopedItem],
      );
      await store.applyListSnapshot(
        ListKey.searchFolderInView('feed', 'Retired', 'update'),
        [deletedScopedItem],
      );
      await store.applyListSnapshot(
        ListKey.searchUnreadFolderInView('feed', 'Retired', 'update'),
        [deletedScopedItem],
      );
      await store.applyListSnapshot(ListKey.source(10), [keptScopedItem]);
      await store.applyListSnapshot(
        ListKey.folderInView('feed', 'Inbox'),
        [keptScopedItem],
        hasMore: true,
        nextCursor: EntryPageCursor(
          publishedAt: DateTime.utc(2026, 4, 10, 8),
          id: 100,
        ),
      );
      await store.savePendingEntryAction(
        const PendingEntryAction(
          type: PendingEntryActionType.savedState,
          entryId: 99,
          updatedAtMicros: 1,
          boolValue: true,
        ),
      );
      await store.savePendingEntryAction(
        const PendingEntryAction(
          type: PendingEntryActionType.readState,
          entryId: 100,
          updatedAtMicros: 2,
          boolValue: true,
        ),
      );

      await store.deleteSources([9]);
      final snapshot = await store.loadSnapshot();
      final pendingActions = await store.loadPendingEntryActions();

      expect(snapshot.sources.map((source) => source.id), [10]);
      expect(snapshot.entries.keys, [100]);
      expect(snapshot.listIds(ListKey.feed), [100]);
      expect(snapshot.hasMore(ListKey.feed), isTrue);
      expect(snapshot.cursorFor(ListKey.feed)?.id, 100);
      expect(snapshot.hasListSnapshot(ListKey.source(9)), isFalse);
      expect(
        snapshot.hasListSnapshot(ListKey.sourceInView('feed', 9)),
        isFalse,
      );
      expect(
        snapshot.hasListSnapshot(ListKey.unreadSourceInView('feed', 9)),
        isFalse,
      );
      expect(
        snapshot.hasListSnapshot(ListKey.searchSource(9, 'update')),
        isFalse,
      );
      expect(
        snapshot.hasListSnapshot(
          ListKey.searchSourceInView('feed', 9, 'update'),
        ),
        isFalse,
      );
      expect(
        snapshot.hasListSnapshot(
          ListKey.searchUnreadSourceInView('feed', 9, 'update'),
        ),
        isFalse,
      );
      expect(
        snapshot.hasListSnapshot(ListKey.folderInView('feed', 'Retired')),
        isFalse,
      );
      expect(
        snapshot.hasListSnapshot(ListKey.unreadFolderInView('feed', 'Retired')),
        isFalse,
      );
      expect(
        snapshot.hasListSnapshot(
          ListKey.searchFolderInView('feed', 'Retired', 'update'),
        ),
        isFalse,
      );
      expect(
        snapshot.hasListSnapshot(
          ListKey.searchUnreadFolderInView('feed', 'Retired', 'update'),
        ),
        isFalse,
      );
      expect(snapshot.listIds(ListKey.source(10)), [100]);
      expect(snapshot.listIds(ListKey.folderInView('feed', 'Inbox')), [100]);
      expect(snapshot.hasMore(ListKey.folderInView('feed', 'Inbox')), isTrue);
      expect(
        snapshot.cursorFor(ListKey.folderInView('feed', 'Inbox'))?.id,
        100,
      );
      expect(pendingActions.map((action) => action.entryId), [100]);

      await store.close();
    });

    test(
      'clears cached source entries when the source RSS URL changes',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.upsertSources([
          FeedSource(
            id: 9,
            name: 'Moved Source',
            folder: 'Inbox',
            rssUrl: 'https://old.example/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: DateTime.utc(2026, 4, 10, 9),
            hasError: false,
            unreadCount: 1,
          ),
          FeedSource(
            id: 10,
            name: 'Kept Source',
            folder: 'Inbox',
            rssUrl: 'https://kept.example/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 0,
          ),
        ]);
        final staleItem = _localStoreItem(
          99,
          sourceId: 9,
          sourceName: 'Moved Source',
        );
        final keptItem = _localStoreItem(
          100,
          sourceId: 10,
          sourceName: 'Kept Source',
        );
        await store.applyListSnapshot(ListKey.feed, [staleItem, keptItem]);
        await store.applyListSnapshot(ListKey.source(9), [staleItem]);
        await store.applyListSnapshot(ListKey.sourceInView('feed', 9), [
          staleItem,
        ]);
        await store.applyListSnapshot(ListKey.searchSource(9, 'old'), [
          staleItem,
        ]);
        await store.applyListSnapshot(ListKey.folderInView('feed', 'Inbox'), [
          staleItem,
          keptItem,
        ]);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readingProgress,
            entryId: 99,
            updatedAtMicros: 1,
            doubleValue: 0.4,
          ),
        );
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readState,
            entryId: 100,
            updatedAtMicros: 2,
            boolValue: true,
          ),
        );

        await store.upsertSources([
          FeedSource(
            id: 9,
            name: 'Moved Source',
            folder: 'Inbox',
            rssUrl: 'https://new.example/rss.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 0,
          ),
        ]);

        final snapshot = await store.loadSnapshot();
        final pendingActions = await store.loadPendingEntryActions();

        expect(
          snapshot.sources.map((source) => source.id),
          containsAll([9, 10]),
        );
        expect(snapshot.sourceById(9)?.rssUrl, 'https://new.example/rss.xml');
        expect(snapshot.entries.keys, [100]);
        expect(snapshot.listIds(ListKey.feed), [100]);
        expect(snapshot.listIds(ListKey.folderInView('feed', 'Inbox')), [100]);
        expect(snapshot.hasListSnapshot(ListKey.source(9)), isFalse);
        expect(
          snapshot.hasListSnapshot(ListKey.sourceInView('feed', 9)),
          isFalse,
        );
        expect(
          snapshot.hasListSnapshot(ListKey.searchSource(9, 'old')),
          isFalse,
        );
        expect(pendingActions.map((action) => action.entryId), [100]);
      },
    );

    test(
      'keeps cached source entries when refresh canonicalizes RSS URL',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.upsertSources([
          FeedSource(
            id: 9,
            name: 'Moved Source',
            folder: 'Inbox',
            rssUrl: 'https://old.example/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: DateTime.utc(2026, 4, 10, 9),
            hasError: false,
            unreadCount: 1,
          ),
          FeedSource(
            id: 10,
            name: 'Kept Source',
            folder: 'Inbox',
            rssUrl: 'https://kept.example/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 0,
          ),
        ]);
        final movedItem = _localStoreItem(
          99,
          sourceId: 9,
          sourceName: 'Moved Source',
        );
        final keptItem = _localStoreItem(
          100,
          sourceId: 10,
          sourceName: 'Kept Source',
        );
        await store.applyListSnapshot(ListKey.feed, [movedItem, keptItem]);
        await store.applyListSnapshot(ListKey.source(9), [movedItem]);
        await store.applyListSnapshot(ListKey.sourceInView('feed', 9), [
          movedItem,
        ]);
        await store.applyListSnapshot(ListKey.folderInView('feed', 'Inbox'), [
          movedItem,
          keptItem,
        ]);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readingProgress,
            entryId: 99,
            updatedAtMicros: 1,
            doubleValue: 0.4,
          ),
        );

        await store.upsertSources([
          FeedSource(
            id: 9,
            name: 'Canonical Source',
            folder: 'Inbox',
            rssUrl: 'https://canonical.example/final-feed.xml',
            siteUrl: 'https://canonical.example/',
            iconUrl: null,
            enabled: true,
            lastFetchedAt: DateTime.utc(2026, 4, 10, 10),
            hasError: false,
            unreadCount: 1,
          ),
        ]);

        final snapshot = await store.loadSnapshot();
        final pendingActions = await store.loadPendingEntryActions();

        expect(
          snapshot.sourceById(9)?.rssUrl,
          'https://canonical.example/final-feed.xml',
        );
        expect(snapshot.entries.keys, containsAll([99, 100]));
        expect(snapshot.entries[99]?.sourceName, 'Canonical Source');
        expect(snapshot.listIds(ListKey.feed), [100, 99]);
        expect(snapshot.listIds(ListKey.source(9)), [99]);
        expect(snapshot.listIds(ListKey.sourceInView('feed', 9)), [99]);
        expect(snapshot.listIds(ListKey.folderInView('feed', 'Inbox')), [
          100,
          99,
        ]);
        expect(pendingActions.map((action) => action.entryId), [99]);
      },
    );

    test(
      'delete entries removes cached list references and pending actions',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);
        await store.upsertSources([
          FeedSource(
            id: 9,
            name: 'Source',
            folder: 'Inbox',
            rssUrl: 'https://source.example/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 2,
          ),
        ]);
        final staleItem = _localStoreItem(
          99,
          sourceId: 9,
          sourceName: 'Source',
        );
        final keptItem = _localStoreItem(
          100,
          sourceId: 9,
          sourceName: 'Source',
        );
        await store.applyListSnapshot(ListKey.feed, [staleItem, keptItem]);
        await store.applyListSnapshot(ListKey.source(9), [staleItem, keptItem]);
        await store.applyListSnapshot(ListKey.sourceInView('feed', 9), [
          staleItem,
          keptItem,
        ]);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readingProgress,
            entryId: 99,
            updatedAtMicros: 1,
            doubleValue: 0.4,
          ),
        );
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readState,
            entryId: 100,
            updatedAtMicros: 2,
            boolValue: true,
          ),
        );

        await store.deleteEntries([99]);

        final snapshot = await store.loadSnapshot();
        final pendingActions = await store.loadPendingEntryActions();

        expect(snapshot.entries.containsKey(99), isFalse);
        expect(snapshot.entries.containsKey(100), isTrue);
        expect(snapshot.listIds(ListKey.feed), [100]);
        expect(snapshot.listIds(ListKey.source(9)), [100]);
        expect(snapshot.listIds(ListKey.sourceInView('feed', 9)), [100]);
        expect(snapshot.sourceById(9)?.unreadCount, 1);
        expect(pendingActions.map((action) => action.entryId), [100]);
      },
    );

    test(
      'replaces remote snapshot and preserves local reader preferences',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.saveReaderPreferences(
          const ReaderPreferences(
            fontSize: 20,
            lineHeight: 1.8,
            width: ReaderWidth.wide,
            entrySortOrder: EntrySortOrder.shortestFirst,
            entryQueueFilter: EntryQueueFilter.unread,
            entryListDensity: EntryListDensity.compact,
            sourceListSortOrder: SourceListSortOrder.health,
            collapsedEntryDateSections: ['2026-04-10'],
            collapsedSourceFolders: ['Engineering'],
            showTranslations: false,
            lastSection: 'saved',
            lastSelectedEntryId: 99,
          ),
        );
        await store.upsertSources([
          FeedSource(
            id: 1,
            name: 'Deleted Source',
            rssUrl: 'https://old.example/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 1,
          ),
        ]);
        await store.applyListSnapshot(
          ListKey.feed,
          [
            EntryListItem(
              id: 99,
              sourceId: 1,
              sourceName: 'Deleted Source',
              title: 'Stale article',
              link: 'https://old.example/article',
              publishedAt: DateTime.utc(2026, 4, 10, 9),
              summary: null,
              isRead: false,
              foreign: false,
              coverImageUrl: null,
            ),
          ],
          hasMore: true,
          nextCursor: EntryPageCursor(
            publishedAt: DateTime.utc(2026, 4, 10, 9),
            id: 99,
          ),
        );

        await store.replaceRemoteSnapshot(
          settings: const SettingsBundle.empty(),
          sources: [
            FeedSource(
              id: 2,
              name: 'Current Source',
              rssUrl: 'https://new.example/feed.xml',
              siteUrl: null,
              iconUrl: null,
              enabled: true,
              lastFetchedAt: null,
              hasError: false,
              unreadCount: 0,
            ),
          ],
          entries: [
            EntryDetail(
              id: 2,
              sourceId: 2,
              sourceName: 'Current Source',
              title: 'Current article',
              link: 'https://new.example/article',
              publishedAt: DateTime.utc(2026, 4, 11, 9),
              summary: 'Current summary',
              isRead: true,
              foreign: false,
              coverImageUrl: null,
              contentHtml: '<p>current</p>',
              filterReason: null,
              translationSegments: const [],
            ),
          ],
        );

        final snapshot = await store.loadSnapshot();
        final preferences = await store.loadReaderPreferences();

        expect(snapshot.sources.map((source) => source.id), [2]);
        expect(snapshot.entries.keys, [2]);
        expect(snapshot.listIds(ListKey.all), [2]);
        expect(snapshot.listIds(ListKey.feed), [2]);
        expect(snapshot.listIds(ListKey.noise), isEmpty);
        expect(snapshot.listIds(ListKey.saved), isEmpty);
        expect(snapshot.hasMore(ListKey.feed), isFalse);
        expect(snapshot.cursorFor(ListKey.feed), isNull);
        expect(preferences.fontSize, 20);
        expect(preferences.entryQueueFilter, EntryQueueFilter.unread);
        expect(preferences.sourceListSortOrder, SourceListSortOrder.health);
        expect(preferences.collapsedEntryDateSections, ['2026-04-10']);
        expect(preferences.collapsedSourceFolders, ['Engineering']);
        expect(preferences.lastSelectedEntryId, 99);
      },
    );

    test(
      'keeps source folders and sorts sources by folder then name',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.upsertSources([
          FeedSource(
            id: 2,
            name: 'Beta',
            folder: 'Work',
            rssUrl: 'https://example.com/beta.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 0,
          ),
          FeedSource(
            id: 1,
            name: 'Alpha',
            folder: 'Personal',
            rssUrl: 'https://example.com/alpha.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 0,
          ),
        ]);

        final snapshot = await store.loadSnapshot();

        expect(snapshot.sources.map((source) => source.folder), [
          'Personal',
          'Work',
        ]);
        expect(snapshot.sources.map((source) => source.name), [
          'Alpha',
          'Beta',
        ]);
      },
    );

    test(
      'reconciles cached folder and search lists when source changes',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.upsertSources([
          FeedSource(
            id: 1,
            name: 'Original Source',
            folder: 'Engineering',
            rssUrl: 'https://example.com/feed.xml',
            siteUrl: null,
            iconUrl: 'https://example.com/original.ico',
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 1,
          ),
        ]);

        final item = EntryListItem(
          id: 1,
          sourceId: 1,
          sourceName: 'Original Source',
          sourceIconUrl: 'https://example.com/original.ico',
          title: 'Backlog article',
          link: 'https://example.com/1',
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        );
        await store.applyListSnapshot(ListKey.feed, [item]);
        await store.applyListSnapshot(ListKey.source(1), [item]);
        await store.applyListSnapshot(
          ListKey.folderInView('feed', 'Engineering'),
          [item],
          hasMore: true,
          nextCursor: EntryPageCursor(
            publishedAt: DateTime.utc(2026, 4, 10, 10),
            id: 1,
          ),
        );
        await store.applyListSnapshot(
          ListKey.unreadFolderInView('feed', 'Engineering'),
          [item],
        );
        await store.applyListSnapshot(
          ListKey.folderInView('feed', 'Product'),
          const [],
        );
        await store.applyListSnapshot(
          ListKey.unreadFolderInView('feed', 'Product'),
          const [],
        );
        await store.applyListSnapshot(
          ListKey.searchInView('feed', 'original'),
          [item],
        );
        await store.applyListSnapshot(
          ListKey.searchInView('feed', 'renamed'),
          const [],
        );
        await store.applyListSnapshot(
          ListKey.searchFolderInView('feed', 'Engineering', 'original'),
          [item],
        );
        await store.applyListSnapshot(
          ListKey.searchUnreadFolderInView('feed', 'Engineering', 'original'),
          [item],
        );
        await store.applyListSnapshot(
          ListKey.searchFolderInView('feed', 'Product', 'renamed'),
          const [],
        );
        await store.applyListSnapshot(
          ListKey.searchUnreadFolderInView('feed', 'Product', 'renamed'),
          const [],
        );

        await store.upsertSources([
          FeedSource(
            id: 1,
            name: 'Renamed Source',
            folder: 'Product',
            rssUrl: 'https://example.com/feed.xml',
            siteUrl: null,
            iconUrl: 'https://example.com/renamed.ico',
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 1,
          ),
        ]);

        final snapshot = await store.loadSnapshot();

        expect(snapshot.entries[1]?.sourceName, 'Renamed Source');
        expect(
          snapshot.entries[1]?.sourceIconUrl,
          'https://example.com/renamed.ico',
        );
        expect(snapshot.listIds(ListKey.feed), [1]);
        expect(snapshot.listIds(ListKey.source(1)), [1]);
        expect(
          snapshot.hasListSnapshot(ListKey.folderInView('feed', 'Engineering')),
          isFalse,
        );
        expect(
          snapshot.hasListSnapshot(
            ListKey.unreadFolderInView('feed', 'Engineering'),
          ),
          isFalse,
        );
        expect(
          snapshot.hasListSnapshot(
            ListKey.searchFolderInView('feed', 'Engineering', 'original'),
          ),
          isFalse,
        );
        expect(
          snapshot.hasListSnapshot(
            ListKey.searchUnreadFolderInView('feed', 'Engineering', 'original'),
          ),
          isFalse,
        );
        expect(snapshot.listIds(ListKey.folderInView('feed', 'Product')), [1]);
        expect(
          snapshot.listIds(ListKey.unreadFolderInView('feed', 'Product')),
          [1],
        );
        expect(
          snapshot.listIds(ListKey.searchInView('feed', 'original')),
          isEmpty,
        );
        expect(snapshot.listIds(ListKey.searchInView('feed', 'renamed')), [1]);
        expect(
          snapshot.listIds(
            ListKey.searchFolderInView('feed', 'Product', 'renamed'),
          ),
          [1],
        );
        expect(
          snapshot.listIds(
            ListKey.searchUnreadFolderInView('feed', 'Product', 'renamed'),
          ),
          [1],
        );
      },
    );

    test('appends paged list snapshots and stores the next cursor', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.applyListSnapshot(
        ListKey.feed,
        [
          EntryListItem(
            id: 1,
            sourceId: 1,
            sourceName: 'Source',
            title: 'First',
            link: 'https://example.com/1',
            publishedAt: DateTime.utc(2026, 4, 10, 10),
            summary: null,
            isRead: false,
            foreign: false,
            coverImageUrl: null,
          ),
        ],
        hasMore: true,
        nextCursor: EntryPageCursor(
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          id: 1,
        ),
      );
      await store.applyListSnapshot(ListKey.feed, [
        EntryListItem(
          id: 2,
          sourceId: 1,
          sourceName: 'Source',
          title: 'Second',
          link: 'https://example.com/2',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
      ], append: true);

      final snapshot = await store.loadSnapshot();

      expect(snapshot.listIds(ListKey.feed), [1, 2]);
      expect(snapshot.hasMore(ListKey.feed), isFalse);
      expect(snapshot.cursorFor(ListKey.feed), isNull);
    });

    test('clears list pagination without dropping loaded entries', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.applyListSnapshot(
        ListKey.feed,
        [
          EntryListItem(
            id: 1,
            sourceId: 1,
            sourceName: 'Source',
            title: 'First',
            link: 'https://example.com/1',
            publishedAt: DateTime.utc(2026, 4, 10, 10),
            summary: null,
            isRead: false,
            foreign: false,
            coverImageUrl: null,
          ),
        ],
        hasMore: true,
        nextCursor: EntryPageCursor(
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          id: 1,
        ),
      );

      await store.clearListPagination(ListKey.feed);

      final snapshot = await store.loadSnapshot();

      expect(snapshot.listIds(ListKey.feed), [1]);
      expect(snapshot.entries[1]?.title, 'First');
      expect(snapshot.hasMore(ListKey.feed), isFalse);
      expect(snapshot.cursorFor(ListKey.feed), isNull);
    });

    test('updates entry saved state and maintains the saved list', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.applyListSnapshot(ListKey.feed, [
        EntryListItem(
          id: 1,
          sourceId: 1,
          sourceName: 'Source',
          title: 'First',
          link: 'https://example.com/1',
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
        EntryListItem(
          id: 2,
          sourceId: 1,
          sourceName: 'Source',
          title: 'Second',
          link: 'https://example.com/2',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
      ]);

      await store.setEntrySaved(2, true);
      await store.setEntrySaved(1, true);
      var snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]!.isSaved, isTrue);
      expect(snapshot.entries[2]!.isSaved, isTrue);
      expect(snapshot.listIds(ListKey.saved), [1, 2]);

      await store.setEntrySaved(1, false);
      snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]!.isSaved, isFalse);
      expect(snapshot.listIds(ListKey.saved), [2]);
    });

    test('updates cached saved filters when saved state changes', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.upsertSources([
        FeedSource(
          id: 1,
          name: 'Source',
          folder: 'Engineering',
          rssUrl: 'https://example.com/feed.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 1,
        ),
      ]);

      final first = EntryListItem(
        id: 1,
        sourceId: 1,
        sourceName: 'Source',
        title: 'First bookmark',
        link: 'https://example.com/1',
        publishedAt: DateTime.utc(2026, 4, 10, 10),
        summary: null,
        isRead: false,
        foreign: false,
        coverImageUrl: null,
      );
      await store.applyListSnapshot(ListKey.feed, [first]);
      await store.applyListSnapshot(ListKey.saved, const []);
      await store.applyListSnapshot(ListKey.sourceInView('saved', 1), const []);
      await store.applyListSnapshot(
        ListKey.folderInView('saved', 'Engineering'),
        const [],
      );
      await store.applyListSnapshot(ListKey.unreadInView('saved'), const []);
      await store.applyListSnapshot(
        ListKey.searchInView('saved', 'first'),
        const [],
      );
      await store.applyListSnapshot(
        ListKey.searchSourceInView('saved', 1, 'first'),
        const [],
      );
      await store.applyListSnapshot(
        ListKey.searchFolderInView('saved', 'Engineering', 'first'),
        const [],
      );
      await store.applyListSnapshot(
        ListKey.searchUnreadInView('saved', 'first'),
        const [],
      );

      await store.setEntrySaved(1, true);
      var snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]?.isSaved, isTrue);
      expect(snapshot.listIds(ListKey.saved), [1]);
      expect(snapshot.listIds(ListKey.sourceInView('saved', 1)), [1]);
      expect(snapshot.listIds(ListKey.folderInView('saved', 'Engineering')), [
        1,
      ]);
      expect(snapshot.listIds(ListKey.unreadInView('saved')), [1]);
      expect(snapshot.listIds(ListKey.searchInView('saved', 'first')), [1]);
      expect(
        snapshot.listIds(ListKey.searchSourceInView('saved', 1, 'first')),
        [1],
      );
      expect(
        snapshot.listIds(
          ListKey.searchFolderInView('saved', 'Engineering', 'first'),
        ),
        [1],
      );
      expect(snapshot.listIds(ListKey.searchUnreadInView('saved', 'first')), [
        1,
      ]);

      await store.setEntrySaved(1, false);
      snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]?.isSaved, isFalse);
      expect(snapshot.listIds(ListKey.saved), isEmpty);
      expect(snapshot.listIds(ListKey.sourceInView('saved', 1)), isEmpty);
      expect(
        snapshot.listIds(ListKey.folderInView('saved', 'Engineering')),
        isEmpty,
      );
      expect(snapshot.listIds(ListKey.unreadInView('saved')), isEmpty);
      expect(snapshot.listIds(ListKey.searchInView('saved', 'first')), isEmpty);
      expect(
        snapshot.listIds(ListKey.searchSourceInView('saved', 1, 'first')),
        isEmpty,
      );
      expect(
        snapshot.listIds(
          ListKey.searchFolderInView('saved', 'Engineering', 'first'),
        ),
        isEmpty,
      );
      expect(
        snapshot.listIds(ListKey.searchUnreadInView('saved', 'first')),
        isEmpty,
      );
    });

    test('moves entries between feed and noise lists', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.upsertSources([
        FeedSource(
          id: 1,
          name: 'Source',
          folder: 'Engineering',
          rssUrl: 'https://example.com/feed.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 2,
        ),
      ]);
      await store.applyListSnapshot(ListKey.feed, [
        EntryListItem(
          id: 1,
          sourceId: 1,
          sourceName: 'Source',
          title: 'First',
          link: 'https://example.com/1',
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
        EntryListItem(
          id: 2,
          sourceId: 1,
          sourceName: 'Source',
          title: 'Second',
          link: 'https://example.com/2',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
      ]);
      await store.applyListSnapshot(ListKey.sourceInView('feed', 1), [
        EntryListItem(
          id: 1,
          sourceId: 1,
          sourceName: 'Source',
          title: 'First',
          link: 'https://example.com/1',
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
        EntryListItem(
          id: 2,
          sourceId: 1,
          sourceName: 'Source',
          title: 'Second',
          link: 'https://example.com/2',
          publishedAt: DateTime.utc(2026, 4, 10, 9),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
      ]);
      await store
          .applyListSnapshot(ListKey.folderInView('feed', 'Engineering'), [
            EntryListItem(
              id: 1,
              sourceId: 1,
              sourceName: 'Source',
              title: 'First',
              link: 'https://example.com/1',
              publishedAt: DateTime.utc(2026, 4, 10, 10),
              summary: null,
              isRead: false,
              foreign: false,
              coverImageUrl: null,
            ),
            EntryListItem(
              id: 2,
              sourceId: 1,
              sourceName: 'Source',
              title: 'Second',
              link: 'https://example.com/2',
              publishedAt: DateTime.utc(2026, 4, 10, 9),
              summary: null,
              isRead: false,
              foreign: false,
              coverImageUrl: null,
            ),
          ]);
      await store.applyListSnapshot(ListKey.noise, const []);
      await store.applyListSnapshot(ListKey.sourceInView('noise', 1), const []);
      await store.applyListSnapshot(
        ListKey.folderInView('noise', 'Engineering'),
        const [],
      );

      await store.setEntryNoise(1, true);
      var snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]!.isNoise, isTrue);
      expect(snapshot.entries[1]!.filterReason, '手动移入噪音箱');
      expect(snapshot.listIds(ListKey.feed), [2]);
      expect(snapshot.listIds(ListKey.noise), [1]);
      expect(snapshot.listIds(ListKey.sourceInView('feed', 1)), [2]);
      expect(snapshot.listIds(ListKey.sourceInView('noise', 1)), [1]);
      expect(snapshot.listIds(ListKey.folderInView('feed', 'Engineering')), [
        2,
      ]);
      expect(snapshot.listIds(ListKey.folderInView('noise', 'Engineering')), [
        1,
      ]);
      expect(snapshot.sourceById(1)?.unreadCount, 1);

      await store.setEntryNoise(1, false);
      snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]!.isNoise, isFalse);
      expect(snapshot.entries[1]!.filterReason, isNull);
      expect(snapshot.listIds(ListKey.feed), [1, 2]);
      expect(snapshot.listIds(ListKey.noise), isEmpty);
      expect(snapshot.listIds(ListKey.sourceInView('feed', 1)), [1, 2]);
      expect(snapshot.listIds(ListKey.sourceInView('noise', 1)), isEmpty);
      expect(snapshot.listIds(ListKey.folderInView('feed', 'Engineering')), [
        1,
        2,
      ]);
      expect(
        snapshot.listIds(ListKey.folderInView('noise', 'Engineering')),
        isEmpty,
      );
      expect(snapshot.sourceById(1)?.unreadCount, 2);
    });

    test(
      'updates cached search filters when moving entries to noise',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.upsertSources([
          FeedSource(
            id: 1,
            name: 'Source',
            folder: 'Engineering',
            rssUrl: 'https://example.com/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 1,
          ),
        ]);

        final first = EntryListItem(
          id: 1,
          sourceId: 1,
          sourceName: 'Source',
          title: 'First noisy candidate',
          link: 'https://example.com/1',
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        );
        await store.applyListSnapshot(ListKey.feed, [first]);
        await store.applyListSnapshot(ListKey.noise, const []);
        await store.applyListSnapshot(ListKey.searchInView('feed', 'first'), [
          first,
        ]);
        await store.applyListSnapshot(
          ListKey.searchInView('noise', 'first'),
          [],
        );
        await store.applyListSnapshot(
          ListKey.searchSourceInView('feed', 1, 'first'),
          [first],
        );
        await store.applyListSnapshot(
          ListKey.searchSourceInView('noise', 1, 'first'),
          const [],
        );
        await store.applyListSnapshot(
          ListKey.searchFolderInView('feed', 'Engineering', 'first'),
          [first],
        );
        await store.applyListSnapshot(
          ListKey.searchFolderInView('noise', 'Engineering', 'first'),
          const [],
        );
        await store.applyListSnapshot(
          ListKey.searchUnreadInView('feed', 'first'),
          [first],
        );
        await store.applyListSnapshot(
          ListKey.searchUnreadInView('noise', 'first'),
          const [],
        );

        await store.setEntryNoise(1, true);
        var snapshot = await store.loadSnapshot();

        expect(
          snapshot.listIds(ListKey.searchInView('feed', 'first')),
          isEmpty,
        );
        expect(snapshot.listIds(ListKey.searchInView('noise', 'first')), [1]);
        expect(
          snapshot.listIds(ListKey.searchSourceInView('feed', 1, 'first')),
          isEmpty,
        );
        expect(
          snapshot.listIds(ListKey.searchSourceInView('noise', 1, 'first')),
          [1],
        );
        expect(
          snapshot.listIds(
            ListKey.searchFolderInView('feed', 'Engineering', 'first'),
          ),
          isEmpty,
        );
        expect(
          snapshot.listIds(
            ListKey.searchFolderInView('noise', 'Engineering', 'first'),
          ),
          [1],
        );
        expect(
          snapshot.listIds(ListKey.searchUnreadInView('feed', 'first')),
          isEmpty,
        );
        expect(snapshot.listIds(ListKey.searchUnreadInView('noise', 'first')), [
          1,
        ]);

        await store.setEntryNoise(1, false);
        snapshot = await store.loadSnapshot();

        expect(snapshot.listIds(ListKey.searchInView('feed', 'first')), [1]);
        expect(
          snapshot.listIds(ListKey.searchInView('noise', 'first')),
          isEmpty,
        );
        expect(
          snapshot.listIds(ListKey.searchSourceInView('feed', 1, 'first')),
          [1],
        );
        expect(
          snapshot.listIds(ListKey.searchSourceInView('noise', 1, 'first')),
          isEmpty,
        );
        expect(
          snapshot.listIds(
            ListKey.searchFolderInView('feed', 'Engineering', 'first'),
          ),
          [1],
        );
        expect(
          snapshot.listIds(
            ListKey.searchFolderInView('noise', 'Engineering', 'first'),
          ),
          isEmpty,
        );
        expect(snapshot.listIds(ListKey.searchUnreadInView('feed', 'first')), [
          1,
        ]);
        expect(
          snapshot.listIds(ListKey.searchUnreadInView('noise', 'first')),
          isEmpty,
        );
      },
    );

    test(
      'reconciles cached scoped lists when entry details change remotely',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.upsertSources([
          FeedSource(
            id: 1,
            name: 'Source',
            folder: 'Engineering',
            rssUrl: 'https://example.com/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 1,
          ),
        ]);

        final first = EntryListItem(
          id: 1,
          sourceId: 1,
          sourceName: 'Source',
          title: 'First synced article',
          link: 'https://example.com/1',
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          summary: 'sync summary',
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        );
        await store.applyListSnapshot(ListKey.feed, [first]);
        await store.applyListSnapshot(ListKey.all, [first]);
        await store.applyListSnapshot(ListKey.source(1), [first]);
        await store.applyListSnapshot(ListKey.sourceInView('feed', 1), [first]);
        await store.applyListSnapshot(
          ListKey.folderInView('feed', 'Engineering'),
          [first],
        );
        await store.applyListSnapshot(ListKey.noise, const []);
        await store.applyListSnapshot(ListKey.saved, const []);
        await store.applyListSnapshot(ListKey.unreadInView('feed'), [first]);
        await store.applyListSnapshot(ListKey.searchSource(1, 'remote'), []);
        await store.applyListSnapshot(ListKey.searchInView('feed', 'remote'), [
          first,
        ]);
        await store.applyListSnapshot(
          ListKey.searchInView('noise', 'remote'),
          const [],
        );
        await store.applyListSnapshot(
          ListKey.searchInView('saved', 'remote'),
          const [],
        );
        await store.applyListSnapshot(
          ListKey.searchUnreadInView('feed', 'remote'),
          [first],
        );

        await store.upsertEntryDetails([
          EntryDetail(
            id: 1,
            sourceId: 1,
            sourceName: 'Source',
            title: 'First synced article',
            link: 'https://example.com/1',
            publishedAt: DateTime.utc(2026, 4, 10, 10),
            summary: 'remote sync summary',
            isRead: true,
            isSaved: true,
            readingProgress: 1,
            isNoise: true,
            foreign: false,
            coverImageUrl: null,
            contentHtml: '<p>remote body</p>',
            filterReason: 'remote noise',
            translationSegments: const [],
          ),
        ]);

        final snapshot = await store.loadSnapshot();

        expect(snapshot.entries[1]?.isRead, isTrue);
        expect(snapshot.entries[1]?.isSaved, isTrue);
        expect(snapshot.entries[1]?.isNoise, isTrue);
        expect(snapshot.entries[1]?.filterReason, 'remote noise');
        expect(snapshot.listIds(ListKey.feed), isEmpty);
        expect(snapshot.listIds(ListKey.all), [1]);
        expect(snapshot.listIds(ListKey.source(1)), [1]);
        expect(snapshot.listIds(ListKey.sourceInView('feed', 1)), isEmpty);
        expect(
          snapshot.listIds(ListKey.folderInView('feed', 'Engineering')),
          isEmpty,
        );
        expect(snapshot.listIds(ListKey.noise), [1]);
        expect(snapshot.listIds(ListKey.saved), [1]);
        expect(snapshot.listIds(ListKey.unreadInView('feed')), isEmpty);
        expect(snapshot.listIds(ListKey.searchSource(1, 'remote')), [1]);
        expect(
          snapshot.listIds(ListKey.searchInView('feed', 'remote')),
          isEmpty,
        );
        expect(snapshot.listIds(ListKey.searchInView('noise', 'remote')), [1]);
        expect(snapshot.listIds(ListKey.searchInView('saved', 'remote')), [1]);
        expect(
          snapshot.listIds(ListKey.searchUnreadInView('feed', 'remote')),
          isEmpty,
        );
      },
    );

    test(
      'updates cached search filters when entry link matches query',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.upsertSources([
          const FeedSource(
            id: 1,
            name: 'Source',
            folder: 'Engineering',
            rssUrl: 'https://example.com/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 1,
          ),
        ]);

        await store.applyListSnapshot(
          ListKey.searchInView('feed', 'launch'),
          [],
        );
        await store.upsertEntryDetails([
          EntryDetail(
            id: 1,
            sourceId: 1,
            sourceName: 'Source',
            title: 'Release notes',
            link: 'https://example.com/articles/launch-plan',
            publishedAt: DateTime.utc(2026, 4, 10, 10),
            summary: 'product update',
            isRead: false,
            foreign: false,
            filterStatus: 'SUCCESS',
            summaryStatus: 'SUCCESS',
            translationStatus: 'SUCCESS',
            coverImageUrl: null,
            contentHtml: null,
            filterReason: null,
            translationSegments: const [],
          ),
        ]);

        final snapshot = await store.loadSnapshot();

        expect(snapshot.listIds(ListKey.searchInView('feed', 'launch')), [1]);
      },
    );

    test(
      'limits cached local search filters to the first eight tokens',
      () async {
        final store = await LocalStore.inMemory();
        addTearDown(store.close);

        await store.upsertSources([
          const FeedSource(
            id: 1,
            name: 'Source',
            folder: 'Engineering',
            rssUrl: 'https://example.com/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 1,
          ),
        ]);

        const query =
            'jane analyst release notes source product update example.com/articles/launch-plan missing';
        await store.applyListSnapshot(ListKey.searchInView('feed', query), []);
        await store.upsertEntryDetails([
          EntryDetail(
            id: 1,
            sourceId: 1,
            sourceName: 'Source',
            author: 'Jane Analyst',
            title: 'Release notes',
            link: 'https://example.com/articles/launch-plan',
            publishedAt: DateTime.utc(2026, 4, 10, 10),
            summary: 'product update',
            isRead: false,
            foreign: false,
            filterStatus: 'SUCCESS',
            summaryStatus: 'SUCCESS',
            translationStatus: 'SUCCESS',
            coverImageUrl: null,
            contentHtml: null,
            filterReason: null,
            translationSegments: const [],
          ),
        ]);

        final snapshot = await store.loadSnapshot();

        expect(snapshot.listIds(ListKey.searchInView('feed', query)), [1]);
      },
    );

    test('updates unread scoped lists when read state changes', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      EntryListItem item(int id, String title) {
        return EntryListItem(
          id: id,
          sourceId: 1,
          sourceName: 'Source',
          title: title,
          link: 'https://example.com/$id',
          publishedAt: DateTime.utc(2026, 4, 10, 11 - id),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        );
      }

      final first = item(1, 'First unread');
      final second = item(2, 'Second unread');
      await store.upsertSources([
        FeedSource(
          id: 1,
          name: 'Source',
          folder: 'Engineering',
          rssUrl: 'https://example.com/feed.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 2,
        ),
      ]);
      await store.applyListSnapshot(ListKey.feed, [first, second]);
      await store.applyListSnapshot(ListKey.unreadInView('feed'), [
        first,
        second,
      ]);
      await store.applyListSnapshot(ListKey.unreadSourceInView('feed', 1), [
        first,
        second,
      ]);
      await store.applyListSnapshot(
        ListKey.unreadFolderInView('feed', 'Engineering'),
        [first, second],
      );
      await store.applyListSnapshot(
        ListKey.searchUnreadInView('feed', 'first'),
        [first],
      );

      await store.setEntryReadState(1, true);
      var snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]?.isRead, isTrue);
      expect(snapshot.entries[1]?.readingProgress, 1);
      expect(snapshot.listIds(ListKey.unreadInView('feed')), [2]);
      expect(snapshot.listIds(ListKey.unreadSourceInView('feed', 1)), [2]);
      expect(
        snapshot.listIds(ListKey.unreadFolderInView('feed', 'Engineering')),
        [2],
      );
      expect(
        snapshot.listIds(ListKey.searchUnreadInView('feed', 'first')),
        isEmpty,
      );

      await store.setEntryReadState(1, false);
      snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]?.isRead, isFalse);
      expect(snapshot.entries[1]?.readingProgress, 0);
      expect(snapshot.listIds(ListKey.unreadInView('feed')), [1, 2]);
      expect(snapshot.listIds(ListKey.unreadSourceInView('feed', 1)), [1, 2]);
      expect(
        snapshot.listIds(ListKey.unreadFolderInView('feed', 'Engineering')),
        [1, 2],
      );
      expect(snapshot.listIds(ListKey.searchUnreadInView('feed', 'first')), [
        1,
      ]);
    });

    test('updates entry reading progress', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.applyListSnapshot(ListKey.feed, [
        EntryListItem(
          id: 1,
          sourceId: 1,
          sourceName: 'Source',
          title: 'First',
          link: 'https://example.com/1',
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
      ]);

      await store.setReadingProgress(1, 0.42);

      final snapshot = await store.loadSnapshot();

      expect(snapshot.entries[1]!.readingProgress, 0.42);
    });

    test('persists reader preferences', () async {
      final store = await LocalStore.inMemory();
      addTearDown(store.close);

      await store.saveReaderPreferences(
        const ReaderPreferences(
          fontSize: 19,
          lineHeight: 1.85,
          width: ReaderWidth.wide,
          entrySortOrder: EntrySortOrder.longestFirst,
          entryQueueFilter: EntryQueueFilter.inProgress,
          entryListDensity: EntryListDensity.compact,
          sourceListSortOrder: SourceListSortOrder.unread,
          collapsedEntryDateSections: ['2026-04-11', '2026-04-10'],
          collapsedSourceFolders: ['Newsletters', 'Engineering'],
          showTranslations: false,
          lastSection: 'feed',
          lastSelectedEntryId: 42,
          lastEntrySourceFilterId: 7,
        ),
      );

      final preferences = await store.loadReaderPreferences();

      expect(preferences.fontSize, 19);
      expect(preferences.lineHeight, 1.85);
      expect(preferences.width, ReaderWidth.wide);
      expect(preferences.entrySortOrder, EntrySortOrder.longestFirst);
      expect(preferences.entryQueueFilter, EntryQueueFilter.inProgress);
      expect(preferences.entryListDensity, EntryListDensity.compact);
      expect(preferences.sourceListSortOrder, SourceListSortOrder.unread);
      expect(preferences.collapsedEntryDateSections, [
        '2026-04-10',
        '2026-04-11',
      ]);
      expect(preferences.collapsedSourceFolders, [
        'Engineering',
        'Newsletters',
      ]);
      expect(preferences.showTranslations, isFalse);
      expect(preferences.lastSection, 'feed');
      expect(preferences.lastSelectedEntryId, 42);
      expect(preferences.lastEntrySourceFilterId, 7);
    });
  });
}

EntryListItem _localStoreItem(
  int id, {
  required int sourceId,
  required String sourceName,
}) {
  return EntryListItem(
    id: id,
    sourceId: sourceId,
    sourceName: sourceName,
    title: 'Cached update $id',
    link: 'https://example.com/$id',
    publishedAt: DateTime.utc(2026, 4, 10, 9),
    summary: null,
    isRead: false,
    foreign: false,
    coverImageUrl: null,
  );
}
