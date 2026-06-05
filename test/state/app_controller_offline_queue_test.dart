import 'dart:async';

import 'package:rss_copilot_client/src/data/api/api_exception.dart';
import 'package:rss_copilot_client/src/data/api/api_client.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/auth_user.dart';
import 'package:rss_copilot_client/src/models/entry_record.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/reader_preferences.dart';
import 'package:rss_copilot_client/src/models/session_data.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:rss_copilot_client/src/repositories/rss_repository.dart';
import 'package:rss_copilot_client/src/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears local state when the saved session is rejected', () async {
    final store = await LocalStore.inMemory();
    final repository = _ExpiredSessionRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(repository.clearLocalDataCalls, 1);
    expect(controller.state.session, isNull);
    expect(controller.state.isAuthenticated, isFalse);
    expect(controller.state.isOnline, isFalse);
    expect(controller.state.snapshot.entries, isEmpty);
    expect(controller.state.pendingSyncCount, 0);
    expect(controller.state.errorMessage, '登录状态已失效，请重新登录。');
  });

  test('queues high-frequency entry actions while offline', () async {
    final store = await LocalStore.inMemory();
    final repository = _OfflineQueueRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await controller.syncNow();

    expect(controller.state.isOnline, isFalse);

    await controller.openEntry(1);
    await controller.toggleSelectedSaved();
    controller.updateReadingProgress(1, 0.42);
    await controller.toggleSelectedNoise();
    await Future<void>.delayed(Duration.zero);
    await controller.markVisibleRead();

    expect(repository.queuedReadStates, ['1:true']);
    expect(repository.queuedSavedStates, ['1:true']);
    expect(repository.queuedNoiseStates, ['1:true']);
    expect(repository.queuedProgress, isEmpty);
    expect(repository.queuedReadBatches, [
      [2],
    ]);
    expect(controller.state.pendingSyncCount, 4);
    expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
    expect(controller.state.snapshot.entries[1]?.isSaved, isTrue);
    expect(controller.state.snapshot.entries[1]?.isNoise, isTrue);
    expect(controller.state.snapshot.entries[1]?.readingProgress, 1);
    expect(controller.state.snapshot.entries[2]?.isRead, isTrue);
  });

  test(
    'queues high-frequency entry actions when an online write loses network',
    () async {
      final store = await LocalStore.inMemory();
      final repository = _TransientWriteFailureRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });

      await controller.initialize();
      await controller.syncNow();

      expect(controller.state.isOnline, isTrue);

      await controller.toggleEntryRead(1);

      expect(repository.markUnreadCalls, 1);
      expect(repository.queuedReadStates, ['1:false']);
      expect(controller.state.isOnline, isFalse);
      expect(controller.state.pendingSyncCount, 1);
      expect(controller.state.snapshot.entries[1]?.isRead, isFalse);
      expect(
        controller.state.errorMessage,
        contains('当前网络不可用，已切换为离线阅读模式。待同步 1 个动作'),
      );
    },
  );

  test(
    'refreshes pending sync status before showing sync failure',
    () async {
      final store = await LocalStore.inMemory();
      final repository = _PartialSyncFailureRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        repository.allowRestore();
        controller.dispose();
        await store.close();
      });

      await controller.initialize();

      expect(controller.state.pendingSyncCount, 3);
      expect(controller.state.pendingSyncDescription, '3 个动作待处理');

      repository.allowRestore();
      await Future<void>.delayed(Duration.zero);

      await controller.syncNow();

      expect(repository.syncCalls, 2);
      expect(controller.state.isOnline, isFalse);
      expect(controller.state.pendingSyncCount, 1);
      expect(controller.state.pendingSyncDescription, '1 个动作待处理');
      expect(
        controller.state.errorMessage,
        '当前网络不可用，已切换为离线阅读模式。'
        '待同步 1 个动作（1 个动作待处理）已保留在本机，恢复在线后可重试。',
      );
    },
  );

  test('does not run manual sync while startup restore is in flight', () async {
    final store = await LocalStore.inMemory();
    final repository = _PartialSyncFailureRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      repository.allowRestore();
      controller.dispose();
      await store.close();
    });

    await controller.initialize();

    final manualSync = controller.syncNow();
    await Future<void>.delayed(Duration.zero);

    expect(repository.syncCalls, 0);
    expect(controller.state.pendingSyncCount, 3);

    repository.allowRestore();
    await manualSync;

    expect(repository.syncCalls, 1);
    expect(controller.state.isOnline, isTrue);
  });

  test(
    'queues opening an unread entry when online detail fetch loses network',
    () async {
      final store = await LocalStore.inMemory();
      final repository = _TransientEntryFetchFailureRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });

      await controller.initialize();
      await controller.syncNow();

      expect(controller.state.isOnline, isTrue);

      await controller.openEntry(1);

      expect(repository.fetchEntryDetailCalls, 1);
      expect(repository.queuedReadStates, ['1:true']);
      expect(controller.state.isOnline, isFalse);
      expect(controller.state.pendingSyncCount, 1);
      expect(controller.state.selectedEntryId, 1);
      expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
      expect(controller.state.errorMessage, contains('待同步 1 个动作'));
    },
  );

  test(
    'queues save-for-later continue action when online write loses network',
    () async {
      final store = await LocalStore.inMemory();
      final repository = _TransientSaveForLaterFailureRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });

      await controller.initialize();
      await controller.syncNow();

      expect(controller.state.selectedEntryId, 1);

      await controller.saveSelectedForLaterAndOpenNext();

      expect(repository.setSavedCalls, 1);
      expect(repository.queuedSavedStates, ['1:true']);
      expect(repository.queuedReadStates, ['1:true', '2:true']);
      expect(controller.state.isOnline, isFalse);
      expect(controller.state.pendingSyncCount, 3);
      expect(controller.state.selectedEntryId, 2);
      expect(controller.state.snapshot.entries[1]?.isSaved, isTrue);
      expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
      expect(controller.state.snapshot.entries[2]?.isRead, isTrue);
    },
  );

  test(
    'queues noise-and-continue action when online write loses network',
    () async {
      final store = await LocalStore.inMemory();
      final repository = _TransientMoveToNoiseFailureRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });

      await controller.initialize();
      await controller.syncNow();

      await controller.moveSelectedToNoiseAndOpenNext();

      expect(repository.setEntryNoiseCalls, 1);
      expect(repository.queuedNoiseStates, ['1:true']);
      expect(repository.queuedReadStates, ['2:true']);
      expect(controller.state.isOnline, isFalse);
      expect(controller.state.pendingSyncCount, 2);
      expect(controller.state.selectedEntryId, 2);
      expect(controller.state.snapshot.entries[1]?.isNoise, isTrue);
      expect(controller.state.snapshot.entries[2]?.isRead, isTrue);
    },
  );

  test(
    'queues finish-and-continue action when online write loses network',
    () async {
      final store = await LocalStore.inMemory();
      final repository = _TransientFinishFailureRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });

      await controller.initialize();
      await controller.syncNow();

      await controller.finishSelectedAndOpenNext();

      expect(repository.markReadCalls, 1);
      expect(repository.queuedReadStates, ['1:true', '2:true']);
      expect(controller.state.isOnline, isFalse);
      expect(controller.state.pendingSyncCount, 2);
      expect(controller.state.selectedEntryId, 2);
      expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
      expect(controller.state.snapshot.entries[2]?.isRead, isTrue);
    },
  );

  test('does not lower reading progress after an article is read', () async {
    final store = await LocalStore.inMemory();
    final repository = _OfflineQueueRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await controller.syncNow();

    await controller.openEntry(1);
    controller.updateReadingProgress(1, 0.42);
    await Future<void>.delayed(Duration.zero);

    expect(repository.queuedReadStates, ['1:true']);
    expect(repository.queuedProgress, isEmpty);
    expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
    expect(controller.state.snapshot.entries[1]?.readingProgress, 1);
  });

  test('queues current cached range mark-read while offline', () async {
    final store = await LocalStore.inMemory();
    final repository = _OfflineQueueRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await controller.syncNow();

    await controller.markAllRead();

    expect(repository.queuedReadBatches, [
      [1, 2],
    ]);
    expect(controller.state.pendingSyncCount, 2);
    expect(controller.visibleUnreadCount, 0);
  });

  test('queues cached source mark-read while offline', () async {
    final store = await LocalStore.inMemory();
    final repository = _OfflineQueueRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await controller.syncNow();
    await controller.openSource(1);

    await controller.markAllRead();

    expect(repository.queuedReadBatches, [
      [1, 2],
    ]);
    expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
    expect(controller.state.snapshot.entries[2]?.isRead, isTrue);
  });

  test('queues cached folder mark-read while offline', () async {
    final store = await LocalStore.inMemory();
    final repository = _OfflineQueueRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await controller.syncNow();

    await controller.markFolderRead('Tech');

    expect(repository.queuedReadBatches, [
      [1, 2],
    ]);
    expect(controller.state.pendingSyncCount, 2);
    expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
    expect(controller.state.snapshot.entries[2]?.isRead, isTrue);
  });

  test('persists online reading progress before debounce flush', () async {
    final store = await LocalStore.inMemory();
    final repository = _OnlineProgressRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    controller.updateReadingProgress(1, 0.42);
    await Future<void>.delayed(Duration.zero);

    expect(repository.queuedProgress, ['1:0.42']);
    expect(controller.state.pendingSyncCount, 1);
    expect(controller.state.snapshot.entries[1]?.readingProgress, 0.42);

    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(repository.flushCount, 1);
    expect(controller.state.pendingSyncCount, 0);
  });

  test(
    'marks entry read when online reading progress reaches the end',
    () async {
      final store = await LocalStore.inMemory();
      final repository = _OnlineProgressRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      controller.updateReadingProgress(1, 0.98);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
      expect(controller.state.snapshot.entries[1]?.readingProgress, 1);
      expect(controller.state.snapshot.sources.single.unreadCount, 0);
      expect(repository.queuedProgress, ['1:0.98']);

      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
      expect(controller.state.snapshot.sources.single.unreadCount, 0);
    },
  );

  test('does not throttle reading progress completion threshold', () async {
    final store = await LocalStore.inMemory();
    final repository = _OnlineProgressRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    controller.updateReadingProgress(1, 0.97);
    await Future<void>.delayed(Duration.zero);
    controller.updateReadingProgress(1, 0.98);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.snapshot.entries[1]?.isRead, isTrue);
    expect(controller.state.snapshot.entries[1]?.readingProgress, 1);
    expect(controller.state.snapshot.sources.single.unreadCount, 0);
    expect(repository.queuedProgress, ['1:0.97', '1:0.98']);
  });

  test(
    'keeps online reading progress queued when disposed before debounce',
    () async {
      final store = await LocalStore.inMemory();
      final repository = _OnlineProgressRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(store.close);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      controller.updateReadingProgress(1, 0.42);
      await Future<void>.delayed(Duration.zero);
      controller.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(repository.queuedProgress, ['1:0.42']);
      expect(repository.pendingSyncCount, 1);
      expect(repository.flushCount, 0);
    },
  );

  test('serializes rapid online reading progress persists', () async {
    final store = await LocalStore.inMemory();
    final repository = _DelayedOnlineProgressRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    controller.updateReadingProgress(1, 0.30);
    controller.updateReadingProgress(1, 0.60);
    await Future<void>.delayed(Duration.zero);

    expect(repository.startedProgress, ['1:0.30']);

    repository.completeNextProgress();
    await Future<void>.delayed(Duration.zero);

    expect(repository.startedProgress, ['1:0.30', '1:0.60']);

    repository.completeNextProgress();
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(repository.flushCount, 1);
    expect(repository.latestPersistedProgress, 0.60);
  });
}

class _OfflineQueueRepository extends RssRepository {
  _OfflineQueueRepository(LocalStore store) : super(store: store);

  final List<String> queuedReadStates = <String>[];
  final List<String> queuedSavedStates = <String>[];
  final List<String> queuedNoiseStates = <String>[];
  final List<String> queuedProgress = <String>[];
  final List<List<int>> queuedReadBatches = <List<int>>[];
  int pendingSyncCount = 0;

  AppSnapshot _snapshot = AppSnapshot(
    sources: const [
      FeedSource(
        id: 1,
        name: 'Example',
        folder: 'Tech',
        rssUrl: 'https://example.com/feed.xml',
        siteUrl: null,
        iconUrl: null,
        enabled: true,
        lastFetchedAt: null,
        hasError: false,
        unreadCount: 2,
      ),
    ],
    settings: const SettingsBundle.empty(),
    entries: {
      1: _entry(1, 'First', isRead: false),
      2: _entry(2, 'Second', isRead: false),
    },
    listSnapshots: const {
      'feed': [1, 2],
      'noise': [],
    },
    listHasMore: const {},
    listCursors: const {},
  );

  @override
  Future<SessionData?> loadSession() async => _session;

  @override
  Future<AppSnapshot> loadSnapshot() async => _snapshot;

  @override
  Future<ReaderPreferences> loadReaderPreferences() async {
    return ReaderPreferences.defaultPreferences;
  }

  @override
  Future<void> verifySession() async {}

  @override
  Future<void> sync() async {
    throw const NetworkException('offline');
  }

  @override
  Future<int> pendingEntryActionCount() async {
    return pendingSyncCount;
  }

  @override
  Future<({int count, String description})> pendingEntryActionStatus() async {
    return (count: pendingSyncCount, description: '');
  }

  @override
  Future<void> queueReadState(int entryId, bool isRead) async {
    queuedReadStates.add('$entryId:$isRead');
    pendingSyncCount += 1;
    _updateEntry(
      entryId,
      (entry) => entry.copyWith(
        isRead: isRead,
        readingProgress: isRead ? 1 : entry.readingProgress,
      ),
    );
  }

  @override
  Future<void> queueEntriesRead(List<int> entryIds) async {
    queuedReadBatches.add(entryIds);
    pendingSyncCount += entryIds.length;
    for (final entryId in entryIds) {
      _updateEntry(
        entryId,
        (entry) => entry.copyWith(isRead: true, readingProgress: 1),
      );
    }
  }

  @override
  Future<void> queueSavedState(int entryId, bool isSaved) async {
    queuedSavedStates.add('$entryId:$isSaved');
    pendingSyncCount += 1;
    _updateEntry(entryId, (entry) => entry.copyWith(isSaved: isSaved));
  }

  @override
  Future<void> queueNoiseState(int entryId, bool isNoise) async {
    queuedNoiseStates.add('$entryId:$isNoise');
    pendingSyncCount += 1;
    _updateEntry(entryId, (entry) => entry.copyWith(isNoise: isNoise));
    final feedIds = _snapshot.listIds(ListKey.feed).toList(growable: true)
      ..remove(entryId);
    final noiseIds = _snapshot.listIds(ListKey.noise).toList(growable: true)
      ..remove(entryId);
    if (isNoise) {
      noiseIds.insert(0, entryId);
    } else {
      feedIds.insert(0, entryId);
    }
    _snapshot = _snapshot.copyWith(
      listSnapshots: {
        ..._snapshot.listSnapshots,
        ListKey.feed.value: feedIds,
        ListKey.noise.value: noiseIds,
      },
    );
  }

  @override
  Future<void> queueReadingProgress(int entryId, double progress) async {
    queuedProgress.add('$entryId:${progress.toStringAsFixed(2)}');
    pendingSyncCount += 1;
    _updateEntry(entryId, (entry) => entry.copyWith(readingProgress: progress));
  }

  void _updateEntry(int entryId, EntryRecord Function(EntryRecord) update) {
    final entry = _snapshot.entries[entryId];
    if (entry == null) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      entries: {..._snapshot.entries, entryId: update(entry)},
    );
  }

  static EntryRecord _entry(int id, String title, {required bool isRead}) {
    return EntryRecord(
      id: id,
      sourceId: 1,
      sourceName: 'Example',
      title: title,
      link: 'https://example.com/$id',
      publishedAt: DateTime.utc(2026, 5, 24, 9 - id),
      summary: 'Summary $id',
      isRead: isRead,
      isSaved: false,
      readingProgress: 0,
      foreign: false,
      coverImageUrl: null,
      contentHtml: null,
      filterReason: null,
      translationSegments: const [],
    );
  }
}

class _TransientWriteFailureRepository extends _OfflineQueueRepository {
  _TransientWriteFailureRepository(super.store) {
    _updateEntry(
      1,
      (entry) => entry.copyWith(isRead: true, readingProgress: 1),
    );
  }

  int markUnreadCalls = 0;

  @override
  Future<void> sync() async {}

  @override
  Future<void> markUnread(int entryId) async {
    markUnreadCalls += 1;
    throw const NetworkException('offline');
  }
}

class _PartialSyncFailureRepository extends _OfflineQueueRepository {
  _PartialSyncFailureRepository(super.store) {
    pendingSyncCount = 3;
  }

  final Completer<void> _restoreGate = Completer<void>();
  int syncCalls = 0;

  @override
  Future<void> verifySession() => _restoreGate.future;

  @override
  Future<void> sync() async {
    syncCalls += 1;
    if (syncCalls == 1) {
      return;
    }
    pendingSyncCount = 1;
    throw const NetworkException('offline after partial sync');
  }

  @override
  Future<({int count, String description})> pendingEntryActionStatus() async {
    return (
      count: pendingSyncCount,
      description: '$pendingSyncCount 个动作待处理',
    );
  }

  void allowRestore() {
    if (!_restoreGate.isCompleted) {
      _restoreGate.complete();
    }
  }
}

class _TransientEntryFetchFailureRepository extends _OfflineQueueRepository {
  _TransientEntryFetchFailureRepository(super.store);

  int fetchEntryDetailCalls = 0;

  @override
  Future<void> sync() async {}

  @override
  Future<EntryRecord?> fetchEntryDetail(int entryId, {bool markRead = false}) {
    fetchEntryDetailCalls += 1;
    throw const NetworkException('offline');
  }
}

class _TransientSaveForLaterFailureRepository extends _OfflineQueueRepository {
  _TransientSaveForLaterFailureRepository(super.store);

  int setSavedCalls = 0;

  @override
  Future<void> sync() async {}

  @override
  Future<void> setSaved(int entryId, bool isSaved) {
    setSavedCalls += 1;
    throw const NetworkException('offline');
  }
}

class _TransientMoveToNoiseFailureRepository extends _OfflineQueueRepository {
  _TransientMoveToNoiseFailureRepository(super.store);

  int setEntryNoiseCalls = 0;

  @override
  Future<void> sync() async {}

  @override
  Future<void> setEntryNoise(int entryId, bool isNoise) {
    setEntryNoiseCalls += 1;
    throw const NetworkException('offline');
  }
}

class _TransientFinishFailureRepository extends _OfflineQueueRepository {
  _TransientFinishFailureRepository(super.store);

  int markReadCalls = 0;

  @override
  Future<void> sync() async {}

  @override
  Future<void> markRead(int entryId) {
    markReadCalls += 1;
    throw const NetworkException('offline');
  }
}

class _ExpiredSessionRepository extends RssRepository {
  _ExpiredSessionRepository(LocalStore store) : super(store: store);

  int clearLocalDataCalls = 0;
  SessionData? _sessionData = _session;
  AppSnapshot _snapshot = AppSnapshot(
    sources: const [],
    settings: const SettingsBundle.empty(),
    entries: {1: _entry(1, 'Cached unread', isRead: false)},
    listSnapshots: const {
      'feed': [1],
    },
    listHasMore: const {},
    listCursors: const {},
  );

  @override
  Future<SessionData?> loadSession() async => _sessionData;

  @override
  Future<AppSnapshot> loadSnapshot() async => _snapshot;

  @override
  Future<ReaderPreferences> loadReaderPreferences() async {
    return ReaderPreferences.defaultPreferences;
  }

  @override
  Future<int> pendingEntryActionCount() async {
    return _snapshot.entries.isEmpty ? 0 : 1;
  }

  @override
  Future<({int count, String description})> pendingEntryActionStatus() async {
    return (count: _snapshot.entries.isEmpty ? 0 : 1, description: '');
  }

  @override
  Future<void> verifySession() async {}

  @override
  Future<void> sync() async {
    throw const ApiException(
      statusCode: 401,
      code: 'UNAUTHORIZED',
      message: 'invalid session',
    );
  }

  @override
  Future<void> clearLocalData() async {
    clearLocalDataCalls += 1;
    _sessionData = null;
    _snapshot = const AppSnapshot(
      sources: [],
      settings: SettingsBundle.empty(),
      entries: {},
      listSnapshots: {},
      listHasMore: {},
      listCursors: {},
    );
  }

  static EntryRecord _entry(int id, String title, {required bool isRead}) {
    return EntryRecord(
      id: id,
      sourceId: 1,
      sourceName: 'Example',
      title: title,
      link: 'https://example.com/$id',
      publishedAt: DateTime.utc(2026, 5, 24, 9 - id),
      summary: 'Summary $id',
      isRead: isRead,
      isSaved: false,
      readingProgress: 0,
      foreign: false,
      coverImageUrl: null,
      contentHtml: null,
      filterReason: null,
      translationSegments: const [],
    );
  }
}

class _OnlineProgressRepository extends RssRepository {
  _OnlineProgressRepository(LocalStore store) : super(store: store);

  final List<String> queuedProgress = <String>[];
  int pendingSyncCount = 0;
  int flushCount = 0;

  AppSnapshot _snapshot = AppSnapshot(
    sources: [_source(unreadCount: 1)],
    settings: const SettingsBundle.empty(),
    entries: {1: _entry(1, 'First', isRead: false)},
    listSnapshots: const {
      'feed': [1],
      'noise': [],
    },
    listHasMore: const {},
    listCursors: const {},
  );

  @override
  Future<SessionData?> loadSession() async => _session;

  @override
  Future<AppSnapshot> loadSnapshot() async => _snapshot;

  @override
  Future<ReaderPreferences> loadReaderPreferences() async {
    return ReaderPreferences.defaultPreferences;
  }

  @override
  Future<void> verifySession() async {}

  @override
  Future<void> sync() async {}

  @override
  Future<int> pendingEntryActionCount() async {
    return pendingSyncCount;
  }

  @override
  Future<({int count, String description})> pendingEntryActionStatus() async {
    return (count: pendingSyncCount, description: '');
  }

  @override
  Future<void> queueReadingProgress(int entryId, double progress) async {
    queuedProgress.add('$entryId:${progress.toStringAsFixed(2)}');
    pendingSyncCount = 1;
    final entry = _snapshot.entries[entryId];
    if (entry == null) {
      return;
    }

    final marksRead = progress >= 0.98;
    _snapshot = _snapshot.copyWith(
      entries: {
        ..._snapshot.entries,
        entryId: entry.copyWith(
          isRead: marksRead ? true : entry.isRead,
          readingProgress: marksRead ? 1 : progress,
        ),
      },
      sources: marksRead && !entry.isRead && !entry.isNoise
          ? _snapshot.sources
                .map(
                  (source) => source.id == entry.sourceId
                      ? source.copyWith(
                          unreadCount: source.unreadCount > 0
                              ? source.unreadCount - 1
                              : 0,
                        )
                      : source,
                )
                .toList(growable: false)
          : _snapshot.sources,
    );
  }

  @override
  Future<void> flushPendingEntryActions({
    SessionData? session,
    RssApiClient? client,
  }) async {
    flushCount += 1;
    pendingSyncCount = 0;
  }

  static EntryRecord _entry(int id, String title, {required bool isRead}) {
    return EntryRecord(
      id: id,
      sourceId: 1,
      sourceName: 'Example',
      title: title,
      link: 'https://example.com/$id',
      publishedAt: DateTime.utc(2026, 5, 24, 9 - id),
      summary: 'Summary $id',
      isRead: isRead,
      isSaved: false,
      readingProgress: 0,
      foreign: false,
      coverImageUrl: null,
      contentHtml: null,
      filterReason: null,
      translationSegments: const [],
    );
  }

  static FeedSource _source({required int unreadCount}) {
    return FeedSource(
      id: 1,
      name: 'Example',
      rssUrl: 'https://example.com/feed.xml',
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: unreadCount,
    );
  }
}

class _DelayedOnlineProgressRepository extends _OnlineProgressRepository {
  _DelayedOnlineProgressRepository(super.store);

  final List<String> startedProgress = <String>[];
  final List<Completer<void>> _progressCompleters = <Completer<void>>[];
  double? latestPersistedProgress;

  @override
  Future<void> queueReadingProgress(int entryId, double progress) async {
    startedProgress.add('$entryId:${progress.toStringAsFixed(2)}');
    pendingSyncCount = 1;
    final completer = Completer<void>();
    _progressCompleters.add(completer);
    await completer.future;
    latestPersistedProgress = progress;
    await super.queueReadingProgress(entryId, progress);
  }

  void completeNextProgress() {
    final completer = _progressCompleters.removeAt(0);
    completer.complete();
  }
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
