import 'dart:async';

import 'package:rss_copilot_client/src/data/api/api_client.dart';
import 'package:rss_copilot_client/src/data/api/api_exception.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/app_section.dart';
import 'package:rss_copilot_client/src/models/auth_user.dart';
import 'package:rss_copilot_client/src/models/entry_record.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/reader_preferences.dart';
import 'package:rss_copilot_client/src/models/session_data.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:rss_copilot_client/src/repositories/rss_repository.dart';
import 'package:rss_copilot_client/src/state/app_controller.dart';
import 'package:test/test.dart';

void main() {
  group('AppController bulk read actions', () {
    test('marks the selected source read from source entries', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store);
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await controller.openSource(1);
        await controller.markAllRead();

        expect(repository.markSourceReadIds, [1]);
        expect(repository.markAllReadViews, isEmpty);
        expect(controller.state.snapshot.sourceById(1)?.unreadCount, 0);
        expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('marks a folder read and keeps other folders untouched', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store);
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        controller.selectSection(AppSection.sources);
        await controller.markFolderRead('Tech');

        expect(repository.markFolderReadFolders, ['Tech']);
        expect(controller.state.snapshot.sourceById(1)?.unreadCount, 0);
        expect(controller.state.snapshot.sourceById(2)?.unreadCount, 4);
        expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
        expect(controller.state.snapshot.entries[2]?.isRead, isFalse);
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('marks current visible unread entries read in one batch', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store);
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await controller.markVisibleRead();

        expect(repository.markEntriesReadBatches, [
          [1, 2],
        ]);
        expect(repository.markSingleReadIds, isEmpty);
        expect(controller.visibleUnreadCount, 0);
        expect(controller.state.snapshot.entries[1]?.readingProgress, 1);
        expect(controller.state.snapshot.entries[2]?.readingProgress, 1);
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('marks unread entries through the selected entry', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(
        store,
        readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
          lastSection: AppSection.feed.name,
          lastSelectedEntryId: 2,
        ),
      );
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();

        expect(controller.visibleUnreadEntryIdsThroughSelection, [1, 2]);

        await controller.markEntriesRead(
          controller.visibleUnreadEntryIdsThroughSelection,
        );

        expect(repository.markEntriesReadBatches, [
          [1, 2],
        ]);
        expect(controller.visibleUnreadEntryIdsThroughSelection, isEmpty);
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test(
      'mark unread skips stale server entries and restores the rest',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..markSingleUnreadExceptionIds = {1};
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await controller.markEntriesRead([1, 2]);

          await controller.markEntriesUnread([1, 2]);

          expect(repository.markUnreadIds, [1, 2]);
          expect(controller.state.errorMessage, '部分文章已在服务端删除，已从本地移除。');
          expect(controller.state.snapshot.entries.containsKey(1), isFalse);
          expect(controller.state.snapshot.entries[2]?.isRead, isFalse);
          expect(controller.visibleEntries.map((entry) => entry.id), [2]);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'open entry removes stale server entries without raw API text',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..fetchEntryDetailException = const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'entry not found',
          );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);
          await controller.openEntry(1);

          expect(repository.openedEntryIds, [1]);
          expect(controller.state.errorMessage, '文章已在服务端删除，已从本地移除。');
          expect(
            controller.state.errorMessage,
            isNot(contains('entry not found')),
          );
          expect(controller.state.selectedEntryId, 2);
          expect(controller.state.snapshot.entries.containsKey(1), isFalse);
          expect(controller.visibleEntries.map((entry) => entry.id), [2]);
          expect(controller.state.snapshot.sourceById(1)?.unreadCount, 1);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'mark read removes stale server entries without raw API text',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..markSingleReadException = const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'entry not found',
          );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);

          await expectLater(
            controller.toggleEntryRead(1),
            throwsA(
              isA<ApiException>().having(
                (error) => error.isNotFound,
                'isNotFound',
                isTrue,
              ),
            ),
          );

          expect(repository.markSingleReadIds, [1]);
          expect(controller.state.errorMessage, '文章已在服务端删除，已从本地移除。');
          expect(
            controller.state.errorMessage,
            isNot(contains('entry not found')),
          );
          expect(controller.state.selectedEntryId, 2);
          expect(controller.state.snapshot.entries.containsKey(1), isFalse);
          expect(controller.visibleEntries.map((entry) => entry.id), [2]);
          expect(controller.state.snapshot.sourceById(1)?.unreadCount, 1);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test('marks the app offline when AI reprocess loses network', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..reprocessEntryAiException = const NetworkException(
          'offline ai reprocess',
        );
      repository._snapshot = repository._snapshot.copyWith(
        entries: {
          ...repository._snapshot.entries,
          1: repository._snapshot.entries[1]!.copyWith(summaryStatus: 'FAILED'),
        },
      );
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.reprocessSelectedAi(),
          throwsA(isA<NetworkException>()),
        );

        expect(repository.reprocessedEntryIds, [1]);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(
          controller.state.snapshot.entries[1]?.aiProcessingState,
          EntryAiProcessingState.failed,
        );
        expect(controller.state.errorMessage, '当前网络不可用，已切换为离线阅读模式。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('moves the selected entry to noise and opens the next item', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store);
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();

        expect(controller.state.selectedEntryId, 1);

        await controller.moveSelectedToNoiseAndOpenNext();

        expect(repository.noiseEntryUpdates, ['1:true']);
        expect(repository.openedEntryIds, [2]);
        expect(controller.state.selectedEntryId, 2);
        expect(controller.state.snapshot.entries[1]?.isNoise, isTrue);
        expect(controller.visibleEntries.map((entry) => entry.id), [2]);
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test(
      'saves the selected entry for later and opens the next item',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store);
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();

          expect(controller.state.selectedEntryId, 1);

          await controller.saveSelectedForLaterAndOpenNext();

          expect(repository.savedEntryUpdates, ['1:true']);
          expect(repository.markSingleReadIds, [1]);
          expect(repository.openedEntryIds, [2]);
          expect(controller.state.selectedEntryId, 2);
          expect(controller.state.snapshot.entries[1]?.isSaved, isTrue);
          expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
          expect(controller.state.snapshot.entries[2]?.isRead, isTrue);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'does not refresh a source immediately when update disables it',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store);
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          final source = controller.state.snapshot.sourceById(1)!;

          await controller.updateSource(source.copyWith(enabled: false));

          expect(repository.updatedSourceIds, [1]);
          expect(repository.refreshedSourceIds, isEmpty);
          expect(controller.state.snapshot.sourceById(1)?.enabled, isFalse);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'refreshes a source immediately when update keeps it enabled',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store);
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          final source = controller.state.snapshot.sourceById(1)!;

          await controller.updateSource(source.copyWith(name: 'Tech Weekly'));

          expect(repository.updatedSourceIds, [1]);
          expect(repository.refreshedSourceIds, [1]);
          expect(controller.state.snapshot.sourceById(1)?.name, 'Tech Weekly');
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'reloads the current source list after batch source refresh',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store);
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await controller.openSource(1);
          repository.loadedListKeys.clear();

          await controller.refreshSources([1, 2, 1]);

          expect(repository.refreshedSourceIds, [1, 2]);
          expect(repository.loadedListKeys.map((key) => key.value), [
            ListKey.source(1).value,
          ]);
          expect(controller.state.section, AppSection.sourceEntries);
          expect(controller.state.selectedSourceId, 1);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'removes stale selected source when opening source entries returns not found',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..loadSourceEntriesException = const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'feed source not found',
          );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();

          await controller.openSource(1);

          expect(controller.state.section, AppSection.sources);
          expect(controller.state.selectedSourceId, isNull);
          expect(controller.state.selectedEntryId, isNull);
          expect(controller.state.isOnline, isTrue);
          expect(controller.state.errorMessage, '订阅源已在服务端删除，已从本地移除。');
          expect(controller.state.snapshot.sourceById(1), isNull);
          expect(controller.state.snapshot.sourceById(2)?.name, 'Design Daily');
          expect(controller.state.snapshot.entries.containsKey(1), isFalse);
          expect(controller.state.snapshot.entries[2]?.sourceName, 'Source 2');
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'removes stale source when source mark read returns not found',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..markSourceReadException = const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'feed source not found',
          );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await controller.openSource(1);

          await expectLater(
            controller.markAllRead(),
            throwsA(
              isA<ApiException>().having(
                (error) => error.message,
                'message',
                '订阅源已在服务端删除，已从本地移除。',
              ),
            ),
          );

          expect(repository.markSourceReadIds, [1]);
          expect(controller.state.section, AppSection.sources);
          expect(controller.state.selectedSourceId, isNull);
          expect(controller.state.selectedEntryId, isNull);
          expect(controller.state.errorMessage, '订阅源已在服务端删除，已从本地移除。');
          expect(controller.state.snapshot.sourceById(1), isNull);
          expect(controller.state.snapshot.sourceById(2)?.name, 'Design Daily');
          expect(controller.state.snapshot.entries.containsKey(1), isFalse);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'removes stale source when source refresh returns not found',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..refreshSourceException = const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'feed source not found',
          );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();

          await expectLater(
            controller.refreshSource(1),
            throwsA(
              isA<ApiException>().having(
                (error) => error.message,
                'message',
                '订阅源已在服务端删除，已从本地移除。',
              ),
            ),
          );

          expect(repository.refreshedSourceIds, [1]);
          expect(controller.state.section, AppSection.sources);
          expect(controller.state.selectedSourceId, isNull);
          expect(controller.state.selectedEntryId, isNull);
          expect(controller.state.errorMessage, '订阅源已在服务端删除，已从本地移除。');
          expect(controller.state.snapshot.sourceById(1), isNull);
          expect(controller.state.snapshot.sourceById(2)?.name, 'Design Daily');
          expect(controller.state.snapshot.entries.containsKey(1), isFalse);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'clears stale source filter when filtered entries return not found',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..loadSearchEntriesException = const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'feed source not found',
          );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);

          controller.setEntrySourceFilter(1);
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(const Duration(milliseconds: 10));

          expect(repository.loadedListKeys, [ListKey.sourceInView('feed', 1)]);
          expect(controller.state.section, AppSection.feed);
          expect(controller.state.entrySourceFilterId, isNull);
          expect(controller.state.selectedSourceId, isNull);
          expect(controller.state.errorMessage, '订阅源已在服务端删除，已清除来源筛选。');
          expect(controller.state.snapshot.sourceById(1), isNull);
          expect(controller.state.snapshot.sourceById(2)?.name, 'Design Daily');
          expect(controller.state.snapshot.entries.containsKey(1), isFalse);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test('marks the app offline when loading more entries times out', () async {
      final store = await LocalStore.inMemory();
      final feedKey = ListKey.feed;
      final repository = _BulkReadRepository(store)
        ..loadMoreEntriesException = TimeoutException('slow history load');
      repository._snapshot = repository._snapshot.copyWith(
        listHasMore: {feedKey.value: true},
      );
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        expect(controller.canLoadMoreEntries, isTrue);

        await expectLater(
          controller.loadMoreEntries(),
          throwsA(isA<TimeoutException>()),
        );

        expect(repository.loadedMoreListKeys, [feedKey]);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.errorMessage, '加载历史文章超时，请稍后重试。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test(
      'clears stale source filter when loading more returns not found',
      () async {
        final store = await LocalStore.inMemory();
        final sourceFilterKey = ListKey.sourceInView('feed', 1);
        final repository = _BulkReadRepository(store)
          ..loadMoreEntriesException = const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'feed source not found',
          );
        repository._snapshot = repository._snapshot.copyWith(
          listHasMore: {sourceFilterKey.value: true},
        );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);

          controller.setEntrySourceFilter(1);
          await Future<void>.delayed(Duration.zero);

          expect(controller.canLoadMoreEntries, isTrue);

          await expectLater(
            controller.loadMoreEntries(),
            throwsA(
              isA<ApiException>().having(
                (error) => error.message,
                'message',
                '订阅源已在服务端删除，已清除来源筛选。',
              ),
            ),
          );

          expect(repository.loadedMoreListKeys, [sourceFilterKey]);
          expect(controller.state.entrySourceFilterId, isNull);
          expect(controller.state.selectedSourceId, isNull);
          expect(controller.state.errorMessage, '订阅源已在服务端删除，已清除来源筛选。');
          expect(controller.state.snapshot.sourceById(1), isNull);
          expect(controller.state.snapshot.entries.containsKey(1), isFalse);
          expect(controller.visibleEntries.map((entry) => entry.id), [2]);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test('falls back to feed when restored source no longer exists', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(
        store,
        readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
          lastSection: AppSection.sourceEntries.name,
          lastSelectedSourceId: 99,
          lastSelectedEntryId: 99,
        ),
      );
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.section, AppSection.feed);
        expect(controller.state.selectedSourceId, isNull);
        expect(controller.state.selectedEntryId, 1);
        expect(
          controller.state.readerPreferences.lastSection,
          AppSection.feed.name,
        );
        expect(controller.state.readerPreferences.lastSelectedSourceId, isNull);
        expect(controller.state.readerPreferences.lastSelectedEntryId, 1);
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test(
      'keeps restored source filter when source has no cached entries',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(
          store,
          includeEmptyCatalogSource: true,
          readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
            lastSection: AppSection.feed.name,
            lastEntrySourceFilterId: 3,
          ),
        );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);

          expect(controller.state.section, AppSection.feed);
          expect(controller.state.entrySourceFilterId, 3);
          expect(controller.visibleEntries, isEmpty);
          expect(controller.state.selectedEntryId, isNull);
          expect(controller.state.readerPreferences.lastEntrySourceFilterId, 3);
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'keeps restored folder filter when folder has no cached entries',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(
          store,
          includeEmptyCatalogSource: true,
          readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
            lastSection: AppSection.feed.name,
            lastEntryFolderFilter: 'Backlog',
          ),
        );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);

          expect(controller.state.section, AppSection.feed);
          expect(controller.state.entryFolderFilter, 'Backlog');
          expect(controller.visibleEntries, isEmpty);
          expect(controller.state.selectedEntryId, isNull);
          expect(
            controller.state.readerPreferences.lastEntryFolderFilter,
            'Backlog',
          );
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'clears stale folder filter when folder mark read returns not found',
      () async {
        final store = await LocalStore.inMemory();
        final repository =
            _BulkReadRepository(
                store,
                includeEmptyCatalogSource: true,
                readerPreferences: ReaderPreferences.defaultPreferences
                    .copyWith(
                      lastSection: AppSection.feed.name,
                      lastEntryFolderFilter: 'Backlog',
                    ),
              )
              ..markFolderReadException = const ApiException(
                statusCode: 404,
                code: 'NOT_FOUND',
                message: 'folder not found',
              );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);

          expect(controller.state.entryFolderFilter, 'Backlog');
          expect(controller.visibleEntries, isEmpty);

          await expectLater(
            controller.markFolderRead('Backlog'),
            throwsA(
              isA<ApiException>().having(
                (error) => error.isNotFound,
                'isNotFound',
                isTrue,
              ),
            ),
          );

          expect(repository.markFolderReadFolders, ['Backlog']);
          expect(controller.state.entryFolderFilter, isNull);
          expect(controller.state.selectedEntryId, 1);
          expect(controller.visibleEntries.map((entry) => entry.id), [1, 2]);
          expect(controller.state.errorMessage, '文件夹范围已在服务端变化，已清除文件夹筛选。');
          expect(
            controller.state.errorMessage,
            isNot(contains('folder not found')),
          );
          expect(
            controller.state.readerPreferences.lastEntryFolderFilter,
            isNull,
          );
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test(
      'keeps an added source visible when the first refresh times out',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..refreshSourceException = TimeoutException('slow source refresh');
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();

          await expectLater(
            controller.addSource('https://example.com/new.xml'),
            throwsA(
              isA<SourceRefreshAfterSaveException>()
                  .having(
                    (error) => error.action,
                    'action',
                    SourceSaveAction.add,
                  )
                  .having(
                    (error) => error.cause,
                    'cause',
                    isA<TimeoutException>(),
                  ),
            ),
          );

          expect(repository.addedSourceUrls, ['https://example.com/new.xml']);
          expect(repository.refreshedSourceIds, [3]);
          expect(controller.state.busy, isFalse);
          expect(controller.state.isOnline, isFalse);
          expect(controller.state.section, AppSection.sourceEntries);
          expect(controller.state.selectedSourceId, 3);
          expect(
            controller.state.snapshot.sourceById(3)?.rssUrl,
            'https://example.com/new.xml',
          );
          expect(controller.state.errorMessage, '请求超时，请稍后重试。');
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test('marks the app offline when source create times out', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..addSourceException = TimeoutException('slow source create');
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.addSource('https://example.com/new.xml'),
          throwsA(isA<TimeoutException>()),
        );

        expect(repository.addedSourceUrls, ['https://example.com/new.xml']);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.snapshot.sourceById(3), isNull);
        expect(controller.state.errorMessage, '请求超时，请稍后重试。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('marks the app offline when refresh all times out', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..refreshAllException = TimeoutException('slow refresh all');
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.refreshAll(),
          throwsA(isA<TimeoutException>()),
        );

        expect(repository.refreshAllRequests, 1);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.errorMessage, '请求超时，请稍后重试。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test(
      'keeps edited source fields visible when follow-up refresh times out',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..refreshSourceException = TimeoutException('slow source refresh');
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          final source = controller.state.snapshot.sourceById(1)!;

          await expectLater(
            controller.updateSource(source.copyWith(name: 'Tech Weekly')),
            throwsA(
              isA<SourceRefreshAfterSaveException>()
                  .having(
                    (error) => error.action,
                    'action',
                    SourceSaveAction.update,
                  )
                  .having(
                    (error) => error.cause,
                    'cause',
                    isA<TimeoutException>(),
                  ),
            ),
          );

          expect(repository.updatedSourceIds, [1]);
          expect(repository.refreshedSourceIds, [1]);
          expect(controller.state.busy, isFalse);
          expect(controller.state.isOnline, isFalse);
          expect(controller.state.snapshot.sourceById(1)?.name, 'Tech Weekly');
          expect(controller.state.errorMessage, '请求超时，请稍后重试。');
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test('marks the app offline when source update loses network', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..updateSourceException = const NetworkException(
          'offline source update',
        );
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);
        final source = controller.state.snapshot.sourceById(1)!;

        await expectLater(
          controller.updateSource(source.copyWith(name: 'Tech Weekly')),
          throwsA(isA<NetworkException>()),
        );

        expect(repository.updatedSourceIds, [1]);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.snapshot.sourceById(1)?.name, 'Tech Daily');
        expect(controller.state.errorMessage, '当前网络不可用，已切换为离线阅读模式。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('marks the app offline when source delete times out', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..deleteSourceException = TimeoutException('slow source delete');
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.deleteSource(1),
          throwsA(isA<TimeoutException>()),
        );

        expect(repository.deletedSourceIds, [1]);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.snapshot.sourceById(1)?.name, 'Tech Daily');
        expect(controller.state.errorMessage, '请求超时，请稍后重试。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('marks the app offline when source delete loses network', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..deleteSourceException = const NetworkException(
          'offline source delete',
        );
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.deleteSource(1),
          throwsA(isA<NetworkException>()),
        );

        expect(repository.deletedSourceIds, [1]);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.snapshot.sourceById(1)?.name, 'Tech Daily');
        expect(controller.state.errorMessage, '当前网络不可用，已切换为离线阅读模式。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('marks the app offline when feed settings save times out', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..updateFeedSettingsException = TimeoutException('slow feed settings');
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.saveFeedSettings('en-US'),
          throwsA(isA<TimeoutException>()),
        );

        expect(repository.updatedFeedLanguages, ['en-US']);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(
          controller.state.snapshot.settings.feeds.defaultLanguage,
          'zh-CN',
        );
        expect(controller.state.errorMessage, '请求超时，请稍后重试。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test(
      'marks the app offline when appearance settings save times out',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..updateAppearanceSettingsException = TimeoutException(
            'slow appearance settings',
          );
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();
          await Future<void>.delayed(Duration.zero);

          await expectLater(
            controller.saveAppearanceSettings(AppThemeMode.dark),
            throwsA(isA<TimeoutException>()),
          );

          expect(repository.updatedAppearanceModes, [AppThemeMode.dark]);
          expect(controller.state.busy, isFalse);
          expect(controller.state.isOnline, isFalse);
          expect(
            controller.state.snapshot.settings.appearance.themeMode,
            AppThemeMode.system,
          );
          expect(controller.state.errorMessage, '请求超时，请稍后重试。');
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test('marks the app offline when AI settings save loses network', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..updateAiSettingsException = const NetworkException(
          'offline ai settings',
        );
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);
        final currentAiSettings = controller.state.snapshot.settings.ai;
        final nextAiSettings = currentAiSettings.copyWith(
          autoSummaryEnabled: true,
        );

        await expectLater(
          controller.saveAiSettings(settings: nextAiSettings),
          throwsA(isA<NetworkException>()),
        );

        expect(repository.updatedAiSettings, [nextAiSettings]);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(
          controller.state.snapshot.settings.ai.autoSummaryEnabled,
          isFalse,
        );
        expect(controller.state.errorMessage, '当前网络不可用，已切换为离线阅读模式。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test(
      'keeps imported OPML sources visible when follow-up sync times out',
      () async {
        final store = await LocalStore.inMemory();
        final repository = _BulkReadRepository(store)
          ..importOpmlSyncExceptionCause = TimeoutException('sync timed out');
        final controller = AppController(repository: repository);
        try {
          await controller.initialize();

          await expectLater(
            controller.importOpml(
              '<opml version="2.0"></opml>',
              refreshAfterImport: false,
            ),
            throwsA(
              isA<OpmlImportSyncAfterSuccessException>()
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

          expect(repository.importedOpmlRequests, [
            (opml: '<opml version="2.0"></opml>', refreshAfterImport: false),
          ]);
          expect(controller.state.busy, isFalse);
          expect(controller.state.isOnline, isFalse);
          expect(controller.state.section, AppSection.sources);
          expect(controller.state.snapshot.sourceById(4)?.name, 'OPML Feed');
        } finally {
          controller.dispose();
          await store.close();
        }
      },
    );

    test('marks the app offline when OPML import loses network', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..importOpmlException = const NetworkException('offline opml import');
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.importOpml(
            '<opml version="2.0"></opml>',
            refreshAfterImport: true,
          ),
          throwsA(isA<NetworkException>()),
        );

        expect(repository.importedOpmlRequests, [
          (opml: '<opml version="2.0"></opml>', refreshAfterImport: true),
        ]);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.snapshot.sourceById(4), isNull);
        expect(controller.state.errorMessage, '当前网络不可用，已切换为离线阅读模式。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });

    test('marks the app offline when OPML import times out', () async {
      final store = await LocalStore.inMemory();
      final repository = _BulkReadRepository(store)
        ..importOpmlException = TimeoutException('slow opml import');
      final controller = AppController(repository: repository);
      try {
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.importOpml(
            '<opml version="2.0"></opml>',
            refreshAfterImport: true,
          ),
          throwsA(isA<TimeoutException>()),
        );

        expect(repository.importedOpmlRequests, [
          (opml: '<opml version="2.0"></opml>', refreshAfterImport: true),
        ]);
        expect(controller.state.busy, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.snapshot.sourceById(4), isNull);
        expect(controller.state.errorMessage, '请求超时，请稍后重试。');
      } finally {
        controller.dispose();
        await store.close();
      }
    });
  });
}

class _BulkReadRepository extends RssRepository {
  _BulkReadRepository(
    LocalStore store, {
    ReaderPreferences? readerPreferences,
    bool includeEmptyCatalogSource = false,
  }) : _readerPreferences =
           readerPreferences ?? ReaderPreferences.defaultPreferences,
       super(store: store) {
    if (includeEmptyCatalogSource) {
      _snapshot = _snapshot.copyWith(
        sources: [
          ..._snapshot.sources,
          const FeedSource(
            id: 3,
            name: 'Backlog Daily',
            folder: 'Backlog',
            rssUrl: 'https://example.com/backlog.xml',
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
  }

  final List<EntryView> markAllReadViews = <EntryView>[];
  final List<int> markSourceReadIds = <int>[];
  final List<String> markFolderReadFolders = <String>[];
  final List<int> markSingleReadIds = <int>[];
  final List<int> markUnreadIds = <int>[];
  final List<List<int>> markEntriesReadBatches = <List<int>>[];
  final List<int> openedEntryIds = <int>[];
  final List<String> addedSourceUrls = <String>[];
  final List<({String opml, bool refreshAfterImport})> importedOpmlRequests =
      <({String opml, bool refreshAfterImport})>[];
  final List<int> updatedSourceIds = <int>[];
  final List<int> refreshedSourceIds = <int>[];
  final List<int> deletedSourceIds = <int>[];
  final List<int> reprocessedEntryIds = <int>[];
  final List<AiSettings> updatedAiSettings = <AiSettings>[];
  final List<AppThemeMode> updatedAppearanceModes = <AppThemeMode>[];
  final List<String> updatedFeedLanguages = <String>[];
  int refreshAllRequests = 0;
  final List<ListKey> loadedListKeys = <ListKey>[];
  final List<ListKey> loadedMoreListKeys = <ListKey>[];
  final List<String> savedEntryUpdates = <String>[];
  final List<String> noiseEntryUpdates = <String>[];
  ReaderPreferences _readerPreferences;
  Object? refreshAllException;
  Object? addSourceException;
  Object? updateSourceException;
  Object? refreshSourceException;
  Object? deleteSourceException;
  Object? updateAiSettingsException;
  Object? updateAppearanceSettingsException;
  Object? updateFeedSettingsException;
  Object? reprocessEntryAiException;
  Object? markSourceReadException;
  Object? markFolderReadException;
  Object? markSingleReadException;
  Object? loadMoreEntriesException;
  Set<int> markSingleUnreadExceptionIds = const {};
  Object? loadSourceEntriesException;
  Object? loadSearchEntriesException;
  Object? fetchEntryDetailException;
  Object? importOpmlException;
  Object? importOpmlSyncExceptionCause;

  static const _session = SessionData(
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

  AppSnapshot _snapshot = AppSnapshot(
    sources: const [
      FeedSource(
        id: 1,
        name: 'Tech Daily',
        folder: 'Tech',
        rssUrl: 'https://example.com/tech.xml',
        siteUrl: null,
        iconUrl: null,
        enabled: true,
        lastFetchedAt: null,
        hasError: false,
        unreadCount: 2,
      ),
      FeedSource(
        id: 2,
        name: 'Design Daily',
        folder: 'Design',
        rssUrl: 'https://example.com/design.xml',
        siteUrl: null,
        iconUrl: null,
        enabled: true,
        lastFetchedAt: null,
        hasError: false,
        unreadCount: 4,
      ),
    ],
    settings: const SettingsBundle.empty(),
    entries: {
      1: _entry(1, sourceId: 1, title: 'Tech unread', isRead: false),
      2: _entry(2, sourceId: 2, title: 'Design unread', isRead: false),
    },
    listSnapshots: const {
      'feed': [1, 2],
      'source:1': [1],
      'source:2': [2],
    },
    listHasMore: const {},
    listCursors: const {},
  );

  @override
  Future<SessionData?> loadSession() async => _session;

  @override
  Future<AppSnapshot> loadSnapshot() async => _snapshot;

  @override
  Future<void> verifySession() async {}

  @override
  Future<void> sync() async {}

  @override
  Future<EntryRecord?> fetchEntryDetail(
    int entryId, {
    bool markRead = false,
  }) async {
    openedEntryIds.add(entryId);
    final exception = fetchEntryDetailException;
    if (exception != null) {
      if (exception is ApiException && exception.isNotFound) {
        _deleteEntry(entryId);
      }
      throw exception;
    }
    if (markRead) {
      _snapshot = _snapshot.copyWith(
        entries: {
          ..._snapshot.entries,
          entryId: _snapshot.entries[entryId]!.copyWith(isRead: true),
        },
      );
    }
    return _snapshot.entries[entryId];
  }

  @override
  Future<ReaderPreferences> loadReaderPreferences() async {
    return _readerPreferences;
  }

  @override
  Future<void> saveReaderPreferences(ReaderPreferences preferences) async {
    _readerPreferences = preferences;
  }

  @override
  Future<void> loadSourceEntries(int sourceId) async {
    final exception = loadSourceEntriesException;
    if (exception != null) {
      if (exception is ApiException && exception.isNotFound) {
        _removeSource(sourceId);
      }
      throw exception;
    }
  }

  @override
  Future<void> loadSearchEntries(ListKey key) async {
    loadedListKeys.add(key);
    final exception = loadSearchEntriesException;
    if (exception != null) {
      if (exception is ApiException && exception.isNotFound) {
        final sourceIds = _snapshot.sources.map((source) => source.id).toSet();
        for (final sourceId in sourceIds) {
          if (ListKey.isSourceScopedValue(key.value, {sourceId})) {
            _removeSource(sourceId);
            break;
          }
        }
      }
      throw exception;
    }
  }

  @override
  Future<void> loadMoreEntries(ListKey key) async {
    loadedMoreListKeys.add(key);
    final exception = loadMoreEntriesException;
    if (exception != null) {
      if (exception is ApiException && exception.isNotFound) {
        final sourceIds = _snapshot.sources.map((source) => source.id).toSet();
        for (final sourceId in sourceIds) {
          if (ListKey.isSourceScopedValue(key.value, {sourceId})) {
            _removeSource(sourceId);
            break;
          }
        }
      }
      throw exception;
    }
  }

  @override
  Future<FeedSource> addSource(String rssUrl, {String? folder}) async {
    addedSourceUrls.add(rssUrl);
    final exception = addSourceException;
    if (exception != null) {
      throw exception;
    }
    final source = FeedSource(
      id: 3,
      name: 'New Source',
      folder: folder ?? defaultSourceFolder,
      rssUrl: rssUrl,
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 0,
    );
    _snapshot = _snapshot.copyWith(sources: [..._snapshot.sources, source]);
    return source;
  }

  @override
  Future<FeedSource> updateSource(FeedSource source) async {
    updatedSourceIds.add(source.id);
    final exception = updateSourceException;
    if (exception != null) {
      throw exception;
    }
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final existing in _snapshot.sources)
          existing.id == source.id ? source : existing,
      ],
    );
    return source;
  }

  void _removeSource(int sourceId) {
    final removedEntryIds = _snapshot.entries.values
        .where((entry) => entry.sourceId == sourceId)
        .map((entry) => entry.id)
        .toSet();
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final source in _snapshot.sources)
          if (source.id != sourceId) source,
      ],
      entries: {
        for (final entry in _snapshot.entries.entries)
          if (!removedEntryIds.contains(entry.key)) entry.key: entry.value,
      },
      listSnapshots: {
        for (final list in _snapshot.listSnapshots.entries)
          if (!ListKey.isSourceScopedValue(list.key, {sourceId}))
            list.key: [
              for (final entryId in list.value)
                if (!removedEntryIds.contains(entryId)) entryId,
            ],
      },
    );
  }

  @override
  Future<void> deleteSource(int sourceId) async {
    deletedSourceIds.add(sourceId);
    final exception = deleteSourceException;
    if (exception != null) {
      throw exception;
    }
    _removeSource(sourceId);
  }

  @override
  Future<SettingsBundle> updateAiSettings({
    required AiSettings current,
    String? rawApiKey,
    bool clearApiKey = false,
  }) async {
    updatedAiSettings.add(current);
    final exception = updateAiSettingsException;
    if (exception != null) {
      throw exception;
    }
    final nextSettings = _snapshot.settings.copyWith(ai: current);
    _snapshot = _snapshot.copyWith(settings: nextSettings);
    return nextSettings;
  }

  @override
  Future<SettingsBundle> updateAppearanceSettings(
    AppThemeMode themeMode,
  ) async {
    updatedAppearanceModes.add(themeMode);
    final exception = updateAppearanceSettingsException;
    if (exception != null) {
      throw exception;
    }
    final nextSettings = _snapshot.settings.copyWith(
      appearance: AppearanceSettings(themeMode: themeMode),
    );
    _snapshot = _snapshot.copyWith(settings: nextSettings);
    return nextSettings;
  }

  @override
  Future<SettingsBundle> updateFeedSettings(String defaultLanguage) async {
    updatedFeedLanguages.add(defaultLanguage);
    final exception = updateFeedSettingsException;
    if (exception != null) {
      throw exception;
    }
    final nextSettings = _snapshot.settings.copyWith(
      feeds: FeedSettings(
        defaultLanguage: defaultLanguage,
        refreshPolicyDescription:
            _snapshot.settings.feeds.refreshPolicyDescription,
      ),
      ai: _snapshot.settings.ai.copyWith(outputLanguage: defaultLanguage),
    );
    _snapshot = _snapshot.copyWith(settings: nextSettings);
    return nextSettings;
  }

  @override
  Future<OpmlImportResult> importOpml(
    String opml, {
    required bool refreshAfterImport,
  }) async {
    importedOpmlRequests.add((
      opml: opml,
      refreshAfterImport: refreshAfterImport,
    ));
    final exception = importOpmlException;
    if (exception != null) {
      throw exception;
    }
    final source = FeedSource(
      id: 4,
      name: 'OPML Feed',
      rssUrl: 'https://opml.example/rss',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 0,
    );
    _snapshot = _snapshot.copyWith(sources: [..._snapshot.sources, source]);
    final result = OpmlImportResult(
      importedCount: 1,
      skippedCount: 0,
      sources: _snapshot.sources,
    );
    final cause = importOpmlSyncExceptionCause;
    if (cause != null) {
      throw OpmlImportSyncException(result: result, cause: cause);
    }
    return result;
  }

  @override
  Future<RefreshAcceptedResult> refreshSourceAndPoll(int sourceId) async {
    refreshedSourceIds.add(sourceId);
    final exception = refreshSourceException;
    if (exception != null) {
      if (exception is ApiException && exception.isNotFound) {
        _removeSource(sourceId);
      }
      throw exception;
    }
    return const RefreshAcceptedResult(
      accepted: true,
      acceptedCount: 1,
      requestedCount: 1,
      skippedCount: 0,
    );
  }

  @override
  Future<RefreshAcceptedResult> refreshSourcesAndPoll(
    Iterable<int> sourceIds,
  ) async {
    final ids = sourceIds.toList(growable: false);
    refreshedSourceIds.addAll(ids);
    return RefreshAcceptedResult(
      accepted: true,
      acceptedCount: ids.length,
      requestedCount: ids.length,
      skippedCount: 0,
    );
  }

  @override
  Future<RefreshAcceptedResult> refreshAllAndPoll() async {
    refreshAllRequests += 1;
    final exception = refreshAllException;
    if (exception != null) {
      throw exception;
    }
    return const RefreshAcceptedResult(
      accepted: true,
      acceptedCount: 2,
      requestedCount: 2,
      skippedCount: 0,
    );
  }

  @override
  Future<void> markAllRead(EntryView view) async {
    markAllReadViews.add(view);
  }

  @override
  Future<void> markRead(int entryId) async {
    markSingleReadIds.add(entryId);
    final exception = markSingleReadException;
    if (exception != null) {
      if (exception is ApiException && exception.isNotFound) {
        _deleteEntry(entryId);
      }
      throw exception;
    }
    _snapshot = _snapshot.copyWith(
      entries: {
        ..._snapshot.entries,
        entryId: _snapshot.entries[entryId]!.copyWith(
          isRead: true,
          readingProgress: 1,
        ),
      },
    );
  }

  @override
  Future<void> markUnread(int entryId) async {
    markUnreadIds.add(entryId);
    if (markSingleUnreadExceptionIds.contains(entryId)) {
      _deleteEntry(entryId);
      throw const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'entry not found',
      );
    }
    final entry = _snapshot.entries[entryId];
    if (entry == null) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      entries: {
        ..._snapshot.entries,
        entryId: entry.copyWith(isRead: false, readingProgress: 0),
      },
    );
  }

  void _deleteEntry(int entryId) {
    final entry = _snapshot.entries[entryId];
    final entries = {..._snapshot.entries}..remove(entryId);
    final listSnapshots = <String, List<int>>{
      for (final listEntry in _snapshot.listSnapshots.entries)
        listEntry.key: listEntry.value
            .where((cachedEntryId) => cachedEntryId != entryId)
            .toList(growable: false),
    };
    final sources = entry == null || entry.isRead
        ? _snapshot.sources
        : _snapshot.sources
              .map(
                (source) => source.id == entry.sourceId
                    ? source.copyWith(
                        unreadCount: source.unreadCount - 1 < 0
                            ? 0
                            : source.unreadCount - 1,
                      )
                    : source,
              )
              .toList(growable: false);
    _snapshot = _snapshot.copyWith(
      sources: sources,
      entries: entries,
      listSnapshots: listSnapshots,
    );
  }

  @override
  Future<void> markEntriesRead(List<int> entryIds) async {
    markEntriesReadBatches.add(entryIds);
    final entryIdSet = entryIds.toSet();
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final source in _snapshot.sources)
          source.copyWith(
            unreadCount:
                source.unreadCount -
                _snapshot.entries.values
                    .where(
                      (entry) =>
                          entry.sourceId == source.id &&
                          entryIdSet.contains(entry.id) &&
                          !entry.isRead,
                    )
                    .length,
          ),
      ],
      entries: {
        for (final entry in _snapshot.entries.entries)
          entry.key: entryIdSet.contains(entry.key)
              ? entry.value.copyWith(isRead: true, readingProgress: 1)
              : entry.value,
      },
    );
  }

  @override
  Future<void> reprocessEntryAi(int entryId) async {
    reprocessedEntryIds.add(entryId);
    final exception = reprocessEntryAiException;
    if (exception != null) {
      throw exception;
    }
    final entry = _snapshot.entries[entryId];
    if (entry == null) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      entries: {
        ..._snapshot.entries,
        entryId: entry.copyWith(
          filterStatus: 'PENDING',
          summaryStatus: 'PENDING',
          translationStatus: 'PENDING',
        ),
      },
    );
  }

  @override
  Future<void> setSaved(int entryId, bool isSaved) async {
    savedEntryUpdates.add('$entryId:$isSaved');
    final entry = _snapshot.entries[entryId];
    if (entry == null) {
      return;
    }

    final savedIds = _snapshot.listIds(ListKey.saved).toList(growable: true)
      ..remove(entryId);
    if (isSaved) {
      savedIds.add(entryId);
    }
    _snapshot = _snapshot.copyWith(
      entries: {
        ..._snapshot.entries,
        entryId: entry.copyWith(isSaved: isSaved),
      },
      listSnapshots: {
        ..._snapshot.listSnapshots,
        ListKey.saved.value: savedIds,
      },
    );
  }

  @override
  Future<void> setEntryNoise(int entryId, bool isNoise) async {
    noiseEntryUpdates.add('$entryId:$isNoise');
    final entry = _snapshot.entries[entryId];
    if (entry == null) {
      return;
    }

    final feedIds = _snapshot
        .listIds(ListKey.feed)
        .where((id) => isNoise ? id != entryId : true)
        .toList(growable: false);
    final noiseIds = _snapshot.listIds(ListKey.noise).toList(growable: true)
      ..remove(entryId);
    if (isNoise) {
      noiseIds.add(entryId);
    }
    _snapshot = _snapshot.copyWith(
      entries: {
        ..._snapshot.entries,
        entryId: entry.copyWith(isNoise: isNoise),
      },
      listSnapshots: {
        ..._snapshot.listSnapshots,
        ListKey.feed.value: isNoise
            ? feedIds
            : [...feedIds, if (!feedIds.contains(entryId)) entryId],
        ListKey.noise.value: noiseIds,
      },
    );
  }

  @override
  Future<void> markSourceRead(int sourceId) async {
    markSourceReadIds.add(sourceId);
    final exception = markSourceReadException;
    if (exception != null) {
      if (exception is ApiException && exception.isNotFound) {
        _removeSource(sourceId);
      }
      throw exception;
    }
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final source in _snapshot.sources)
          source.id == sourceId ? source.copyWith(unreadCount: 0) : source,
      ],
      entries: {
        for (final entry in _snapshot.entries.entries)
          entry.key: entry.value.sourceId == sourceId
              ? entry.value.copyWith(isRead: true, readingProgress: 1)
              : entry.value,
      },
    );
  }

  @override
  Future<void> markFolderRead(String folder) async {
    markFolderReadFolders.add(folder);
    final exception = markFolderReadException;
    if (exception != null) {
      throw exception;
    }
    final sourceIds = _snapshot.sources
        .where((source) => source.folder == folder)
        .map((source) => source.id)
        .toSet();
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final source in _snapshot.sources)
          sourceIds.contains(source.id)
              ? source.copyWith(unreadCount: 0)
              : source,
      ],
      entries: {
        for (final entry in _snapshot.entries.entries)
          entry.key: sourceIds.contains(entry.value.sourceId)
              ? entry.value.copyWith(isRead: true, readingProgress: 1)
              : entry.value,
      },
    );
  }

  static EntryRecord _entry(
    int id, {
    required int sourceId,
    required String title,
    required bool isRead,
  }) {
    return EntryRecord(
      id: id,
      sourceId: sourceId,
      sourceName: 'Source $sourceId',
      title: title,
      link: 'https://example.com/$id',
      publishedAt: DateTime.utc(2026, 5, 24, 12 - id),
      summary: 'Summary $id',
      isRead: isRead,
      isSaved: false,
      foreign: false,
      coverImageUrl: null,
      contentHtml: null,
      filterReason: null,
      translationSegments: const [],
    );
  }
}
