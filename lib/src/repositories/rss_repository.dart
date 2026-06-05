import 'dart:async';
import 'dart:math';

import '../core/diagnostic_redaction.dart';
import '../data/api/api_client.dart';
import '../data/api/api_exception.dart';
import '../data/local/local_store.dart';
import '../models/entry_detail.dart';
import '../models/entry_page_cursor.dart';
import '../models/entry_record.dart';
import '../models/feed_source.dart';
import '../models/pending_entry_action.dart';
import '../models/reader_preferences.dart';
import '../models/settings_bundle.dart';
import '../models/session_data.dart';
import '../models/snapshot.dart';

typedef RssApiClientFactory = RssApiClient Function(SessionData session);
typedef RssLoginApiClientFactory = RssApiClient Function(String baseUrl);

class OpmlImportSyncException implements Exception {
  const OpmlImportSyncException({required this.result, required this.cause});

  final OpmlImportResult result;
  final Object cause;
}

class RssRepository {
  RssRepository({
    required this.store,
    RssApiClientFactory? apiClientFactory,
    RssLoginApiClientFactory? loginApiClientFactory,
    Duration refreshPollDelay = const Duration(seconds: 2),
    int refreshPollAttempts = 3,
  }) : _apiClientFactory =
           apiClientFactory ??
           ((session) =>
               RssApiClient(baseUrl: session.baseUrl, token: session.token)),
       _loginApiClientFactory =
           loginApiClientFactory ??
           ((baseUrl) => RssApiClient(baseUrl: baseUrl)),
       _refreshPollDelay = refreshPollDelay,
       _refreshPollAttempts = max(1, refreshPollAttempts);

  static const int entryPageSize = 60;
  static const int _refreshSourceBatchSize = 100;
  static const int _pendingReadFlushBatchSize = 100;
  static const double _readingCompleteProgress = 0.98;

  final LocalStore store;
  final RssApiClientFactory _apiClientFactory;
  final RssLoginApiClientFactory _loginApiClientFactory;
  final Duration _refreshPollDelay;
  final int _refreshPollAttempts;
  int _lastPendingActionTimestamp = 0;

  Future<SessionData?> loadSession() async {
    final session = await store.loadSession();
    if (session == null) {
      return null;
    }
    return _normalizeStoredSession(session);
  }

  Future<AppSnapshot> loadSnapshot() => store.loadSnapshot();

  Future<ReaderPreferences> loadReaderPreferences() =>
      store.loadReaderPreferences();

  Future<void> saveReaderPreferences(ReaderPreferences preferences) {
    return store.saveReaderPreferences(preferences);
  }

  Future<int> pendingEntryActionCount() async {
    return (await store.loadPendingEntryActions()).length;
  }

  Future<({int count, String description})> pendingEntryActionStatus() async {
    final actions = await store.loadPendingEntryActions();
    return (
      count: actions.length,
      description: _describePendingEntryActions(actions),
    );
  }

  Future<void> verifySession() async {
    final session = await _requireSession();
    final client = _clientFor(session);
    final user = await client.me();
    await store.saveSession(session.copyWith(user: user));
  }

  Future<void> logout() async {
    final session = await loadSession();
    if (session != null) {
      try {
        await _clientFor(session).logout();
      } on ApiException catch (error) {
        if (!error.isUnauthorized) {
          rethrow;
        }
      } on NetworkException {
        // Ignore remote logout failures and clear local state below.
      } on TimeoutException {
        // Ignore remote logout failures and clear local state below.
      }
    }

    await store.clearAll();
  }

  Future<void> clearLocalData() => store.clearAll();

  Future<SessionData> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final normalizedBaseUrl = _normalizeServerBaseUrl(baseUrl);
    final client = _loginApiClientFactory(normalizedBaseUrl);
    await _verifyServerHealth(client);
    final response = await client.login(
      email: email.trim(),
      password: password,
    );
    final themeOverride = (await store.loadSession())?.themeOverride;
    await store.clearAll();
    final session = SessionData(
      baseUrl: normalizedBaseUrl,
      token: response.token,
      user: response.user,
      lastServerTime: null,
      themeOverride: themeOverride,
    );
    await store.saveSession(session);
    return bootstrap(session: session, flushPendingActions: false);
  }

  String _normalizeServerBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority) {
      return trimmed;
    }
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final apiIndex = segments.lastIndexWhere(
      (segment) => segment.toLowerCase() == 'api',
    );
    if (apiIndex < 0) {
      return _serverBaseUri(uri).toString().replaceFirst(RegExp(r'/+$'), '');
    }

    return _serverBaseUri(
      uri,
      pathSegments: segments.take(apiIndex).toList(growable: false),
    ).toString().replaceFirst(RegExp(r'/+$'), '');
  }

  Uri _serverBaseUri(Uri uri, {List<String>? pathSegments}) {
    return Uri(
      scheme: uri.scheme,
      userInfo: '',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: pathSegments ?? uri.pathSegments,
    );
  }

  Future<void> _verifyServerHealth(RssApiClient client) async {
    try {
      final health = await client.health();
      if (!health.isExpectedService) {
        throw const ServerHealthException(
          '未检测到 RSS Copilot 服务，请确认地址没有指向其他网页或代理',
        );
      }
      if (!health.isSupportedApi) {
        throw ServerHealthException(
          '服务端 API 版本过旧，请更新服务端后重试（当前 ${health.apiVersion}，需要 ${ServerHealth.minimumApiVersion}+）',
        );
      }
      if (!health.isUp) {
        throw ServerHealthException('服务端健康状态为 ${health.status}，请稍后重试');
      }
    } on ServerHealthException {
      rethrow;
    } on ApiException catch (error) {
      throw ServerHealthException(_healthApiErrorMessage(error));
    } on TimeoutException {
      throw const ServerHealthException('连接服务端超时，请稍后重试');
    } on NetworkException catch (error) {
      throw ServerHealthException(_healthNetworkErrorMessage(error));
    }
  }

  String _healthApiErrorMessage(ApiException error) {
    if (error.isUnauthorized || error.isNotFound) {
      return '未检测到 RSS Copilot 健康检查接口，请确认服务端已更新并且地址正确';
    }
    return '健康检查失败：${redactDiagnosticText(error.message, emptyPlaceholder: '')}';
  }

  String _healthNetworkErrorMessage(NetworkException error) {
    if (error.message.contains('FormatException')) {
      return '未检测到 RSS Copilot 服务，请确认地址没有指向其他网页或代理';
    }
    return '无法连接服务端，${redactDiagnosticText(error.message, emptyPlaceholder: '')}';
  }

  Future<SessionData> bootstrap({
    SessionData? session,
    bool flushPendingActions = true,
  }) async {
    final currentSession = session ?? await _requireSession();
    final client = _clientFor(currentSession);
    if (flushPendingActions) {
      await flushPendingEntryActions(session: currentSession, client: client);
    }
    final bootstrap = await client.syncBootstrap();
    await store.replaceRemoteSnapshot(
      settings: bootstrap.settings,
      sources: bootstrap.sources,
      entries: bootstrap.entries,
    );
    final updatedSession = currentSession.copyWith(
      lastServerTime: bootstrap.serverTime,
    );
    await store.saveSession(updatedSession);
    await _refreshGlobalListsBestEffort(
      session: updatedSession,
      client: client,
    );
    return updatedSession;
  }

  Future<void> sync() async {
    final session = await _requireSession();
    final client = _clientFor(session);
    await flushPendingEntryActions(session: session, client: client);

    if (session.lastServerTime == null) {
      await bootstrap(session: session, flushPendingActions: false);
      return;
    }

    final changes = await client.syncChanges(session.lastServerTime!);
    await store.upsertSources(changes.sources);
    await store.upsertEntryDetails(changes.entries);
    await store.saveSettings(changes.settings);
    if (changes.deletedSourceIds.isNotEmpty) {
      await store.deleteSources(changes.deletedSourceIds);
    }

    final updatedSession = session.copyWith(lastServerTime: changes.serverTime);
    await store.saveSession(updatedSession);
    await refreshGlobalLists(session: updatedSession, client: client);
  }

  Future<void> refreshGlobalLists({
    SessionData? session,
    RssApiClient? client,
  }) async {
    final currentSession = session ?? await _requireSession();
    final currentClient = client ?? _clientFor(currentSession);
    final pages = await Future.wait<EntryPage>([
      currentClient.fetchEntries(EntryView.all, limit: entryPageSize),
      currentClient.fetchEntries(EntryView.feed, limit: entryPageSize),
      currentClient.fetchEntries(EntryView.noise, limit: entryPageSize),
      currentClient.fetchEntries(EntryView.saved, limit: entryPageSize),
    ]);
    final all = pages[0];
    final feed = pages[1];
    final noise = pages[2];
    final saved = pages[3];
    await store.applyListSnapshot(
      ListKey.all,
      all.items,
      hasMore: all.hasMore,
      nextCursor: all.nextCursor,
    );
    await store.applyListSnapshot(
      ListKey.feed,
      feed.items,
      hasMore: feed.hasMore,
      nextCursor: feed.nextCursor,
    );
    await store.applyListSnapshot(
      ListKey.noise,
      noise.items,
      hasMore: noise.hasMore,
      nextCursor: noise.nextCursor,
    );
    await store.applyListSnapshot(
      ListKey.saved,
      saved.items,
      hasMore: saved.hasMore,
      nextCursor: saved.nextCursor,
    );
  }

  Future<void> _refreshGlobalListsBestEffort({
    required SessionData session,
    required RssApiClient client,
  }) async {
    try {
      await refreshGlobalLists(session: session, client: client);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        rethrow;
      }
    } on NetworkException {
      // Keep the already persisted bootstrap snapshot usable while offline.
    } on TimeoutException {
      // Keep the already persisted bootstrap snapshot usable while offline.
    }
  }

  Future<void> loadSourceEntries(int sourceId) async {
    final session = await _requireSession();
    final EntryPage page;
    try {
      page = await _clientFor(
        session,
      ).fetchSourceEntries(sourceId, limit: entryPageSize);
    } on ApiException catch (error) {
      if (error.isNotFound) {
        await store.deleteSources([sourceId]);
      }
      rethrow;
    }
    await store.applyListSnapshot(
      ListKey.source(sourceId),
      page.items,
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> loadSearchEntries(ListKey key) async {
    final session = await _requireSession();
    final EntryPage? page;
    try {
      page = await _fetchEntriesForListKey(_clientFor(session), key);
    } on ApiException catch (error) {
      await _deleteMissingSourceForListKey(key, error);
      rethrow;
    }
    if (page == null) {
      return;
    }

    await store.applyListSnapshot(
      key,
      page.items,
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> loadMoreEntries(ListKey key) async {
    final session = await _requireSession();
    final snapshot = await store.loadSnapshot();
    if (!snapshot.hasMore(key)) {
      return;
    }

    final cursor = snapshot.cursorFor(key);
    if (cursor == null) {
      await store.clearListPagination(key);
      return;
    }

    final client = _clientFor(session);
    final EntryPage? page;
    try {
      page = await _fetchEntriesForListKey(client, key, before: cursor);
    } on ApiException catch (error) {
      if (_isInvalidPaginationCursor(error)) {
        await store.clearListPagination(key);
      }
      await _deleteMissingSourceForListKey(key, error);
      rethrow;
    }
    if (page == null) {
      return;
    }

    await store.applyListSnapshot(
      key,
      page.items,
      append: true,
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }

  Future<EntryRecord?> fetchEntryDetail(
    int entryId, {
    bool markRead = false,
  }) async {
    final session = await _requireSession();
    final previousRecord = markRead ? await store.loadEntry(entryId) : null;
    final EntryDetail detail;
    try {
      detail = await _clientFor(
        session,
      ).fetchEntryDetail(entryId, markRead: markRead);
    } on ApiException catch (error) {
      await _deleteEntryOnNotFound(entryId, error);
      rethrow;
    }
    await store.upsertEntryDetails([detail]);
    if (markRead) {
      await _applyLocalReadState(entryId, true, previousRecord: previousRecord);
      await _clearPendingReadingProgress([entryId]);
    }

    return store.loadEntry(entryId);
  }

  Future<void> markRead(int entryId) async {
    final session = await _requireSession();
    try {
      await _clientFor(session).markRead(entryId);
    } on ApiException catch (error) {
      await _deleteEntryOnNotFound(entryId, error);
      rethrow;
    }
    await _applyLocalReadState(entryId, true);
    await _clearPendingReadingProgress([entryId]);
  }

  Future<void> markEntriesRead(List<int> entryIds) async {
    final normalizedEntryIds = entryIds
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (normalizedEntryIds.isEmpty) {
      return;
    }

    final session = await _requireSession();
    final client = _clientFor(session);
    final succeededEntryIds = <int>[];
    for (
      var index = 0;
      index < normalizedEntryIds.length;
      index += _pendingReadFlushBatchSize
    ) {
      final chunk = normalizedEntryIds
          .skip(index)
          .take(_pendingReadFlushBatchSize)
          .toList(growable: false);
      succeededEntryIds.addAll(await _markEntriesReadChunk(client, chunk));
    }
    await _markCachedEntryIdsRead(succeededEntryIds.toSet());
    await _clearPendingReadingProgress(succeededEntryIds);
  }

  Future<void> markUnread(int entryId) async {
    final session = await _requireSession();
    try {
      await _clientFor(session).markUnread(entryId);
    } on ApiException catch (error) {
      await _deleteEntryOnNotFound(entryId, error);
      rethrow;
    }
    await _applyLocalReadState(entryId, false);
    await _clearPendingReadingProgress([entryId]);
  }

  Future<void> setSaved(int entryId, bool isSaved) async {
    final session = await _requireSession();
    final client = _clientFor(session);
    try {
      if (isSaved) {
        await client.markSaved(entryId);
      } else {
        await client.markUnsaved(entryId);
      }
    } on ApiException catch (error) {
      await _deleteEntryOnNotFound(entryId, error);
      rethrow;
    }
    await store.setEntrySaved(entryId, isSaved);
  }

  Future<void> updateReadingProgress(int entryId, double progress) async {
    final session = await _requireSession();
    final normalizedProgress = _normalizeReadingProgress(progress);
    if (_isReadingComplete(normalizedProgress)) {
      try {
        await _clientFor(session).markRead(entryId);
      } on ApiException catch (error) {
        await _deleteEntryOnNotFound(entryId, error);
        rethrow;
      }
      await _applyLocalReadState(entryId, true);
      await _clearPendingReadingProgress([entryId]);
      return;
    }
    final entry = await store.loadEntry(entryId);
    if (entry != null && entry.isRead) {
      return;
    }
    try {
      await _clientFor(
        session,
      ).updateReadingProgress(entryId, normalizedProgress);
    } on ApiException catch (error) {
      await _deleteEntryOnNotFound(entryId, error);
      rethrow;
    }
    await store.setReadingProgress(entryId, normalizedProgress);
  }

  Future<void> setEntryNoise(int entryId, bool isNoise) async {
    final session = await _requireSession();
    final client = _clientFor(session);
    try {
      if (isNoise) {
        await client.markNoise(entryId);
      } else {
        await client.markFeed(entryId);
      }
    } on ApiException catch (error) {
      await _deleteEntryOnNotFound(entryId, error);
      rethrow;
    }
    await store.setEntryNoise(entryId, isNoise);
  }

  Future<void> reprocessEntryAi(int entryId) async {
    final session = await _requireSession();
    try {
      await _clientFor(session).reprocessEntryAi(entryId);
    } on ApiException catch (error) {
      await _deleteEntryOnNotFound(entryId, error);
      rethrow;
    }
    await store.setEntryAiProcessingPending(entryId);
  }

  Future<void> saveReadingProgressLocally(int entryId, double progress) async {
    final normalizedProgress = _normalizeReadingProgress(progress);
    if (_isReadingComplete(normalizedProgress)) {
      await _applyLocalReadState(entryId, true);
      return;
    }
    final entry = await store.loadEntry(entryId);
    if (entry != null && entry.isRead) {
      return;
    }
    await store.setReadingProgress(entryId, normalizedProgress);
  }

  Future<void> queueReadState(int entryId, bool isRead) async {
    await _applyLocalReadState(entryId, isRead);
    await _clearPendingReadingProgress([entryId]);
    await _savePendingAction(
      PendingEntryActionType.readState,
      entryId,
      boolValue: isRead,
    );
  }

  Future<void> queueEntriesRead(List<int> entryIds) async {
    final normalizedEntryIds = entryIds
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (normalizedEntryIds.isEmpty) {
      return;
    }

    await _markCachedEntryIdsRead(normalizedEntryIds.toSet());
    await _clearPendingReadingProgress(normalizedEntryIds);
    for (final entryId in normalizedEntryIds) {
      await _savePendingAction(
        PendingEntryActionType.readState,
        entryId,
        boolValue: true,
      );
    }
  }

  Future<void> queueSavedState(int entryId, bool isSaved) async {
    await store.setEntrySaved(entryId, isSaved);
    await _savePendingAction(
      PendingEntryActionType.savedState,
      entryId,
      boolValue: isSaved,
    );
  }

  Future<void> queueNoiseState(int entryId, bool isNoise) async {
    await store.setEntryNoise(entryId, isNoise);
    await _savePendingAction(
      PendingEntryActionType.noiseState,
      entryId,
      boolValue: isNoise,
    );
  }

  Future<void> queueReadingProgress(int entryId, double progress) async {
    final normalizedProgress = _normalizeReadingProgress(progress);
    if (_isReadingComplete(normalizedProgress)) {
      await queueReadState(entryId, true);
      return;
    }
    final entry = await store.loadEntry(entryId);
    if (entry != null && entry.isRead) {
      return;
    }
    await store.setReadingProgress(entryId, normalizedProgress);
    await _savePendingAction(
      PendingEntryActionType.readingProgress,
      entryId,
      doubleValue: normalizedProgress,
    );
  }

  Future<void> _clearPendingReadingProgress(Iterable<int> entryIds) {
    return store.deletePendingEntryActionsFor(
      PendingEntryActionType.readingProgress,
      entryIds,
    );
  }

  Future<void> flushPendingEntryActions({
    SessionData? session,
    RssApiClient? client,
  }) async {
    final actions = await store.loadPendingEntryActions();
    if (actions.isEmpty) {
      return;
    }

    final snapshot = await store.loadSnapshot();
    final staleActions = actions
        .where((action) => !snapshot.entries.containsKey(action.entryId))
        .toList(growable: false);
    if (staleActions.isNotEmpty) {
      await store.deletePendingEntryActions(staleActions);
    }
    final flushableActions = staleActions.isEmpty
        ? actions
        : actions
              .where((action) => snapshot.entries.containsKey(action.entryId))
              .toList(growable: false);
    if (flushableActions.isEmpty) {
      return;
    }

    final currentSession = session ?? await _requireSession();
    final currentClient = client ?? _clientFor(currentSession);
    var index = 0;
    while (index < flushableActions.length) {
      final action = flushableActions[index];
      if (_isBatchableReadAction(action)) {
        final batch = <PendingEntryAction>[action];
        index += 1;
        while (index < flushableActions.length &&
            _isBatchableReadAction(flushableActions[index])) {
          batch.add(flushableActions[index]);
          index += 1;
        }
        await _flushPendingReadBatch(currentClient, batch);
        continue;
      }

      await _flushPendingEntryAction(currentClient, action);
      index += 1;
    }
  }

  Future<void> markAllRead(EntryView view) async {
    final session = await _requireSession();
    await _clientFor(session).markAllRead(view);

    switch (view) {
      case EntryView.feed:
        await _markCachedEntriesRead((entry) => !entry.isNoise);
        await _clearUnreadCounts();
      case EntryView.noise:
        await _markCachedEntriesRead((entry) => entry.isNoise);
      case EntryView.saved:
        await _markCachedEntriesReadWithUnreadDelta((entry) => entry.isSaved);
      case EntryView.all:
        await _markCachedEntriesRead((_) => true);
        await _clearUnreadCounts();
    }
  }

  Future<void> markSourceRead(int sourceId) async {
    final session = await _requireSession();
    try {
      await _clientFor(session).markAllRead(EntryView.all, sourceId: sourceId);
    } on ApiException catch (error) {
      if (error.isNotFound) {
        await store.deleteSources([sourceId]);
      }
      rethrow;
    }
    await _markCachedEntriesRead((entry) => entry.sourceId == sourceId);
    await _clearUnreadCountsWhere((source) => source.id == sourceId);
  }

  Future<void> markFolderRead(String folder) async {
    final folderName = _normalizeFolderName(folder);
    final session = await _requireSession();
    await _clientFor(session).markAllRead(EntryView.all, folder: folderName);
    final snapshot = await store.loadSnapshot();
    final sourceIds = snapshot.sources
        .where((source) => _normalizeFolderName(source.folder) == folderName)
        .map((source) => source.id)
        .toSet();
    await _markCachedEntriesRead((entry) => sourceIds.contains(entry.sourceId));
    await _clearUnreadCountsWhere(
      (source) => _normalizeFolderName(source.folder) == folderName,
    );
  }

  Future<FeedSource> addSource(String rssUrl, {String? folder}) async {
    final session = await _requireSession();
    final source = await _clientFor(
      session,
    ).createSource(rssUrl.trim(), folder: folder);
    await store.upsertSources([source]);
    return source;
  }

  Future<FeedSource> updateSource(FeedSource source) async {
    final session = await _requireSession();
    final updated = await _clientFor(session).updateSource(source);
    await store.upsertSources([updated]);
    return updated;
  }

  Future<void> deleteSource(int sourceId) async {
    final session = await _requireSession();
    try {
      await _clientFor(session).deleteSource(sourceId);
    } on ApiException catch (error) {
      if (!error.isNotFound) {
        rethrow;
      }
    }
    await store.deleteSources([sourceId]);
  }

  Future<RefreshAcceptedResult> refreshAllAndPoll() async {
    final session = await _requireSession();
    final client = _clientFor(session);
    final result = await client.refreshAllSources();
    await _pollSync();
    return result;
  }

  Future<RefreshAcceptedResult> refreshSourceAndPoll(int sourceId) async {
    final session = await _requireSession();
    final client = _clientFor(session);
    final RefreshAcceptedResult result;
    try {
      result = await client.refreshSource(sourceId);
    } on ApiException catch (error) {
      if (error.isNotFound) {
        await store.deleteSources([sourceId]);
      }
      rethrow;
    }
    await _pollSync();
    await loadSourceEntries(sourceId);
    return result;
  }

  Future<RefreshAcceptedResult> refreshSourcesAndPoll(
    Iterable<int> sourceIds,
  ) async {
    final normalizedSourceIds = <int>[];
    final seenSourceIds = <int>{};
    for (final sourceId in sourceIds) {
      if (seenSourceIds.add(sourceId)) {
        normalizedSourceIds.add(sourceId);
      }
    }
    if (normalizedSourceIds.isEmpty) {
      return const RefreshAcceptedResult(
        accepted: true,
        acceptedCount: 0,
        requestedCount: 0,
        skippedCount: 0,
      );
    }

    final session = await _requireSession();
    final client = _clientFor(session);
    final result = await _refreshSourcesInBatches(client, normalizedSourceIds);
    await _pollSync();
    return result;
  }

  Future<RefreshAcceptedResult> _refreshSourcesInBatches(
    RssApiClient client,
    List<int> sourceIds,
  ) async {
    var acceptedCount = 0;
    var requestedCount = 0;
    var skippedCount = 0;
    for (
      var start = 0;
      start < sourceIds.length;
      start += _refreshSourceBatchSize
    ) {
      final end = min(start + _refreshSourceBatchSize, sourceIds.length);
      final result = await client.refreshSources(sourceIds.sublist(start, end));
      acceptedCount += result.acceptedCount;
      requestedCount += result.requestedCount;
      skippedCount += result.skippedCount;
    }
    return RefreshAcceptedResult(
      accepted: true,
      acceptedCount: acceptedCount,
      requestedCount: requestedCount,
      skippedCount: skippedCount,
    );
  }

  Future<String> exportOpml() async {
    final snapshot = await store.loadSnapshot();
    return _renderLocalOpml(snapshot.sources);
  }

  Future<OpmlImportResult> importOpml(
    String opml, {
    required bool refreshAfterImport,
  }) async {
    final session = await _requireSession();
    final client = _clientFor(session);
    await flushPendingEntryActions(session: session, client: client);
    final result = await client.importOpml(
      opml.trim(),
      refreshAfterImport: refreshAfterImport,
    );
    await store.upsertSources(result.sources);
    try {
      await bootstrap(session: session, flushPendingActions: false);
      if (refreshAfterImport) {
        await _pollSync();
      }
    } on ApiException catch (error) {
      throw OpmlImportSyncException(result: result, cause: error);
    } on NetworkException catch (error) {
      throw OpmlImportSyncException(result: result, cause: error);
    } on TimeoutException catch (error) {
      throw OpmlImportSyncException(result: result, cause: error);
    }

    return result;
  }

  Future<SettingsBundle> updateAiSettings({
    required AiSettings current,
    String? rawApiKey,
    bool clearApiKey = false,
  }) async {
    final session = await _requireSession();
    final nextAi = await _clientFor(session).updateAiSettings(
      provider: current.provider,
      filterPrompt: current.filterPrompt,
      summaryPrompt: current.summaryPrompt,
      translationPrompt: current.translationPrompt,
      autoSummaryEnabled: current.autoSummaryEnabled,
      autoTranslationEnabled: current.autoTranslationEnabled,
      outputLanguage: current.outputLanguage,
      apiKey: rawApiKey,
      clearApiKey: clearApiKey,
    );

    final snapshot = await store.loadSnapshot();
    final nextSettings = snapshot.settings.copyWith(ai: nextAi);
    await store.saveSettings(nextSettings);
    return nextSettings;
  }

  Future<SettingsBundle> updateAppearanceSettings(
    AppThemeMode themeMode,
  ) async {
    final session = await _requireSession();
    final nextAppearance = await _clientFor(
      session,
    ).updateAppearanceSettings(themeMode: themeMode);

    final snapshot = await store.loadSnapshot();
    final nextSettings = snapshot.settings.copyWith(appearance: nextAppearance);
    await store.saveSettings(nextSettings);
    return nextSettings;
  }

  Future<SettingsBundle> updateFeedSettings(String defaultLanguage) async {
    final session = await _requireSession();
    final nextFeeds = await _clientFor(
      session,
    ).updateFeedSettings(defaultLanguage: defaultLanguage);

    final snapshot = await store.loadSnapshot();
    final nextSettings = snapshot.settings.copyWith(
      feeds: nextFeeds,
      ai: snapshot.settings.ai.copyWith(
        outputLanguage: nextFeeds.defaultLanguage,
      ),
    );
    await store.saveSettings(nextSettings);
    return nextSettings;
  }

  Future<void> setThemeOverride(AppThemeMode? mode) async {
    final session = await loadSession();
    if (session == null) {
      return;
    }

    await store.saveSession(
      session.copyWith(themeOverride: mode, clearThemeOverride: mode == null),
    );
  }

  Future<void> _applyLocalReadState(
    int entryId,
    bool isRead, {
    EntryRecord? previousRecord,
  }) async {
    final record = previousRecord ?? await store.loadEntry(entryId);
    if (record == null || record.isRead == isRead) {
      return;
    }

    await store.setEntryReadState(entryId, isRead);
    if (record.isNoise) {
      return;
    }

    await _adjustUnreadCount(record.sourceId, isRead ? -1 : 1);
  }

  Future<void> _adjustUnreadCount(int sourceId, int delta) async {
    final snapshot = await store.loadSnapshot();
    final updatedSources = snapshot.sources
        .map(
          (source) => source.id == sourceId
              ? source.copyWith(unreadCount: max(0, source.unreadCount + delta))
              : source,
        )
        .toList(growable: false);
    await store.upsertSources(updatedSources);
  }

  Future<void> _clearUnreadCounts() async {
    await _clearUnreadCountsWhere((_) => true);
  }

  Future<void> _clearUnreadCountsWhere(
    bool Function(FeedSource) matches,
  ) async {
    final snapshot = await store.loadSnapshot();
    final updatedSources = snapshot.sources
        .map(
          (source) =>
              matches(source) ? source.copyWith(unreadCount: 0) : source,
        )
        .toList(growable: false);
    await store.upsertSources(updatedSources);
  }

  Future<void> _markCachedEntriesRead(
    bool Function(EntryRecord) matches,
  ) async {
    final snapshot = await store.loadSnapshot();
    final matchedEntryIds = <int>[];
    for (final entry in snapshot.entries.values) {
      if (!matches(entry)) {
        continue;
      }
      matchedEntryIds.add(entry.id);
      if (!entry.isRead) {
        await store.setEntryReadState(entry.id, true);
      }
    }
    await _clearPendingReadingProgress(matchedEntryIds);
  }

  Future<void> _markCachedEntriesReadWithUnreadDelta(
    bool Function(EntryRecord) matches,
  ) async {
    final snapshot = await store.loadSnapshot();
    final unreadDeltasBySource = <int, int>{};
    final matchedEntryIds = <int>[];
    for (final entry in snapshot.entries.values) {
      if (!matches(entry)) {
        continue;
      }
      matchedEntryIds.add(entry.id);
      if (entry.isRead) {
        continue;
      }

      if (!entry.isNoise) {
        unreadDeltasBySource[entry.sourceId] =
            (unreadDeltasBySource[entry.sourceId] ?? 0) - 1;
      }
      await store.setEntryReadState(entry.id, true);
    }
    await _clearPendingReadingProgress(matchedEntryIds);

    if (unreadDeltasBySource.isEmpty) {
      return;
    }

    final latestSnapshot = await store.loadSnapshot();
    final updatedSources = latestSnapshot.sources
        .map((source) {
          final delta = unreadDeltasBySource[source.id];
          if (delta == null) {
            return source;
          }
          return source.copyWith(
            unreadCount: max(0, source.unreadCount + delta),
          );
        })
        .toList(growable: false);
    await store.upsertSources(updatedSources);
  }

  Future<void> _markCachedEntryIdsRead(Set<int> entryIds) async {
    if (entryIds.isEmpty) {
      return;
    }

    final snapshot = await store.loadSnapshot();
    final unreadDeltasBySource = <int, int>{};
    final readEntryIds = <int>[];
    for (final entryId in entryIds) {
      final entry = snapshot.entries[entryId];
      if (entry == null || entry.isRead) {
        continue;
      }

      if (!entry.isNoise) {
        unreadDeltasBySource[entry.sourceId] =
            (unreadDeltasBySource[entry.sourceId] ?? 0) - 1;
      }
      await store.setEntryReadState(entryId, true);
      readEntryIds.add(entryId);
    }
    await _clearPendingReadingProgress(readEntryIds);

    if (unreadDeltasBySource.isEmpty) {
      return;
    }

    final latestSnapshot = await store.loadSnapshot();
    final updatedSources = latestSnapshot.sources
        .map((source) {
          final delta = unreadDeltasBySource[source.id];
          if (delta == null) {
            return source;
          }
          return source.copyWith(
            unreadCount: max(0, source.unreadCount + delta),
          );
        })
        .toList(growable: false);
    await store.upsertSources(updatedSources);
  }

  Future<void> _savePendingAction(
    PendingEntryActionType type,
    int entryId, {
    bool? boolValue,
    double? doubleValue,
  }) {
    return store.savePendingEntryAction(
      PendingEntryAction(
        type: type,
        entryId: entryId,
        updatedAtMicros: _nextPendingActionTimestamp(),
        boolValue: boolValue,
        doubleValue: doubleValue,
      ),
    );
  }

  String _describePendingEntryActions(List<PendingEntryAction> actions) {
    if (actions.isEmpty) {
      return '';
    }
    final counts = <String, int>{};
    for (final action in actions) {
      final label = switch (action.type) {
        PendingEntryActionType.readState =>
          action.boolValue == true
              ? '标记已读'
              : action.boolValue == false
              ? '标记未读'
              : '阅读状态',
        PendingEntryActionType.savedState =>
          action.boolValue == true
              ? '加入稍后读'
              : action.boolValue == false
              ? '取消稍后读'
              : '稍后读状态',
        PendingEntryActionType.noiseState =>
          action.boolValue == true
              ? '移入噪音箱'
              : action.boolValue == false
              ? '恢复到 Feed'
              : '噪音箱状态',
        PendingEntryActionType.readingProgress => '阅读进度',
      };
      counts[label] = (counts[label] ?? 0) + 1;
    }
    const labelOrder = <String>[
      '标记已读',
      '标记未读',
      '加入稍后读',
      '取消稍后读',
      '移入噪音箱',
      '恢复到 Feed',
      '阅读进度',
      '阅读状态',
      '稍后读状态',
      '噪音箱状态',
    ];
    return labelOrder
        .where(counts.containsKey)
        .map((label) => '$label ${counts[label]}')
        .join('、');
  }

  int _nextPendingActionTimestamp() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now <= _lastPendingActionTimestamp) {
      _lastPendingActionTimestamp += 1;
    } else {
      _lastPendingActionTimestamp = now;
    }
    return _lastPendingActionTimestamp;
  }

  Future<void> _sendPendingEntryAction(
    RssApiClient client,
    PendingEntryAction action,
  ) {
    return switch (action.type) {
      PendingEntryActionType.readState =>
        (action.boolValue ?? false)
            ? client.markRead(action.entryId)
            : client.markUnread(action.entryId),
      PendingEntryActionType.savedState =>
        (action.boolValue ?? false)
            ? client.markSaved(action.entryId)
            : client.markUnsaved(action.entryId),
      PendingEntryActionType.noiseState =>
        (action.boolValue ?? false)
            ? client.markNoise(action.entryId)
            : client.markFeed(action.entryId),
      PendingEntryActionType.readingProgress => client.updateReadingProgress(
        action.entryId,
        _normalizeReadingProgress(action.doubleValue ?? 0),
      ),
    };
  }

  bool _isBatchableReadAction(PendingEntryAction action) {
    return action.type == PendingEntryActionType.readState &&
        (action.boolValue ?? false);
  }

  Future<void> _flushPendingReadBatch(
    RssApiClient client,
    List<PendingEntryAction> actions,
  ) async {
    if (actions.length == 1) {
      await _flushPendingEntryAction(client, actions.single);
      return;
    }

    for (
      var index = 0;
      index < actions.length;
      index += _pendingReadFlushBatchSize
    ) {
      final chunk = actions
          .skip(index)
          .take(_pendingReadFlushBatchSize)
          .toList(growable: false);
      if (chunk.length == 1) {
        await _flushPendingEntryAction(client, chunk.single);
        continue;
      }

      try {
        await client.markEntriesRead(
          chunk.map((action) => action.entryId).toList(growable: false),
        );
        await store.deletePendingEntryActions(chunk);
      } on ApiException catch (error) {
        if (!error.isNotFound) {
          rethrow;
        }
        for (final action in chunk) {
          await _flushPendingEntryAction(client, action);
        }
      }
    }
  }

  Future<List<int>> _markEntriesReadChunk(
    RssApiClient client,
    List<int> entryIds,
  ) async {
    try {
      await client.markEntriesRead(entryIds);
      return entryIds;
    } on ApiException catch (error) {
      if (!error.isNotFound) {
        rethrow;
      }
    }

    final succeededEntryIds = <int>[];
    for (final entryId in entryIds) {
      try {
        await client.markRead(entryId);
        succeededEntryIds.add(entryId);
      } on ApiException catch (error) {
        await _deleteEntryOnNotFound(entryId, error);
        if (!error.isNotFound) {
          rethrow;
        }
      }
    }
    return succeededEntryIds;
  }

  Future<void> _flushPendingEntryAction(
    RssApiClient client,
    PendingEntryAction action,
  ) async {
    try {
      await _sendPendingEntryAction(client, action);
    } on ApiException catch (error) {
      if (!error.isNotFound) {
        rethrow;
      }
      await store.deleteEntries([action.entryId]);
    }
    await store.deletePendingEntryActions([action]);
  }

  String _normalizeFolderName(String folder) {
    final folderName = folder.trim();
    return folderName.isEmpty ? defaultSourceFolder : folderName;
  }

  String _renderLocalOpml(List<FeedSource> sources) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<opml version="2.0">')
      ..writeln('  <head>')
      ..writeln('    <title>RSS Copilot subscriptions</title>')
      ..writeln('  </head>')
      ..writeln('  <body>');

    final rootFolder = _OpmlFolderNode(null);
    for (final source in sources) {
      var folder = rootFolder;
      for (final segment in _opmlFolderPath(source.folder)) {
        folder = folder.children.putIfAbsent(
          segment,
          () => _OpmlFolderNode(segment),
        );
      }
      folder.sources.add(source);
    }

    _writeOpmlFolderContents(buffer, rootFolder, indent: 4);

    buffer
      ..writeln('  </body>')
      ..writeln('</opml>');
    return buffer.toString();
  }

  List<String> _opmlFolderPath(String folder) {
    final normalizedFolder = _normalizeFolderName(folder);
    if (normalizedFolder == defaultSourceFolder) {
      return const <String>[];
    }
    return normalizedFolder
        .split(' / ')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  void _writeOpmlFolderContents(
    StringBuffer buffer,
    _OpmlFolderNode folder, {
    required int indent,
  }) {
    final sortedSources = folder.sources.toList(growable: false)
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    for (final source in sortedSources) {
      _writeOpmlSource(buffer, source, indent: indent);
    }

    final childNames = folder.children.keys.toList(
      growable: false,
    )..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
    for (final childName in childNames) {
      final child = folder.children[childName]!;
      final spaces = ' ' * indent;
      final title = _escapeXmlAttribute(child.name!);
      buffer.writeln('$spaces<outline text="$title" title="$title">');
      _writeOpmlFolderContents(buffer, child, indent: indent + 2);
      buffer.writeln('$spaces</outline>');
    }
  }

  void _writeOpmlSource(
    StringBuffer buffer,
    FeedSource source, {
    required int indent,
  }) {
    final spaces = ' ' * indent;
    final title = _escapeXmlAttribute(source.name);
    final xmlUrl = _escapeXmlAttribute(source.rssUrl);
    final htmlUrl = source.siteUrl?.trim();
    final htmlUrlAttribute = htmlUrl == null || htmlUrl.isEmpty
        ? ''
        : ' htmlUrl="${_escapeXmlAttribute(htmlUrl)}"';
    final category = _opmlCategory(source.folder);
    final categoryAttribute = category == null
        ? ''
        : ' category="${_escapeXmlAttribute(category)}"';
    buffer.writeln(
      '$spaces<outline text="$title" title="$title" type="rss" xmlUrl="$xmlUrl"$categoryAttribute$htmlUrlAttribute />',
    );
  }

  String? _opmlCategory(String folder) {
    final path = _opmlFolderPath(folder);
    if (path.isEmpty) {
      return null;
    }
    return '/${path.join('/')}';
  }

  String _escapeXmlAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  double _normalizeReadingProgress(double progress) {
    if (progress.isNaN || progress.isInfinite) {
      return 0;
    }
    return progress.clamp(0, 1).toDouble();
  }

  bool _isReadingComplete(double progress) {
    return progress >= _readingCompleteProgress;
  }

  bool _isInvalidPaginationCursor(ApiException error) {
    return error.isBadRequest && error.message == 'invalid pagination cursor';
  }

  Future<void> _deleteEntryOnNotFound(int entryId, ApiException error) async {
    if (error.isNotFound) {
      await store.deleteEntries([entryId]);
    }
  }

  Future<void> _deleteMissingSourceForListKey(
    ListKey key,
    ApiException error,
  ) async {
    if (!error.isNotFound) {
      return;
    }
    final sourceId = _sourceIdForListKey(key);
    if (sourceId != null) {
      await store.deleteSources([sourceId]);
    }
  }

  Future<SessionData> _requireSession() async {
    final session = await loadSession();
    if (session == null) {
      throw const ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: 'Session not available',
      );
    }

    return session;
  }

  Future<SessionData> _normalizeStoredSession(SessionData session) async {
    final normalizedBaseUrl = _normalizeServerBaseUrl(session.baseUrl);
    if (normalizedBaseUrl == session.baseUrl) {
      return session;
    }

    final normalizedSession = session.copyWith(baseUrl: normalizedBaseUrl);
    await store.saveSession(normalizedSession);
    return normalizedSession;
  }

  RssApiClient _clientFor(SessionData session) {
    return _apiClientFactory(session);
  }

  Future<EntryPage?> _fetchEntriesForListKey(
    RssApiClient client,
    ListKey key, {
    EntryPageCursor? before,
  }) async {
    final searchQuery = key.searchQuery;
    final searchUnreadSourceView = key.searchUnreadSourceViewValue;
    if (searchUnreadSourceView != null) {
      final view = _entryViewForWireValue(searchUnreadSourceView);
      final sourceId = key.searchUnreadSourceViewSourceId;
      if (view == null || sourceId == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        unreadOnly: true,
        limit: entryPageSize,
        before: before,
        sourceId: sourceId,
        searchQuery: searchQuery,
      );
    }

    final searchUnreadFolderView = key.searchUnreadFolderViewValue;
    if (searchUnreadFolderView != null) {
      final view = _entryViewForWireValue(searchUnreadFolderView);
      final folder = key.searchUnreadFolderName;
      if (view == null || folder == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        unreadOnly: true,
        limit: entryPageSize,
        before: before,
        folder: folder,
        searchQuery: searchQuery,
      );
    }

    final searchUnreadView = key.searchUnreadViewValue;
    if (searchUnreadView != null) {
      final view = _entryViewForWireValue(searchUnreadView);
      if (view == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        unreadOnly: true,
        limit: entryPageSize,
        before: before,
        searchQuery: searchQuery,
      );
    }

    final searchSourceView = key.searchSourceViewValue;
    if (searchSourceView != null) {
      final view = _entryViewForWireValue(searchSourceView);
      final sourceId = key.searchSourceViewSourceId;
      if (view == null || sourceId == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        limit: entryPageSize,
        before: before,
        sourceId: sourceId,
        searchQuery: searchQuery,
      );
    }

    final searchFolderView = key.searchFolderViewValue;
    if (searchFolderView != null) {
      final view = _entryViewForWireValue(searchFolderView);
      final folder = key.searchFolderName;
      if (view == null || folder == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        limit: entryPageSize,
        before: before,
        folder: folder,
        searchQuery: searchQuery,
      );
    }

    final searchSourceId = key.searchSourceId;
    if (searchSourceId != null) {
      return client.fetchSourceEntries(
        searchSourceId,
        limit: entryPageSize,
        before: before,
        searchQuery: searchQuery,
      );
    }

    final searchView = key.searchViewValue;
    if (searchView != null) {
      final view = _entryViewForWireValue(searchView);
      if (view == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        limit: entryPageSize,
        before: before,
        searchQuery: searchQuery,
      );
    }

    final unreadSourceView = key.unreadSourceViewValue;
    if (unreadSourceView != null) {
      final view = _entryViewForWireValue(unreadSourceView);
      final sourceId = key.unreadSourceViewSourceId;
      if (view == null || sourceId == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        unreadOnly: true,
        limit: entryPageSize,
        before: before,
        sourceId: sourceId,
      );
    }

    final unreadFolderView = key.unreadFolderViewValue;
    if (unreadFolderView != null) {
      final view = _entryViewForWireValue(unreadFolderView);
      final folder = key.unreadFolderName;
      if (view == null || folder == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        unreadOnly: true,
        limit: entryPageSize,
        before: before,
        folder: folder,
      );
    }

    final unreadView = key.unreadViewValue;
    if (unreadView != null) {
      final view = _entryViewForWireValue(unreadView);
      if (view == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        unreadOnly: true,
        limit: entryPageSize,
        before: before,
      );
    }

    final sourceView = key.sourceViewValue;
    if (sourceView != null) {
      final view = _entryViewForWireValue(sourceView);
      final sourceId = key.sourceViewSourceId;
      if (view == null || sourceId == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        limit: entryPageSize,
        before: before,
        sourceId: sourceId,
      );
    }

    final folderView = key.folderViewValue;
    if (folderView != null) {
      final view = _entryViewForWireValue(folderView);
      final folder = key.folderName;
      if (view == null || folder == null) {
        return null;
      }
      return client.fetchEntries(
        view,
        limit: entryPageSize,
        before: before,
        folder: folder,
      );
    }

    if (key == ListKey.feed) {
      return client.fetchEntries(
        EntryView.feed,
        limit: entryPageSize,
        before: before,
      );
    }
    if (key == ListKey.noise) {
      return client.fetchEntries(
        EntryView.noise,
        limit: entryPageSize,
        before: before,
      );
    }
    if (key == ListKey.saved) {
      return client.fetchEntries(
        EntryView.saved,
        limit: entryPageSize,
        before: before,
      );
    }
    if (key == ListKey.all) {
      return client.fetchEntries(
        EntryView.all,
        limit: entryPageSize,
        before: before,
      );
    }

    final sourceId = _sourceIdForListKey(key);
    if (sourceId == null) {
      return null;
    }
    return client.fetchSourceEntries(
      sourceId,
      limit: entryPageSize,
      before: before,
    );
  }

  EntryView? _entryViewForWireValue(String value) {
    for (final view in EntryView.values) {
      if (view.wireValue == value) {
        return view;
      }
    }
    return null;
  }

  Future<void> _pollSync() async {
    Object? lastTransientError;
    StackTrace? lastTransientStackTrace;
    for (var index = 0; index < _refreshPollAttempts; index += 1) {
      if (_refreshPollDelay > Duration.zero) {
        await Future<void>.delayed(_refreshPollDelay);
      }
      try {
        await sync();
        return;
      } on TimeoutException catch (error, stackTrace) {
        lastTransientError = error;
        lastTransientStackTrace = stackTrace;
        continue;
      } on NetworkException catch (error, stackTrace) {
        lastTransientError = error;
        lastTransientStackTrace = stackTrace;
        continue;
      }
    }
    if (lastTransientError != null) {
      Error.throwWithStackTrace(lastTransientError, lastTransientStackTrace!);
    }
  }

  int? _sourceIdForListKey(ListKey key) {
    final searchSourceId = key.searchSourceId;
    if (searchSourceId != null) {
      return searchSourceId;
    }
    final searchSourceViewSourceId = key.searchSourceViewSourceId;
    if (searchSourceViewSourceId != null) {
      return searchSourceViewSourceId;
    }
    final searchUnreadSourceViewSourceId = key.searchUnreadSourceViewSourceId;
    if (searchUnreadSourceViewSourceId != null) {
      return searchUnreadSourceViewSourceId;
    }
    final sourceViewSourceId = key.sourceViewSourceId;
    if (sourceViewSourceId != null) {
      return sourceViewSourceId;
    }
    final unreadSourceViewSourceId = key.unreadSourceViewSourceId;
    if (unreadSourceViewSourceId != null) {
      return unreadSourceViewSourceId;
    }
    if (!key.value.startsWith('source:')) {
      return null;
    }
    return int.tryParse(key.value.substring('source:'.length));
  }
}

class _OpmlFolderNode {
  _OpmlFolderNode(this.name);

  final String? name;
  final Map<String, _OpmlFolderNode> children = <String, _OpmlFolderNode>{};
  final List<FeedSource> sources = <FeedSource>[];
}
