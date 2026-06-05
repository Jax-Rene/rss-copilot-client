import 'dart:async';

import 'package:rss_copilot_client/src/data/api/api_client.dart';
import 'package:rss_copilot_client/src/data/api/api_exception.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/auth_user.dart';
import 'package:rss_copilot_client/src/models/entry_detail.dart';
import 'package:rss_copilot_client/src/models/entry_list_item.dart';
import 'package:rss_copilot_client/src/models/entry_page_cursor.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/pending_entry_action.dart';
import 'package:rss_copilot_client/src/models/reader_preferences.dart';
import 'package:rss_copilot_client/src/models/session_data.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:rss_copilot_client/src/repositories/rss_repository.dart';
import 'package:test/test.dart';

void main() {
  group('RssRepository pending entry actions', () {
    test('queues local mutations and flushes them in order', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedEntry(store);
      await repository.queueReadingProgress(1, 0.42);
      await repository.queueReadState(1, true);
      await repository.queueSavedState(1, true);

      final queued = await store.loadPendingEntryActions();
      expect(queued, hasLength(2));

      final snapshot = await store.loadSnapshot();
      expect(snapshot.entries[1]?.isRead, isTrue);
      expect(snapshot.entries[1]?.readingProgress, 1);
      expect(snapshot.entries[1]?.isSaved, isTrue);

      await repository.flushPendingEntryActions();

      expect(calls, ['read:1', 'saved:1']);
      expect(await store.loadPendingEntryActions(), isEmpty);
    });

    test('coalesces repeated actions of the same type for one entry', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedEntry(store);
      await repository.queueSavedState(1, true);
      await repository.queueSavedState(1, false);

      expect(await store.loadPendingEntryActions(), hasLength(1));

      await repository.flushPendingEntryActions();

      expect(calls, ['unsaved:1']);
      expect(await store.loadPendingEntryActions(), isEmpty);
    });

    test(
      'does not queue stale partial progress after an entry is read',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await repository.queueReadState(1, true);
        await repository.queueReadingProgress(1, 0.42);

        final queued = await store.loadPendingEntryActions();
        final snapshot = await store.loadSnapshot();
        expect(queued.map((action) => action.type), [
          PendingEntryActionType.readState,
        ]);
        expect(snapshot.entries[1]?.isRead, isTrue);
        expect(snapshot.entries[1]?.readingProgress, 1);

        await repository.flushPendingEntryActions();

        expect(calls, ['read:1']);
        expect(await store.loadPendingEntryActions(), isEmpty);
      },
    );

    test(
      'queues read state when reading progress reaches completion threshold',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await repository.queueReadingProgress(1, 0.98);

        final queued = await store.loadPendingEntryActions();
        final snapshot = await store.loadSnapshot();
        expect(queued.map((action) => action.type), [
          PendingEntryActionType.readState,
        ]);
        expect(snapshot.entries[1]?.isRead, isTrue);
        expect(snapshot.entries[1]?.readingProgress, 1);

        await repository.flushPendingEntryActions();

        expect(calls, ['read:1']);
        expect(await store.loadPendingEntryActions(), isEmpty);
      },
    );

    test('marks read online when reading progress reaches the end', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedEntry(store);
      await repository.updateReadingProgress(1, 1.5);

      final snapshot = await store.loadSnapshot();
      expect(calls, ['read:1']);
      expect(snapshot.entries[1]?.isRead, isTrue);
      expect(snapshot.entries[1]?.readingProgress, 1);
    });

    test(
      'mark read removes stale queued progress for the same entry',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readingProgress,
            entryId: 1,
            updatedAtMicros: 2,
            doubleValue: 0.42,
          ),
        );
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.savedState,
            entryId: 1,
            updatedAtMicros: 1,
            boolValue: true,
          ),
        );

        await repository.queueReadState(1, true);

        final queued = await store.loadPendingEntryActions();
        expect(queued.map((action) => action.type), [
          PendingEntryActionType.savedState,
          PendingEntryActionType.readState,
        ]);

        await repository.flushPendingEntryActions();

        expect(calls, ['saved:1', 'read:1']);
        expect(await store.loadPendingEntryActions(), isEmpty);
      },
    );

    test(
      'mark unread removes stale queued progress for the same entry',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await store.setEntryReadState(1, true);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readingProgress,
            entryId: 1,
            updatedAtMicros: 1,
            doubleValue: 0.42,
          ),
        );

        await repository.markUnread(1);

        final snapshot = await store.loadSnapshot();
        expect(calls, ['unread:1']);
        expect(snapshot.entries[1]?.isRead, isFalse);
        expect(snapshot.entries[1]?.readingProgress, 0);
        expect(await store.loadPendingEntryActions(), isEmpty);
      },
    );

    test(
      'queued unread removes stale queued progress for the same entry',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await store.setEntryReadState(1, true);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readingProgress,
            entryId: 1,
            updatedAtMicros: 1,
            doubleValue: 0.42,
          ),
        );
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.savedState,
            entryId: 1,
            updatedAtMicros: 2,
            boolValue: true,
          ),
        );

        await repository.queueReadState(1, false);

        final snapshot = await store.loadSnapshot();
        final queued = await store.loadPendingEntryActions();
        expect(snapshot.entries[1]?.isRead, isFalse);
        expect(snapshot.entries[1]?.readingProgress, 0);
        expect(queued.map((action) => action.type), [
          PendingEntryActionType.savedState,
          PendingEntryActionType.readState,
        ]);

        await repository.flushPendingEntryActions();

        expect(calls, ['saved:1', 'unread:1']);
        expect(await store.loadPendingEntryActions(), isEmpty);
      },
    );

    test(
      'mark all read removes stale queued progress for matching entries',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedTwoEntries(store);
        await store.setEntryReadState(2, true);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readingProgress,
            entryId: 1,
            updatedAtMicros: 1,
            doubleValue: 0.42,
          ),
        );
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readingProgress,
            entryId: 2,
            updatedAtMicros: 2,
            doubleValue: 0.84,
          ),
        );
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.savedState,
            entryId: 2,
            updatedAtMicros: 3,
            boolValue: true,
          ),
        );

        await repository.markAllRead(EntryView.feed);

        final pendingActions = await store.loadPendingEntryActions();
        expect(calls, ['read-all:feed:null:null']);
        expect(pendingActions.map((action) => action.type), [
          PendingEntryActionType.savedState,
        ]);
        expect(pendingActions.single.entryId, 2);
      },
    );

    test(
      'logout clears local cache and queued actions after remote failure',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _LogoutNetworkFailureApiClient(calls),
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await store.saveReaderPreferences(
          ReaderPreferences.defaultPreferences.copyWith(
            fontSize: 22,
            lastSelectedEntryId: 1,
          ),
        );
        await repository.queueSavedState(1, true);

        expect(await store.loadSession(), isNotNull);
        expect(await store.loadPendingEntryActions(), hasLength(1));
        expect((await store.loadSnapshot()).entries, contains(1));

        await repository.logout();

        final snapshot = await store.loadSnapshot();
        final preferences = await store.loadReaderPreferences();
        expect(calls, ['logout']);
        expect(await store.loadSession(), isNull);
        expect(await store.loadPendingEntryActions(), isEmpty);
        expect(snapshot.sources, isEmpty);
        expect(snapshot.entries, isEmpty);
        expect(snapshot.listIds(ListKey.feed), isEmpty);
        expect(
          preferences.fontSize,
          ReaderPreferences.defaultPreferences.fontSize,
        );
        expect(preferences.lastSelectedEntryId, isNull);
      },
    );

    test('sync applies deleted source tombstones to local cache', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _DeletedSourceSyncApiClient(calls),
      );
      addTearDown(store.close);

      await _seedTwoSources(store);
      await store.saveSession(
        _session.copyWith(lastServerTime: DateTime.utc(2026, 5, 24, 1)),
      );

      await repository.sync();

      final snapshot = await store.loadSnapshot();
      final session = await store.loadSession();
      expect(calls, [
        'sync-changes:2026-05-24T01:00:00.000Z',
        'fetch:all:false:null:null:null:null',
        'fetch:feed:false:null:null:null:null',
        'fetch:noise:false:null:null:null:null',
        'fetch:saved:false:null:null:null:null',
      ]);
      expect(snapshot.sources.map((source) => source.id), isNot(contains(1)));
      expect(snapshot.sources.map((source) => source.id), contains(2));
      expect(snapshot.entries.containsKey(101), isFalse);
      expect(snapshot.entries[202]?.sourceId, 2);
      expect(snapshot.listIds(ListKey.source(1)), isEmpty);
      expect(snapshot.listIds(ListKey.feed), isNot(contains(101)));
      expect(session?.lastServerTime, DateTime.utc(2026, 5, 24, 2));
    });

    test(
      'sync applies canonical source URL without clearing cached entries',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _CanonicalSourceSyncApiClient(calls),
        );
        addTearDown(store.close);

        await _seedTwoSources(store);
        await store.saveSession(
          _session.copyWith(lastServerTime: DateTime.utc(2026, 5, 24, 1)),
        );

        await repository.sync();

        final snapshot = await store.loadSnapshot();
        final session = await store.loadSession();
        expect(calls, [
          'sync-changes:2026-05-24T01:00:00.000Z',
          'fetch:all:false:null:null:null:null',
          'fetch:feed:false:null:null:null:null',
          'fetch:noise:false:null:null:null:null',
          'fetch:saved:false:null:null:null:null',
        ]);
        expect(snapshot.sourceById(1)?.name, 'Canonical');
        expect(
          snapshot.sourceById(1)?.rssUrl,
          'https://canonical.example/final-feed.xml',
        );
        expect(snapshot.sourceById(1)?.hasError, isFalse);
        expect(snapshot.entries[101]?.sourceId, 1);
        expect(snapshot.listIds(ListKey.source(1)), [101]);
        expect(session?.lastServerTime, DateTime.utc(2026, 5, 24, 2));
      },
    );

    test(
      'update source clears stale cached entries when RSS URL changes',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedTwoSources(store);
        await store.saveSession(_session);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readState,
            entryId: 101,
            updatedAtMicros: 1,
            boolValue: true,
          ),
        );
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readState,
            entryId: 202,
            updatedAtMicros: 2,
            boolValue: true,
          ),
        );

        final updated = await repository.updateSource(
          const FeedSource(
            id: 1,
            name: 'Moved',
            folder: 'Inbox',
            rssUrl: 'https://new.example/feed.xml',
            siteUrl: null,
            iconUrl: null,
            enabled: true,
            lastFetchedAt: null,
            hasError: false,
            unreadCount: 0,
          ),
        );

        final snapshot = await store.loadSnapshot();
        final pendingActions = await store.loadPendingEntryActions();
        expect(calls, ['update-source:1:https://new.example/feed.xml']);
        expect(updated.rssUrl, 'https://new.example/feed.xml');
        expect(snapshot.sourceById(1)?.rssUrl, 'https://new.example/feed.xml');
        expect(snapshot.entries.containsKey(101), isFalse);
        expect(snapshot.entries[202]?.sourceId, 2);
        expect(snapshot.listIds(ListKey.source(1)), isEmpty);
        expect(snapshot.listIds(ListKey.feed), [202]);
        expect(pendingActions.map((action) => action.entryId), [202]);
      },
    );

    test('flushes consecutive queued read actions in one batch', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedThreeEntries(store);
      await repository.queueEntriesRead([1, 2, 3]);

      expect(await store.loadPendingEntryActions(), hasLength(3));

      await repository.flushPendingEntryActions();

      expect(calls, ['batch-read:1,2,3']);
      expect(await store.loadPendingEntryActions(), isEmpty);
    });

    test('summarizes pending action types for sync status', () async {
      final store = await LocalStore.inMemory();
      final repository = RssRepository(store: store);
      addTearDown(store.close);

      await _seedThreeEntries(store);
      await repository.queueEntriesRead([1, 2]);
      await repository.queueSavedState(2, true);
      await repository.queueNoiseState(3, true);
      await repository.queueReadingProgress(3, 0.4);

      final status = await repository.pendingEntryActionStatus();

      expect(status.count, 5);
      expect(status.description, '标记已读 2、加入稍后读 1、移入噪音箱 1、阅读进度 1');
    });

    test('drops queued actions for entries no longer in local cache', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedEntry(store);
      await store.savePendingEntryAction(
        const PendingEntryAction(
          type: PendingEntryActionType.savedState,
          entryId: 404,
          updatedAtMicros: 1,
          boolValue: true,
        ),
      );
      await repository.queueSavedState(1, true);

      await repository.flushPendingEntryActions();

      expect(calls, ['saved:1']);
      expect(await store.loadPendingEntryActions(), isEmpty);
    });

    test('splits large queued read batches at the server limit', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedManyEntries(store, 101);
      await repository.queueEntriesRead(
        List<int>.generate(101, (index) => index + 1),
      );

      await repository.flushPendingEntryActions();

      final firstBatch = List<int>.generate(
        100,
        (index) => index + 1,
      ).join(',');
      expect(calls, ['batch-read:$firstBatch', 'read:101']);
      expect(await store.loadPendingEntryActions(), isEmpty);
    });

    test(
      'keeps non-read actions ordered around batched read actions',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedThreeEntries(store);
        await repository.queueEntriesRead([1, 2]);
        await repository.queueSavedState(3, true);
        await repository.queueEntriesRead([3]);

        await repository.flushPendingEntryActions();

        expect(calls, ['batch-read:1,2', 'saved:3', 'read:3']);
        expect(await store.loadPendingEntryActions(), isEmpty);
      },
    );

    test('drops stale not found actions and continues flushing', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _StaleFirstApiClient(calls),
      );
      addTearDown(store.close);

      await _seedTwoEntries(store);
      await repository.queueReadState(1, true);
      await repository.queueSavedState(2, true);

      expect(await store.loadPendingEntryActions(), hasLength(2));

      await repository.flushPendingEntryActions();

      final snapshot = await store.loadSnapshot();
      expect(calls, ['read:1', 'saved:2']);
      expect(snapshot.entries.containsKey(1), isFalse);
      expect(snapshot.listIds(ListKey.feed), [2]);
      expect(await store.loadPendingEntryActions(), isEmpty);
    });

    test('falls back around stale batched pending read actions', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _StaleBatchReadApiClient(calls),
      );
      addTearDown(store.close);

      await _seedTwoEntries(store);
      await repository.queueEntriesRead([1, 2]);

      await repository.flushPendingEntryActions();

      final snapshot = await store.loadSnapshot();

      expect(calls, ['batch-read:1,2', 'read:1', 'read:2']);
      expect(snapshot.entries.containsKey(1), isFalse);
      expect(snapshot.entries[2]?.isRead, isTrue);
      expect(snapshot.listIds(ListKey.feed), [2]);
      expect(await store.loadPendingEntryActions(), isEmpty);
    });

    test(
      'keeps newer queued action written while an older action flushes',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        late final RssRepository repository;
        repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _OverwritingDuringFlushApiClient(
            calls,
            onMarkRead: () => repository.queueReadState(1, false),
          ),
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await repository.queueReadState(1, true);

        await repository.flushPendingEntryActions();

        var pendingActions = await store.loadPendingEntryActions();
        expect(calls, ['read:1']);
        expect(pendingActions, hasLength(1));
        expect(pendingActions.single.type, PendingEntryActionType.readState);
        expect(pendingActions.single.entryId, 1);
        expect(pendingActions.single.boolValue, isFalse);

        await repository.flushPendingEntryActions();

        pendingActions = await store.loadPendingEntryActions();
        expect(calls, ['read:1', 'unread:1']);
        expect(pendingActions, isEmpty);
      },
    );

    test('queues manual noise state while offline and flushes it', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedEntry(store);
      await repository.queueNoiseState(1, true);

      var snapshot = await store.loadSnapshot();
      expect(snapshot.entries[1]?.isNoise, isTrue);
      expect(snapshot.listIds(ListKey.feed), isEmpty);
      expect(snapshot.listIds(ListKey.noise), [1]);
      expect(await store.loadPendingEntryActions(), hasLength(1));

      await repository.flushPendingEntryActions();

      expect(calls, ['noise:1']);
      expect(await store.loadPendingEntryActions(), isEmpty);

      await repository.queueNoiseState(1, false);
      snapshot = await store.loadSnapshot();
      expect(snapshot.entries[1]?.isNoise, isFalse);
      expect(snapshot.listIds(ListKey.feed), [1]);
      expect(snapshot.listIds(ListKey.noise), isEmpty);

      await repository.flushPendingEntryActions();

      expect(calls, ['noise:1', 'feed:1']);
    });

    test('marks an entry as AI pending after retry request', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedEntry(store);
      await repository.reprocessEntryAi(1);

      final snapshot = await store.loadSnapshot();

      expect(calls, ['reprocess-ai:1']);
      expect(snapshot.entries[1]?.filterStatus, 'PENDING');
      expect(snapshot.entries[1]?.summaryStatus, 'PENDING');
      expect(snapshot.entries[1]?.translationStatus, 'PENDING');
    });

    test(
      'does not decrement source unread count for noise batch reads',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedFeedAndNoiseEntries(store);

        await repository.markEntriesRead([2]);

        final snapshot = await store.loadSnapshot();

        expect(calls, ['batch-read:2']);
        expect(snapshot.entries[2]?.isRead, isTrue);
        expect(snapshot.sourceById(1)?.unreadCount, 1);
      },
    );

    test(
      'mark read decrements source unread count outside feed cache',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedSourceOnlyEntry(store);

        await repository.markRead(1);

        final snapshot = await store.loadSnapshot();

        expect(calls, ['read:1']);
        expect(snapshot.entries[1]?.isRead, isTrue);
        expect(snapshot.listIds(ListKey.source(1)), [1]);
        expect(snapshot.sourceById(1)?.unreadCount, 0);
      },
    );

    test(
      'detail mark-read decrements source unread count from prior cache',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedSourceOnlyEntry(store);

        await repository.fetchEntryDetail(1, markRead: true);

        final snapshot = await store.loadSnapshot();

        expect(calls, ['detail:1:true']);
        expect(snapshot.entries[1]?.isRead, isTrue);
        expect(snapshot.entries[1]?.contentHtml, '<p>Fetched detail</p>');
        expect(snapshot.sourceById(1)?.unreadCount, 0);
      },
    );

    test('detail not found removes stale cached entry', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _MissingEntryDetailApiClient(calls),
      );
      addTearDown(store.close);

      await _seedSourceOnlyEntry(store);
      await store.savePendingEntryAction(
        const PendingEntryAction(
          type: PendingEntryActionType.readingProgress,
          entryId: 1,
          updatedAtMicros: 1,
          doubleValue: 0.4,
        ),
      );

      await expectLater(
        repository.fetchEntryDetail(1, markRead: true),
        throwsA(
          isA<ApiException>().having(
            (error) => error.isNotFound,
            'isNotFound',
            isTrue,
          ),
        ),
      );

      final snapshot = await store.loadSnapshot();
      final pendingActions = await store.loadPendingEntryActions();

      expect(calls, ['detail:1:true']);
      expect(snapshot.entries.containsKey(1), isFalse);
      expect(snapshot.listIds(ListKey.source(1)), isEmpty);
      expect(snapshot.sourceById(1)?.unreadCount, 0);
      expect(pendingActions, isEmpty);
    });

    test('mark read not found removes stale cached entry', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _StaleFirstApiClient(calls),
      );
      addTearDown(store.close);

      await _seedTwoEntries(store);

      await expectLater(
        repository.markRead(1),
        throwsA(
          isA<ApiException>().having(
            (error) => error.isNotFound,
            'isNotFound',
            isTrue,
          ),
        ),
      );

      final snapshot = await store.loadSnapshot();

      expect(calls, ['read:1']);
      expect(snapshot.entries.containsKey(1), isFalse);
      expect(snapshot.entries.containsKey(2), isTrue);
      expect(snapshot.listIds(ListKey.feed), [2]);
      expect(snapshot.sourceById(1)?.unreadCount, 0);
    });

    test('batch mark read falls back around stale cached entries', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _StaleBatchReadApiClient(calls),
      );
      addTearDown(store.close);

      await _seedTwoEntries(store);

      await repository.markEntriesRead([1, 2]);

      final snapshot = await store.loadSnapshot();

      expect(calls, ['batch-read:1,2', 'read:1', 'read:2']);
      expect(snapshot.entries.containsKey(1), isFalse);
      expect(snapshot.entries[2]?.isRead, isTrue);
      expect(snapshot.listIds(ListKey.feed), [2]);
      expect(snapshot.sourceById(1)?.unreadCount, 0);
    });

    test('splits large online mark-read batches at the server limit', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedManyEntries(store, 101);

      await repository.markEntriesRead(
        List<int>.generate(101, (index) => index + 1),
      );

      final firstBatch = List<int>.generate(
        100,
        (index) => index + 1,
      ).join(',');
      expect(calls, ['batch-read:$firstBatch', 'batch-read:101']);
      final snapshot = await store.loadSnapshot();
      expect(snapshot.entries.values.where((entry) => !entry.isRead), isEmpty);
      expect(snapshot.sourceById(1)?.unreadCount, 0);
    });

    test('saved mark-all-read decrements only feed unread counts', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await _seedSavedFeedAndNoiseEntries(store);

      await repository.markAllRead(EntryView.saved);

      final snapshot = await store.loadSnapshot();

      expect(calls, ['read-all:saved:null:null']);
      expect(snapshot.entries[1]?.isRead, isTrue);
      expect(snapshot.entries[2]?.isRead, isTrue);
      expect(snapshot.entries[3]?.isRead, isFalse);
      expect(snapshot.sourceById(1)?.unreadCount, 1);
    });

    test(
      'feed mark-all-read updates cached entries outside feed page',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedSourceOnlyEntry(store);

        await repository.markAllRead(EntryView.feed);

        final snapshot = await store.loadSnapshot();

        expect(calls, ['read-all:feed:null:null']);
        expect(snapshot.entries[1]?.isRead, isTrue);
        expect(snapshot.listIds(ListKey.source(1)), [1]);
        expect(snapshot.sourceById(1)?.unreadCount, 0);
      },
    );

    test(
      'saved mark-all-read updates cached saved entries outside saved page',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await _seedSourceOnlySavedEntry(store);

        await repository.markAllRead(EntryView.saved);

        final snapshot = await store.loadSnapshot();

        expect(calls, ['read-all:saved:null:null']);
        expect(snapshot.entries[1]?.isRead, isTrue);
        expect(snapshot.entries[1]?.isSaved, isTrue);
        expect(snapshot.listIds(ListKey.saved), isEmpty);
        expect(snapshot.sourceById(1)?.unreadCount, 0);
      },
    );

    test('bootstrap replaces stale cached sources and entries', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _BootstrapApiClient(calls),
      );
      addTearDown(store.close);

      await store.saveSession(_session);
      await store.upsertSources([
        FeedSource(
          id: 99,
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
      await store.applyListSnapshot(ListKey.feed, [
        EntryListItem(
          id: 99,
          sourceId: 99,
          sourceName: 'Deleted Source',
          title: 'Stale article',
          link: 'https://old.example/article',
          publishedAt: DateTime.utc(2026, 5, 24, 6),
          summary: null,
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
      ]);

      await repository.bootstrap(session: _session);

      final snapshot = await store.loadSnapshot();
      final session = await store.loadSession();

      expect(calls.first, 'bootstrap');
      expect(snapshot.sources.map((source) => source.id), [2]);
      expect(snapshot.entries.containsKey(99), isFalse);
      expect(snapshot.entries[2]?.title, 'Bootstrap article');
      expect(snapshot.listIds(ListKey.feed).contains(99), isFalse);
      expect(session?.lastServerTime, DateTime.utc(2026, 5, 25, 1));
    });

    test(
      'bootstrap flushes queued actions before replacing snapshot',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _BootstrapApiClient(calls),
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await repository.queueReadState(1, true);

        await repository.bootstrap(session: _session);

        final snapshot = await store.loadSnapshot();

        expect(calls.first, 'read:1');
        expect(calls[1], 'bootstrap');
        expect(await store.loadPendingEntryActions(), isEmpty);
        expect(snapshot.entries.containsKey(1), isFalse);
        expect(snapshot.entries[2]?.title, 'Bootstrap article');
      },
    );

    test('bootstrap keeps snapshot visible when list refresh fails', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _BootstrapListFailureApiClient(calls),
      );
      addTearDown(store.close);

      await store.saveSession(_session);

      final session = await repository.bootstrap(session: _session);
      final snapshot = await store.loadSnapshot();

      expect(calls, [
        'bootstrap',
        'fetch:all',
        'fetch:feed',
        'fetch:noise',
        'fetch:saved',
      ]);
      expect(session.lastServerTime, DateTime.utc(2026, 5, 25, 1));
      expect(snapshot.entries[2]?.title, 'Bootstrap article');
      expect(snapshot.listIds(ListKey.all), [2]);
      expect(snapshot.listIds(ListKey.feed), [2]);
      expect(snapshot.listIds(ListKey.noise), isEmpty);
      expect(snapshot.listIds(ListKey.saved), isEmpty);
    });

    test('keeps imported OPML sources when bootstrap sync times out', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _OpmlImportBootstrapTimeoutApiClient(calls),
      );
      addTearDown(store.close);

      await store.saveSession(_session);

      await expectLater(
        repository.importOpml('<opml></opml>', refreshAfterImport: false),
        throwsA(
          isA<OpmlImportSyncException>()
              .having((error) => error.result.importedCount, 'importedCount', 1)
              .having((error) => error.cause, 'cause', isA<TimeoutException>()),
        ),
      );

      final snapshot = await store.loadSnapshot();

      expect(calls, ['import-opml:false', 'bootstrap']);
      expect(snapshot.sourceById(7)?.name, 'Imported Feed');
      expect(snapshot.sourceById(7)?.rssUrl, 'https://imported.example/rss');
    });

    test('exports OPML from cached sources without a network request', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await store.upsertSources([
        const FeedSource(
          id: 1,
          name: 'B & B Daily',
          rssUrl: 'https://example.com/b&b.xml',
          siteUrl: 'https://example.com/?a=1&b=2',
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 0,
        ),
        const FeedSource(
          id: 2,
          name: 'AI "Weekly"',
          folder: 'Research <AI> / LLM',
          rssUrl: 'https://ai.example.com/rss.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 0,
        ),
      ]);

      final opml = await repository.exportOpml();

      expect(calls, isEmpty);
      expect(opml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(opml, contains('<opml version="2.0">'));
      expect(
        opml,
        contains(
          '<outline text="B &amp; B Daily" title="B &amp; B Daily" type="rss" xmlUrl="https://example.com/b&amp;b.xml" htmlUrl="https://example.com/?a=1&amp;b=2" />',
        ),
      );
      expect(
        opml,
        contains(
          '<outline text="Research &lt;AI&gt;" title="Research &lt;AI&gt;">',
        ),
      );
      expect(opml, contains('<outline text="LLM" title="LLM">'));
      expect(opml, contains('title="AI &quot;Weekly&quot;"'));
      expect(opml, contains('category="/Research &lt;AI&gt;/LLM"'));
      expect(
        opml.indexOf('title="Research &lt;AI&gt;"'),
        lessThan(opml.indexOf('title="LLM"')),
      );
      expect(
        opml.indexOf('title="LLM"'),
        lessThan(opml.indexOf('title="AI &quot;Weekly&quot;"')),
      );
    });

    test('loads folder list keys through the entries endpoint', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await store.saveSession(_session);

      final key = ListKey.folderInView(EntryView.feed.wireValue, 'Tech');
      await repository.loadSearchEntries(key);

      expect(calls, ['fetch:feed:false:Tech:null:null:null']);
      final snapshot = await store.loadSnapshot();
      expect(snapshot.listIds(key), [9]);
      expect(snapshot.entries[9]?.sourceName, 'Tech');
    });

    test(
      'loads source-in-view list keys through the entries endpoint',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await store.saveSession(_session);

        final key = ListKey.sourceInView(EntryView.feed.wireValue, 42);
        await repository.loadSearchEntries(key);

        expect(calls, ['fetch:feed:false:null:42:null:null']);
        final snapshot = await store.loadSnapshot();
        expect(snapshot.listIds(key), [9]);
        expect(snapshot.entries[9]?.sourceId, 42);
      },
    );

    test('loads folder search keys through the entries endpoint', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await store.saveSession(_session);

      final key = ListKey.searchFolderInView(
        EntryView.saved.wireValue,
        'Research',
        'ai',
      );
      await repository.loadSearchEntries(key);

      expect(calls, ['fetch:saved:false:Research:null:ai:null']);
      final snapshot = await store.loadSnapshot();
      expect(snapshot.listIds(key), [9]);
      expect(snapshot.entries[9]?.title, 'saved Research ai');
    });

    test(
      'loads source-in-view search keys through the entries endpoint',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await store.saveSession(_session);

        final key = ListKey.searchSourceInView(
          EntryView.noise.wireValue,
          7,
          'infra',
        );
        await repository.loadSearchEntries(key);

        expect(calls, ['fetch:noise:false:null:7:infra:null']);
        final snapshot = await store.loadSnapshot();
        expect(snapshot.listIds(key), [9]);
        expect(snapshot.entries[9]?.title, 'noise all infra');
      },
    );

    test('loads unread list keys through the entries endpoint', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await store.saveSession(_session);

      final key = ListKey.unreadSourceInView(EntryView.feed.wireValue, 42);
      await repository.loadSearchEntries(key);

      expect(calls, ['fetch:feed:true:null:42:null:null']);
      final snapshot = await store.loadSnapshot();
      expect(snapshot.listIds(key), [9]);
      expect(snapshot.entries[9]?.isRead, isFalse);
    });

    test('loads unread search keys through the entries endpoint', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
      );
      addTearDown(store.close);

      await store.saveSession(_session);

      final key = ListKey.searchUnreadFolderInView(
        EntryView.saved.wireValue,
        'Research',
        'ai',
      );
      await repository.loadSearchEntries(key);

      expect(calls, ['fetch:saved:true:Research:null:ai:null']);
      final snapshot = await store.loadSnapshot();
      expect(snapshot.listIds(key), [9]);
      expect(snapshot.entries[9]?.title, 'saved Research ai');
    });

    test(
      'clears stale pagination when server rejects the cached cursor',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _InvalidCursorApiClient(calls),
        );
        addTearDown(store.close);

        await store.saveSession(_session);
        await store.applyListSnapshot(
          ListKey.feed,
          [_listItem(1, 'Cached feed article')],
          hasMore: true,
          nextCursor: EntryPageCursor(
            publishedAt: DateTime.utc(2026, 5, 24, 9),
            id: 1,
          ),
        );

        await expectLater(
          repository.loadMoreEntries(ListKey.feed),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              'invalid pagination cursor',
            ),
          ),
        );

        final snapshot = await store.loadSnapshot();

        expect(calls, ['fetch:feed:1']);
        expect(snapshot.listIds(ListKey.feed), [1]);
        expect(snapshot.entries[1]?.title, 'Cached feed article');
        expect(snapshot.hasMore(ListKey.feed), isFalse);
        expect(snapshot.cursorFor(ListKey.feed), isNull);
      },
    );

    test(
      'clears inconsistent pagination when cached cursor is missing',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
        );
        addTearDown(store.close);

        await store.saveSession(_session);
        await store.applyListSnapshot(ListKey.feed, [
          _listItem(1, 'Cached feed article'),
        ], hasMore: true);

        await repository.loadMoreEntries(ListKey.feed);

        final snapshot = await store.loadSnapshot();

        expect(calls, isEmpty);
        expect(snapshot.listIds(ListKey.feed), [1]);
        expect(snapshot.entries[1]?.title, 'Cached feed article');
        expect(snapshot.hasMore(ListKey.feed), isFalse);
        expect(snapshot.cursorFor(ListKey.feed), isNull);
      },
    );

    test(
      'clears stale source pagination when server rejects the cached cursor',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _InvalidCursorApiClient(calls),
        );
        addTearDown(store.close);

        await store.saveSession(_session);
        final key = ListKey.source(42);
        await store.applyListSnapshot(
          key,
          [
            EntryListItem(
              id: 7,
              sourceId: 42,
              sourceName: 'Source',
              title: 'Cached source article',
              link: 'https://example.com/source/7',
              publishedAt: DateTime.utc(2026, 5, 24, 9),
              summary: 'cached',
              isRead: false,
              foreign: false,
              coverImageUrl: null,
            ),
          ],
          hasMore: true,
          nextCursor: EntryPageCursor(
            publishedAt: DateTime.utc(2026, 5, 24, 9),
            id: 7,
          ),
        );

        await expectLater(
          repository.loadMoreEntries(key),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              'invalid pagination cursor',
            ),
          ),
        );

        final snapshot = await store.loadSnapshot();

        expect(calls, ['source-fetch:42:7']);
        expect(snapshot.listIds(key), [7]);
        expect(snapshot.entries[7]?.title, 'Cached source article');
        expect(snapshot.hasMore(key), isFalse);
        expect(snapshot.cursorFor(key), isNull);
      },
    );

    test(
      'removes stale local source when source entries return not found',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _MissingSourceEntriesApiClient(calls),
        );
        addTearDown(store.close);

        await store.saveSession(_session);
        await _seedTwoSources(store);

        await expectLater(
          repository.loadSourceEntries(1),
          throwsA(
            isA<ApiException>().having(
              (error) => error.isNotFound,
              'isNotFound',
              isTrue,
            ),
          ),
        );

        final snapshot = await store.loadSnapshot();

        expect(calls, ['source-fetch:1']);
        expect(snapshot.sourceById(1), isNull);
        expect(snapshot.sourceById(2)?.name, 'Kept');
        expect(snapshot.entries.containsKey(101), isFalse);
        expect(snapshot.entries[202]?.sourceName, 'Kept');
        expect(snapshot.listIds(ListKey.feed), [202]);
        expect(snapshot.hasListSnapshot(ListKey.source(1)), isFalse);
      },
    );

    test(
      'removes stale local source when source-filtered entries return not found',
      () async {
        final cases = <({ListKey key, String call})>[
          (
            key: ListKey.sourceInView(EntryView.feed.wireValue, 1),
            call: 'fetch:feed:false:null:1:null:null',
          ),
          (
            key: ListKey.unreadSourceInView(EntryView.saved.wireValue, 1),
            call: 'fetch:saved:true:null:1:null:null',
          ),
          (
            key: ListKey.searchUnreadSourceInView(
              EntryView.noise.wireValue,
              1,
              'ai',
            ),
            call: 'fetch:noise:true:null:1:ai:null',
          ),
        ];

        for (final testCase in cases) {
          final store = await LocalStore.inMemory();
          final calls = <String>[];
          final repository = RssRepository(
            store: store,
            apiClientFactory: (_) =>
                _MissingSourceFilteredEntriesApiClient(calls),
          );
          addTearDown(store.close);

          await store.saveSession(_session);
          await _seedTwoSources(store);

          await expectLater(
            repository.loadSearchEntries(testCase.key),
            throwsA(
              isA<ApiException>().having(
                (error) => error.isNotFound,
                'isNotFound',
                isTrue,
              ),
            ),
          );

          final snapshot = await store.loadSnapshot();

          expect(calls, [testCase.call]);
          expect(snapshot.sourceById(1), isNull);
          expect(snapshot.sourceById(2)?.name, 'Kept');
          expect(snapshot.entries.containsKey(101), isFalse);
          expect(snapshot.entries[202]?.sourceName, 'Kept');
          expect(snapshot.listIds(ListKey.feed), [202]);
        }
      },
    );

    test(
      'removes stale local source when source history returns not found',
      () async {
        final cases = <({ListKey key, String call})>[
          (key: ListKey.source(1), call: 'source-fetch:1'),
          (
            key: ListKey.sourceInView(EntryView.feed.wireValue, 1),
            call: 'fetch:feed:false:null:1:null:101',
          ),
          (
            key: ListKey.searchUnreadSourceInView(
              EntryView.noise.wireValue,
              1,
              'ai',
            ),
            call: 'fetch:noise:true:null:1:ai:101',
          ),
        ];

        for (final testCase in cases) {
          final store = await LocalStore.inMemory();
          final calls = <String>[];
          final repository = RssRepository(
            store: store,
            apiClientFactory: (_) => testCase.key == ListKey.source(1)
                ? _MissingSourceEntriesApiClient(calls)
                : _MissingSourceFilteredEntriesApiClient(calls),
          );
          addTearDown(store.close);

          await store.saveSession(_session);
          await _seedTwoSources(store);
          await store.applyListSnapshot(
            testCase.key,
            [_listItem(101, 'Cached stale source article')],
            hasMore: true,
            nextCursor: EntryPageCursor(
              publishedAt: DateTime.utc(2026, 5, 24, 9),
              id: 101,
            ),
          );

          await expectLater(
            repository.loadMoreEntries(testCase.key),
            throwsA(
              isA<ApiException>().having(
                (error) => error.isNotFound,
                'isNotFound',
                isTrue,
              ),
            ),
          );

          final snapshot = await store.loadSnapshot();

          expect(calls, [testCase.call]);
          expect(snapshot.sourceById(1), isNull);
          expect(snapshot.sourceById(2)?.name, 'Kept');
          expect(snapshot.entries.containsKey(101), isFalse);
          expect(snapshot.entries[202]?.sourceName, 'Kept');
          expect(snapshot.listIds(ListKey.feed), [202]);
          expect(snapshot.hasListSnapshot(testCase.key), isFalse);
        }
      },
    );

    test(
      'removes stale local source when source mark read returns not found',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _MissingSourceReadAllApiClient(calls),
        );
        addTearDown(store.close);

        await store.saveSession(_session);
        await _seedTwoSources(store);

        await expectLater(
          repository.markSourceRead(1),
          throwsA(
            isA<ApiException>().having(
              (error) => error.isNotFound,
              'isNotFound',
              isTrue,
            ),
          ),
        );

        final snapshot = await store.loadSnapshot();

        expect(calls, ['read-all:all:1:null']);
        expect(snapshot.sourceById(1), isNull);
        expect(snapshot.sourceById(2)?.name, 'Kept');
        expect(snapshot.entries.containsKey(101), isFalse);
        expect(snapshot.entries[202]?.sourceName, 'Kept');
        expect(snapshot.listIds(ListKey.feed), [202]);
      },
    );

    test(
      'removes stale local source when source refresh returns not found',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _MissingSourceRefreshApiClient(calls),
        );
        addTearDown(store.close);

        await store.saveSession(_session);
        await _seedTwoSources(store);

        await expectLater(
          repository.refreshSourceAndPoll(1),
          throwsA(
            isA<ApiException>().having(
              (error) => error.isNotFound,
              'isNotFound',
              isTrue,
            ),
          ),
        );

        final snapshot = await store.loadSnapshot();

        expect(calls, ['refresh-source:1']);
        expect(snapshot.sourceById(1), isNull);
        expect(snapshot.sourceById(2)?.name, 'Kept');
        expect(snapshot.entries.containsKey(101), isFalse);
        expect(snapshot.entries[202]?.sourceName, 'Kept');
        expect(snapshot.listIds(ListKey.feed), [202]);
      },
    );

    test('treats missing remote source delete as local cleanup', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _MissingSourceDeleteApiClient(calls),
      );
      addTearDown(store.close);

      await store.saveSession(_session);
      await _seedTwoSources(store);

      await repository.deleteSource(1);

      final snapshot = await store.loadSnapshot();

      expect(calls, ['delete-source:1']);
      expect(snapshot.sourceById(1), isNull);
      expect(snapshot.sourceById(2)?.name, 'Kept');
      expect(snapshot.entries.containsKey(101), isFalse);
      expect(snapshot.entries[202]?.sourceName, 'Kept');
      expect(snapshot.listIds(ListKey.feed), [202]);
    });

    test('batch source refresh avoids per-source entry fetches', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RecordingApiClient(calls),
        refreshPollDelay: Duration.zero,
        refreshPollAttempts: 1,
      );
      addTearDown(store.close);

      await store.saveSession(
        _session.copyWith(lastServerTime: DateTime.utc(2026, 5, 24, 1)),
      );

      final result = await repository.refreshSourcesAndPoll([2, 4, 2]);

      expect(calls, [
        'refresh-sources:2,4',
        'sync-changes:2026-05-24T01:00:00.000Z',
        'fetch:all:false:null:null:null:null',
        'fetch:feed:false:null:null:null:null',
        'fetch:noise:false:null:null:null:null',
        'fetch:saved:false:null:null:null:null',
      ]);
      expect(result.acceptedCount, 2);
      expect(result.requestedCount, 2);
      expect(result.skippedCount, 0);
      expect(calls.where((call) => call.startsWith('source-fetch:')), isEmpty);
    });

    test(
      'batch source refresh splits large selections at the API limit',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _RecordingApiClient(calls),
          refreshPollDelay: Duration.zero,
          refreshPollAttempts: 1,
        );
        addTearDown(store.close);

        await store.saveSession(
          _session.copyWith(lastServerTime: DateTime.utc(2026, 5, 24, 1)),
        );

        final sourceIds = List<int>.generate(205, (index) => index + 1);
        final result = await repository.refreshSourcesAndPoll(sourceIds);

        expect(calls.take(3), [
          'refresh-sources:${sourceIds.take(100).join(',')}',
          'refresh-sources:${sourceIds.skip(100).take(100).join(',')}',
          'refresh-sources:${sourceIds.skip(200).join(',')}',
        ]);
        expect(calls[3], 'sync-changes:2026-05-24T01:00:00.000Z');
        expect(result.acceptedCount, 205);
        expect(result.requestedCount, 205);
        expect(result.skippedCount, 0);
      },
    );

    test('OPML import refresh uses configurable sync polling', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _OpmlImportRefreshApiClient(calls),
        refreshPollDelay: Duration.zero,
        refreshPollAttempts: 1,
      );
      addTearDown(store.close);

      await store.saveSession(_session);

      final result = await repository.importOpml(
        '<opml></opml>',
        refreshAfterImport: true,
      );

      expect(result.importedCount, 1);
      expect(calls, [
        'import-opml:true',
        'bootstrap',
        'fetch:all:false:null:null:null:null',
        'fetch:feed:false:null:null:null:null',
        'fetch:noise:false:null:null:null:null',
        'fetch:saved:false:null:null:null:null',
        'sync-changes:2026-05-25T01:00:00.000Z',
        'fetch:all:false:null:null:null:null',
        'fetch:feed:false:null:null:null:null',
        'fetch:noise:false:null:null:null:null',
        'fetch:saved:false:null:null:null:null',
      ]);
    });

    test(
      'OPML import flushes pending actions before replacing snapshot',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _OpmlImportRefreshApiClient(calls),
          refreshPollDelay: Duration.zero,
          refreshPollAttempts: 1,
        );
        addTearDown(store.close);

        await _seedEntry(store);
        await repository.queueReadState(1, true);

        final result = await repository.importOpml(
          '<opml></opml>',
          refreshAfterImport: false,
        );

        expect(result.importedCount, 1);
        expect(calls, [
          'read:1',
          'import-opml:false',
          'bootstrap',
          'fetch:all:false:null:null:null:null',
          'fetch:feed:false:null:null:null:null',
          'fetch:noise:false:null:null:null:null',
          'fetch:saved:false:null:null:null:null',
        ]);
        expect(await store.loadPendingEntryActions(), isEmpty);
      },
    );

    test('refresh polling reports the last transient sync failure', () async {
      final store = await LocalStore.inMemory();
      final calls = <String>[];
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => _RefreshPollTimeoutApiClient(calls),
        refreshPollDelay: Duration.zero,
        refreshPollAttempts: 2,
      );
      addTearDown(store.close);

      await store.saveSession(
        _session.copyWith(lastServerTime: DateTime.utc(2026, 5, 24, 1)),
      );

      await expectLater(
        repository.refreshSourcesAndPoll([2, 4]),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, [
        'refresh-sources:2,4',
        'sync-changes:2026-05-24T01:00:00.000Z',
        'sync-changes:2026-05-24T01:00:00.000Z',
      ]);
    });

    test(
      'OPML import wraps refresh polling failure after import succeeds',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (_) => _OpmlImportRefreshTimeoutApiClient(calls),
          refreshPollDelay: Duration.zero,
          refreshPollAttempts: 1,
        );
        addTearDown(store.close);

        await store.saveSession(_session);

        await expectLater(
          repository.importOpml('<opml></opml>', refreshAfterImport: true),
          throwsA(
            isA<OpmlImportSyncException>()
                .having(
                  (error) => error.result.importedCount,
                  'importedCount',
                  1,
                )
                .having(
                  (error) => error.cause,
                  'cause',
                  isA<TimeoutException>(),
                ),
          ),
        );

        final snapshot = await store.loadSnapshot();
        expect(snapshot.sourceById(8)?.name, 'Imported Refresh Feed');
        expect(calls, [
          'import-opml:true',
          'bootstrap',
          'fetch:all:false:null:null:null:null',
          'fetch:feed:false:null:null:null:null',
          'fetch:noise:false:null:null:null:null',
          'fetch:saved:false:null:null:null:null',
          'sync-changes:2026-05-25T01:00:00.000Z',
        ]);
      },
    );

    test('refreshes global lists concurrently', () async {
      final store = await LocalStore.inMemory();
      final client = _ConcurrentGlobalListsApiClient();
      final repository = RssRepository(
        store: store,
        apiClientFactory: (_) => client,
      );
      addTearDown(store.close);

      await store.saveSession(_session);

      final refreshFuture = repository.refreshGlobalLists();
      await Future<void>.delayed(Duration.zero);

      expect(client.startedViews, [
        EntryView.all,
        EntryView.feed,
        EntryView.noise,
        EntryView.saved,
      ]);

      client.completeAll();
      await refreshFuture;

      final snapshot = await store.loadSnapshot();
      expect(snapshot.listIds(ListKey.all), [100]);
      expect(snapshot.listIds(ListKey.feed), [101]);
      expect(snapshot.listIds(ListKey.noise), [102]);
      expect(snapshot.listIds(ListKey.saved), [103]);
    });
  });
}

Future<void> _seedEntry(LocalStore store) async {
  await store.saveSession(_session);
  await store.upsertSources([
    FeedSource(
      id: 1,
      name: 'Example',
      rssUrl: 'https://example.com/feed.xml',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 1,
    ),
  ]);
  await store.applyListSnapshot(ListKey.feed, [
    EntryListItem(
      id: 1,
      sourceId: 1,
      sourceName: 'Example',
      title: 'Offline article',
      link: 'https://example.com/1',
      publishedAt: DateTime.utc(2026, 5, 24, 8),
      summary: 'Summary',
      isRead: false,
      isSaved: false,
      readingProgress: 0,
      foreign: false,
      coverImageUrl: null,
    ),
  ]);
  await store.applyListSnapshot(ListKey.noise, const []);
}

Future<void> _seedTwoEntries(LocalStore store) async {
  await _seedEntry(store);
  await store.applyListSnapshot(ListKey.feed, [
    EntryListItem(
      id: 1,
      sourceId: 1,
      sourceName: 'Example',
      title: 'Offline article',
      link: 'https://example.com/1',
      publishedAt: DateTime.utc(2026, 5, 24, 8),
      summary: 'Summary',
      isRead: false,
      isSaved: false,
      readingProgress: 0,
      foreign: false,
      coverImageUrl: null,
    ),
    EntryListItem(
      id: 2,
      sourceId: 1,
      sourceName: 'Example',
      title: 'Second offline article',
      link: 'https://example.com/2',
      publishedAt: DateTime.utc(2026, 5, 24, 7),
      summary: 'Summary 2',
      isRead: false,
      isSaved: false,
      readingProgress: 0,
      foreign: false,
      coverImageUrl: null,
    ),
  ]);
}

Future<void> _seedThreeEntries(LocalStore store) async {
  await _seedTwoEntries(store);
  await store.applyListSnapshot(ListKey.feed, [
    _listItem(1, 'First unread'),
    _listItem(2, 'Second unread'),
    _listItem(3, 'Third unread'),
  ]);
}

Future<void> _seedTwoSources(LocalStore store) async {
  await store.upsertSources([
    FeedSource(
      id: 1,
      name: 'Deleted',
      rssUrl: 'https://deleted.example/feed.xml',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 1,
    ),
    FeedSource(
      id: 2,
      name: 'Kept',
      rssUrl: 'https://kept.example/feed.xml',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 1,
    ),
  ]);
  final deletedEntry = _listItem(
    101,
    'Deleted source article',
    sourceId: 1,
    sourceName: 'Deleted',
  );
  final keptEntry = _listItem(
    202,
    'Kept source article',
    sourceId: 2,
    sourceName: 'Kept',
  );
  await store.applyListSnapshot(ListKey.feed, [deletedEntry, keptEntry]);
  await store.applyListSnapshot(ListKey.source(1), [deletedEntry]);
  await store.applyListSnapshot(ListKey.source(2), [keptEntry]);
}

Future<void> _seedManyEntries(LocalStore store, int count) async {
  await store.saveSession(_session);
  await store.upsertSources([
    FeedSource(
      id: 1,
      name: 'Example',
      rssUrl: 'https://example.com/feed.xml',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: count,
    ),
  ]);
  await store.applyListSnapshot(
    ListKey.feed,
    List<EntryListItem>.generate(
      count,
      (index) => _listItem(index + 1, 'Unread article ${index + 1}'),
    ),
  );
  await store.applyListSnapshot(ListKey.noise, const []);
}

Future<void> _seedFeedAndNoiseEntries(LocalStore store) async {
  await store.saveSession(_session);
  await store.upsertSources([
    FeedSource(
      id: 1,
      name: 'Example',
      rssUrl: 'https://example.com/feed.xml',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 1,
    ),
  ]);
  await store.applyListSnapshot(ListKey.feed, [_listItem(1, 'Feed unread')]);
  await store.applyListSnapshot(ListKey.noise, [
    _listItem(2, 'Noise unread', isNoise: true),
  ]);
}

Future<void> _seedSourceOnlyEntry(LocalStore store) async {
  await store.saveSession(_session);
  await store.upsertSources([
    FeedSource(
      id: 1,
      name: 'Example',
      rssUrl: 'https://example.com/feed.xml',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 1,
    ),
  ]);
  await store.applyListSnapshot(ListKey.feed, const []);
  await store.applyListSnapshot(ListKey.source(1), [
    _listItem(1, 'Source backlog unread'),
  ]);
}

Future<void> _seedSourceOnlySavedEntry(LocalStore store) async {
  await store.saveSession(_session);
  await store.upsertSources([
    FeedSource(
      id: 1,
      name: 'Example',
      rssUrl: 'https://example.com/feed.xml',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 1,
    ),
  ]);
  await store.applyListSnapshot(ListKey.saved, const []);
  await store.applyListSnapshot(ListKey.source(1), [
    _listItem(1, 'Source saved backlog unread', isSaved: true),
  ]);
}

Future<void> _seedSavedFeedAndNoiseEntries(LocalStore store) async {
  await store.saveSession(_session);
  await store.upsertSources([
    FeedSource(
      id: 1,
      name: 'Example',
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
    _listItem(1, 'Saved feed unread', isSaved: true),
    _listItem(3, 'Regular feed unread'),
  ]);
  await store.applyListSnapshot(ListKey.noise, [
    _listItem(2, 'Saved noise unread', isSaved: true, isNoise: true),
  ]);
  await store.applyListSnapshot(ListKey.saved, [
    _listItem(1, 'Saved feed unread', isSaved: true),
    _listItem(2, 'Saved noise unread', isSaved: true, isNoise: true),
  ]);
}

EntryListItem _listItem(
  int id,
  String title, {
  int sourceId = 1,
  String sourceName = 'Example',
  bool isSaved = false,
  bool isNoise = false,
}) {
  return EntryListItem(
    id: id,
    sourceId: sourceId,
    sourceName: sourceName,
    title: title,
    link: 'https://example.com/$id',
    publishedAt: DateTime.utc(2026, 5, 24, 10 - id),
    summary: 'Summary',
    isRead: false,
    isSaved: isSaved,
    isNoise: isNoise,
    readingProgress: 0,
    foreign: false,
    coverImageUrl: null,
  );
}

const _session = SessionData(
  baseUrl: 'https://reader.example',
  token: 'token',
  user: AuthUser(
    id: 1,
    email: 'demo@rsscopilot.local',
    displayName: 'RSS Copilot Demo',
  ),
  lastServerTime: null,
  themeOverride: null,
);

class _RecordingApiClient extends RssApiClient {
  _RecordingApiClient(this.calls) : super(baseUrl: 'https://reader.example');

  final List<String> calls;

  @override
  Future<void> markRead(int entryId) async {
    calls.add('read:$entryId');
  }

  @override
  Future<EntryDetail> fetchEntryDetail(
    int entryId, {
    bool markRead = false,
  }) async {
    calls.add('detail:$entryId:$markRead');
    return EntryDetail(
      id: entryId,
      sourceId: 1,
      sourceName: 'Example',
      title: 'Fetched detail',
      link: 'https://example.com/$entryId',
      publishedAt: DateTime.utc(2026, 5, 24, 8),
      summary: 'Fetched detail summary',
      isRead: markRead,
      foreign: false,
      coverImageUrl: null,
      contentHtml: '<p>Fetched detail</p>',
      filterReason: null,
      translationSegments: const [],
    );
  }

  @override
  Future<int> markEntriesRead(List<int> entryIds) async {
    calls.add('batch-read:${entryIds.join(',')}');
    return entryIds.length;
  }

  @override
  Future<int> markAllRead(
    EntryView view, {
    int? sourceId,
    String? folder,
  }) async {
    calls.add(
      'read-all:${view.wireValue}:${sourceId ?? 'null'}:${folder ?? 'null'}',
    );
    return 1;
  }

  @override
  Future<void> markUnread(int entryId) async {
    calls.add('unread:$entryId');
  }

  @override
  Future<void> markSaved(int entryId) async {
    calls.add('saved:$entryId');
  }

  @override
  Future<void> markUnsaved(int entryId) async {
    calls.add('unsaved:$entryId');
  }

  @override
  Future<void> markNoise(int entryId) async {
    calls.add('noise:$entryId');
  }

  @override
  Future<void> markFeed(int entryId) async {
    calls.add('feed:$entryId');
  }

  @override
  Future<void> updateReadingProgress(int entryId, double progress) async {
    calls.add('progress:$entryId:${progress.toStringAsFixed(2)}');
  }

  @override
  Future<void> reprocessEntryAi(int entryId) async {
    calls.add('reprocess-ai:$entryId');
  }

  @override
  Future<RefreshAcceptedResult> refreshSources(List<int> sourceIds) async {
    calls.add('refresh-sources:${sourceIds.join(',')}');
    return RefreshAcceptedResult(
      accepted: true,
      acceptedCount: sourceIds.length,
      requestedCount: sourceIds.length,
      skippedCount: 0,
    );
  }

  @override
  Future<FeedSource> updateSource(FeedSource source) async {
    calls.add('update-source:${source.id}:${source.rssUrl}');
    return source;
  }

  @override
  Future<SyncPayload> syncChanges(DateTime since) async {
    calls.add('sync-changes:${since.toUtc().toIso8601String()}');
    return SyncPayload(
      serverTime: DateTime.utc(2026, 5, 24, 2),
      sources: const [],
      entries: const [],
      deletedSourceIds: const [],
      settings: const SettingsBundle.empty(),
    );
  }

  @override
  Future<EntryPage> fetchEntries(
    EntryView view, {
    bool unreadOnly = false,
    int limit = 60,
    EntryPageCursor? before,
    String? folder,
    int? sourceId,
    String? searchQuery,
  }) async {
    calls.add(
      'fetch:${view.wireValue}:$unreadOnly:${folder ?? 'null'}:${sourceId ?? 'null'}:${searchQuery ?? 'null'}:${before?.id ?? 'null'}',
    );
    final id = calls.length + 8;
    return EntryPage(
      items: [
        EntryListItem(
          id: id,
          sourceId: sourceId ?? 42,
          sourceName: folder ?? 'All',
          title:
              '${view.wireValue} ${folder ?? 'all'} ${searchQuery ?? 'list'}',
          link: 'https://example.com/fetch/$id',
          publishedAt: DateTime.utc(2026, 5, 24, 9),
          summary: 'Fetched page',
          isRead: false,
          foreign: false,
          coverImageUrl: null,
        ),
      ],
      hasMore: false,
      nextCursor: null,
    );
  }

  @override
  Future<EntryPage> fetchSourceEntries(
    int sourceId, {
    int limit = 60,
    EntryPageCursor? before,
    String? searchQuery,
  }) async {
    calls.add(
      'source-fetch:$sourceId:${searchQuery ?? 'null'}:${before?.id ?? 'null'}',
    );
    return const EntryPage(items: [], hasMore: false, nextCursor: null);
  }
}

class _LogoutNetworkFailureApiClient extends _RecordingApiClient {
  _LogoutNetworkFailureApiClient(super.calls);

  @override
  Future<void> logout() async {
    calls.add('logout');
    throw const NetworkException('offline');
  }
}

class _DeletedSourceSyncApiClient extends _RecordingApiClient {
  _DeletedSourceSyncApiClient(super.calls);

  @override
  Future<SyncPayload> syncChanges(DateTime since) async {
    calls.add('sync-changes:${since.toUtc().toIso8601String()}');
    return SyncPayload(
      serverTime: DateTime.utc(2026, 5, 24, 2),
      sources: const [],
      entries: const [],
      deletedSourceIds: const [1],
      settings: const SettingsBundle.empty(),
    );
  }
}

class _StaleFirstApiClient extends _RecordingApiClient {
  _StaleFirstApiClient(super.calls);

  @override
  Future<void> markRead(int entryId) async {
    calls.add('read:$entryId');
    if (entryId == 1) {
      throw const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'entry not found',
      );
    }
  }
}

class _StaleBatchReadApiClient extends _StaleFirstApiClient {
  _StaleBatchReadApiClient(super.calls);

  @override
  Future<int> markEntriesRead(List<int> entryIds) async {
    calls.add('batch-read:${entryIds.join(',')}');
    throw const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: 'entry not found',
    );
  }
}

class _OverwritingDuringFlushApiClient extends _RecordingApiClient {
  _OverwritingDuringFlushApiClient(super.calls, {required this.onMarkRead});

  final Future<void> Function() onMarkRead;
  bool _overwritten = false;

  @override
  Future<void> markRead(int entryId) async {
    await super.markRead(entryId);
    if (_overwritten) {
      return;
    }
    _overwritten = true;
    await onMarkRead();
  }
}

class _CanonicalSourceSyncApiClient extends _RecordingApiClient {
  _CanonicalSourceSyncApiClient(super.calls);

  @override
  Future<SyncPayload> syncChanges(DateTime since) async {
    calls.add('sync-changes:${since.toUtc().toIso8601String()}');
    return SyncPayload(
      serverTime: DateTime.utc(2026, 5, 24, 2),
      sources: [
        FeedSource(
          id: 1,
          name: 'Canonical',
          rssUrl: 'https://canonical.example/final-feed.xml',
          siteUrl: 'https://canonical.example/',
          iconUrl: null,
          enabled: true,
          lastFetchedAt: DateTime.utc(2026, 5, 24, 1, 30),
          hasError: false,
          unreadCount: 1,
        ),
      ],
      entries: const [],
      deletedSourceIds: const [],
      settings: SettingsBundle.empty(),
    );
  }

  @override
  Future<EntryPage> fetchEntries(
    EntryView view, {
    bool unreadOnly = false,
    int limit = 60,
    EntryPageCursor? before,
    String? folder,
    int? sourceId,
    String? searchQuery,
  }) async {
    calls.add(
      'fetch:${view.wireValue}:$unreadOnly:${folder ?? 'null'}:${sourceId ?? 'null'}:${searchQuery ?? 'null'}:${before?.id ?? 'null'}',
    );
    if (view == EntryView.noise || view == EntryView.saved) {
      return const EntryPage(items: [], hasMore: false, nextCursor: null);
    }
    return EntryPage(
      items: [_listItem(101, 'Canonical source article', sourceId: 1)],
      hasMore: false,
      nextCursor: null,
    );
  }
}

class _BootstrapApiClient extends _RecordingApiClient {
  _BootstrapApiClient(super.calls);

  @override
  Future<SyncPayload> syncBootstrap() async {
    calls.add('bootstrap');
    return SyncPayload(
      serverTime: DateTime.utc(2026, 5, 25, 1),
      sources: [
        FeedSource(
          id: 2,
          name: 'Bootstrap Source',
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
          sourceName: 'Bootstrap Source',
          title: 'Bootstrap article',
          link: 'https://new.example/article',
          publishedAt: DateTime.utc(2026, 5, 25),
          summary: 'Fresh snapshot article',
          isRead: false,
          foreign: false,
          coverImageUrl: null,
          contentHtml: '<p>fresh</p>',
          filterReason: null,
          translationSegments: const [],
        ),
      ],
      deletedSourceIds: const [],
      settings: const SettingsBundle.empty(),
    );
  }
}

class _OpmlImportRefreshApiClient extends _BootstrapApiClient {
  _OpmlImportRefreshApiClient(super.calls);

  @override
  Future<OpmlImportResult> importOpml(
    String opml, {
    required bool refreshAfterImport,
  }) async {
    calls.add('import-opml:$refreshAfterImport');
    return const OpmlImportResult(
      importedCount: 1,
      skippedCount: 0,
      sources: [
        FeedSource(
          id: 8,
          name: 'Imported Refresh Feed',
          rssUrl: 'https://refresh.example/feed.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 0,
        ),
      ],
    );
  }

  @override
  Future<SyncPayload> syncChanges(DateTime since) async {
    calls.add('sync-changes:${since.toUtc().toIso8601String()}');
    return SyncPayload(
      serverTime: DateTime.utc(2026, 5, 25, 2),
      sources: const [],
      entries: const [],
      deletedSourceIds: const [],
      settings: const SettingsBundle.empty(),
    );
  }
}

class _RefreshPollTimeoutApiClient extends _RecordingApiClient {
  _RefreshPollTimeoutApiClient(super.calls);

  @override
  Future<SyncPayload> syncChanges(DateTime since) async {
    calls.add('sync-changes:${since.toUtc().toIso8601String()}');
    throw TimeoutException('sync timed out');
  }
}

class _OpmlImportRefreshTimeoutApiClient extends _OpmlImportRefreshApiClient {
  _OpmlImportRefreshTimeoutApiClient(super.calls);

  @override
  Future<SyncPayload> syncBootstrap() async {
    calls.add('bootstrap');
    return SyncPayload(
      serverTime: DateTime.utc(2026, 5, 25, 1),
      sources: const [
        FeedSource(
          id: 8,
          name: 'Imported Refresh Feed',
          rssUrl: 'https://refresh.example/feed.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 0,
        ),
      ],
      entries: const [],
      deletedSourceIds: const [],
      settings: SettingsBundle.empty(),
    );
  }

  @override
  Future<SyncPayload> syncChanges(DateTime since) async {
    calls.add('sync-changes:${since.toUtc().toIso8601String()}');
    throw TimeoutException('sync timed out');
  }
}

class _BootstrapListFailureApiClient extends _BootstrapApiClient {
  _BootstrapListFailureApiClient(super.calls);

  @override
  Future<EntryPage> fetchEntries(
    EntryView view, {
    bool unreadOnly = false,
    int limit = 60,
    EntryPageCursor? before,
    String? folder,
    int? sourceId,
    String? searchQuery,
  }) async {
    calls.add('fetch:${view.wireValue}');
    throw const NetworkException('list refresh failed');
  }
}

class _InvalidCursorApiClient extends _RecordingApiClient {
  _InvalidCursorApiClient(super.calls);

  @override
  Future<EntryPage> fetchEntries(
    EntryView view, {
    bool unreadOnly = false,
    int limit = 60,
    EntryPageCursor? before,
    String? folder,
    int? sourceId,
    String? searchQuery,
  }) async {
    calls.add('fetch:${view.wireValue}:${before?.id ?? 'null'}');
    throw const ApiException(
      statusCode: 400,
      code: 'BAD_REQUEST',
      message: 'invalid pagination cursor',
    );
  }

  @override
  Future<EntryPage> fetchSourceEntries(
    int sourceId, {
    int limit = 60,
    EntryPageCursor? before,
    String? searchQuery,
  }) async {
    calls.add('source-fetch:$sourceId:${before?.id ?? 'null'}');
    throw const ApiException(
      statusCode: 400,
      code: 'BAD_REQUEST',
      message: 'invalid pagination cursor',
    );
  }
}

class _MissingEntryDetailApiClient extends _RecordingApiClient {
  _MissingEntryDetailApiClient(super.calls);

  @override
  Future<EntryDetail> fetchEntryDetail(
    int entryId, {
    bool markRead = false,
  }) async {
    calls.add('detail:$entryId:$markRead');
    throw const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: 'entry not found',
    );
  }
}

class _MissingSourceEntriesApiClient extends _RecordingApiClient {
  _MissingSourceEntriesApiClient(super.calls);

  @override
  Future<EntryPage> fetchSourceEntries(
    int sourceId, {
    int limit = 60,
    EntryPageCursor? before,
    String? searchQuery,
  }) async {
    calls.add('source-fetch:$sourceId');
    throw const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: 'feed source not found',
    );
  }
}

class _MissingSourceFilteredEntriesApiClient extends _RecordingApiClient {
  _MissingSourceFilteredEntriesApiClient(super.calls);

  @override
  Future<EntryPage> fetchEntries(
    EntryView view, {
    bool unreadOnly = false,
    int limit = 60,
    EntryPageCursor? before,
    String? folder,
    int? sourceId,
    String? searchQuery,
  }) async {
    calls.add(
      'fetch:${view.wireValue}:$unreadOnly:${folder ?? 'null'}:${sourceId ?? 'null'}:${searchQuery ?? 'null'}:${before == null ? 'null' : before.id}',
    );
    throw const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: 'feed source not found',
    );
  }
}

class _MissingSourceReadAllApiClient extends _RecordingApiClient {
  _MissingSourceReadAllApiClient(super.calls);

  @override
  Future<int> markAllRead(
    EntryView view, {
    int? sourceId,
    String? folder,
  }) async {
    calls.add(
      'read-all:${view.wireValue}:${sourceId ?? 'null'}:${folder ?? 'null'}',
    );
    throw const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: 'feed source not found',
    );
  }
}

class _MissingSourceRefreshApiClient extends _RecordingApiClient {
  _MissingSourceRefreshApiClient(super.calls);

  @override
  Future<RefreshAcceptedResult> refreshSource(int sourceId) async {
    calls.add('refresh-source:$sourceId');
    throw const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: 'feed source not found',
    );
  }
}

class _MissingSourceDeleteApiClient extends _RecordingApiClient {
  _MissingSourceDeleteApiClient(super.calls);

  @override
  Future<void> deleteSource(int sourceId) async {
    calls.add('delete-source:$sourceId');
    throw const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: 'feed source not found',
    );
  }
}

class _OpmlImportBootstrapTimeoutApiClient extends _RecordingApiClient {
  _OpmlImportBootstrapTimeoutApiClient(super.calls);

  @override
  Future<OpmlImportResult> importOpml(
    String opml, {
    required bool refreshAfterImport,
  }) async {
    calls.add('import-opml:$refreshAfterImport');
    return const OpmlImportResult(
      importedCount: 1,
      skippedCount: 0,
      sources: [
        FeedSource(
          id: 7,
          name: 'Imported Feed',
          rssUrl: 'https://imported.example/rss',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 0,
        ),
      ],
    );
  }

  @override
  Future<SyncPayload> syncBootstrap() async {
    calls.add('bootstrap');
    throw TimeoutException('bootstrap timed out');
  }
}

class _ConcurrentGlobalListsApiClient extends _RecordingApiClient {
  _ConcurrentGlobalListsApiClient() : super(<String>[]);

  final List<EntryView> startedViews = [];
  final Map<EntryView, Completer<EntryPage>> _pageCompleters = {};

  @override
  Future<EntryPage> fetchEntries(
    EntryView view, {
    bool unreadOnly = false,
    int limit = 60,
    EntryPageCursor? before,
    String? folder,
    int? sourceId,
    String? searchQuery,
  }) {
    startedViews.add(view);
    final completer = Completer<EntryPage>();
    _pageCompleters[view] = completer;
    return completer.future;
  }

  void completeAll() {
    for (final MapEntry(key: view, value: completer)
        in _pageCompleters.entries) {
      completer.complete(
        EntryPage(
          items: [_listItem(_entryIdForView(view), '${view.wireValue} list')],
          hasMore: false,
          nextCursor: null,
        ),
      );
    }
  }

  int _entryIdForView(EntryView view) {
    return switch (view) {
      EntryView.all => 100,
      EntryView.feed => 101,
      EntryView.noise => 102,
      EntryView.saved => 103,
    };
  }
}
