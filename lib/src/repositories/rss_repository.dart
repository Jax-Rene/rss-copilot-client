import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../data/api/api_client.dart';
import '../data/api/api_exception.dart';
import '../data/local/local_store.dart';
import '../models/entry_record.dart';
import '../models/feed_source.dart';
import '../models/settings_bundle.dart';
import '../models/session_data.dart';
import '../models/snapshot.dart';

class RssRepository {
  RssRepository({required this.store});

  final LocalStore store;

  Future<SessionData?> loadSession() => store.loadSession();

  Future<AppSnapshot> loadSnapshot() => store.loadSnapshot();

  Future<void> verifySession() async {
    final session = await _requireSession();
    final client = _clientFor(session);
    final user = await client.me();
    await store.saveSession(session.copyWith(user: user));
  }

  Future<void> logout() async {
    final session = await store.loadSession();
    if (session != null) {
      try {
        await _clientFor(session).logout();
      } on ApiException catch (error) {
        if (!error.isUnauthorized) {
          rethrow;
        }
      } on SocketException {
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
    final client = RssApiClient(baseUrl: baseUrl);
    final response = await client.login(
      email: email.trim(),
      password: password,
    );
    final themeOverride = (await store.loadSession())?.themeOverride;
    final session = SessionData(
      baseUrl: baseUrl.trim(),
      token: response.token,
      user: response.user,
      lastServerTime: null,
      themeOverride: themeOverride,
    );
    await store.saveSession(session);
    return bootstrap(session: session);
  }

  Future<SessionData> bootstrap({SessionData? session}) async {
    final currentSession = session ?? await _requireSession();
    final client = _clientFor(currentSession);
    final bootstrap = await client.syncBootstrap();
    await store.saveSettings(bootstrap.settings);
    await store.upsertSources(bootstrap.sources);
    await store.upsertEntryDetails(bootstrap.entries);
    final updatedSession = currentSession.copyWith(
      lastServerTime: bootstrap.serverTime,
    );
    await store.saveSession(updatedSession);
    await refreshGlobalLists(session: updatedSession, client: client);
    await _recalculateUnreadCounts();
    return updatedSession;
  }

  Future<void> sync() async {
    final session = await _requireSession();
    if (session.lastServerTime == null) {
      await bootstrap(session: session);
      return;
    }

    final client = _clientFor(session);
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
    await _recalculateUnreadCounts();
  }

  Future<void> refreshGlobalLists({
    SessionData? session,
    RssApiClient? client,
  }) async {
    final currentSession = session ?? await _requireSession();
    final currentClient = client ?? _clientFor(currentSession);
    final all = await currentClient.fetchEntries(EntryView.all);
    final feed = await currentClient.fetchEntries(EntryView.feed);
    final noise = await currentClient.fetchEntries(EntryView.noise);
    await store.applyListSnapshot(ListKey.all, all);
    await store.applyListSnapshot(ListKey.feed, feed);
    await store.applyListSnapshot(ListKey.noise, noise);
  }

  Future<void> loadSourceEntries(int sourceId) async {
    final session = await _requireSession();
    final items = await _clientFor(session).fetchSourceEntries(sourceId);
    await store.applyListSnapshot(ListKey.source(sourceId), items);
  }

  Future<EntryRecord?> fetchEntryDetail(
    int entryId, {
    bool markRead = false,
  }) async {
    final session = await _requireSession();
    final detail = await _clientFor(
      session,
    ).fetchEntryDetail(entryId, markRead: markRead);
    await store.upsertEntryDetails([detail]);
    if (markRead) {
      await _applyLocalReadState(entryId, true);
    }

    return store.loadEntry(entryId);
  }

  Future<void> markRead(int entryId) async {
    final session = await _requireSession();
    await _clientFor(session).markRead(entryId);
    await _applyLocalReadState(entryId, true);
  }

  Future<void> markUnread(int entryId) async {
    final session = await _requireSession();
    await _clientFor(session).markUnread(entryId);
    await _applyLocalReadState(entryId, false);
  }

  Future<void> markAllRead(EntryView view) async {
    final session = await _requireSession();
    await _clientFor(session).markAllRead(view);

    final snapshot = await store.loadSnapshot();
    final targetKey = switch (view) {
      EntryView.feed => ListKey.feed,
      EntryView.noise => ListKey.noise,
      EntryView.all => ListKey.all,
    };

    for (final entryId in snapshot.listIds(targetKey)) {
      final entry = snapshot.entries[entryId];
      if (entry != null && !entry.isRead) {
        await store.upsertEntryRecord(entry.copyWith(isRead: true));
      }
    }
    await _recalculateUnreadCounts();
  }

  Future<FeedSource> addSource(String rssUrl) async {
    final session = await _requireSession();
    final source = await _clientFor(session).createSource(rssUrl.trim());
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
    await _clientFor(session).deleteSource(sourceId);
    await store.deleteSources([sourceId]);
  }

  Future<void> refreshAllAndPoll() async {
    final session = await _requireSession();
    final client = _clientFor(session);
    await client.refreshAllSources();
    for (var index = 0; index < 3; index += 1) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        await sync();
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      }
    }
  }

  Future<SettingsBundle> updateAiSettings({
    required AiSettings current,
    String? rawApiKey,
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
    );

    final snapshot = await store.loadSnapshot();
    final nextSettings = snapshot.settings.copyWith(ai: nextAi);
    await store.saveSettings(nextSettings);
    return nextSettings;
  }

  Future<void> setThemeOverride(AppThemeMode? mode) async {
    final session = await store.loadSession();
    if (session == null) {
      return;
    }

    await store.saveSession(
      session.copyWith(themeOverride: mode, clearThemeOverride: mode == null),
    );
  }

  Future<void> _applyLocalReadState(int entryId, bool isRead) async {
    final record = await store.loadEntry(entryId);
    if (record == null || record.isRead == isRead) {
      return;
    }

    await store.upsertEntryRecord(record.copyWith(isRead: isRead));
    await _recalculateUnreadCounts();
  }

  Future<void> _recalculateUnreadCounts() async {
    final snapshot = await store.loadSnapshot();
    final feedIds = snapshot.listIds(ListKey.feed);
    final unreadCounter = <int, int>{};
    for (final entryId in feedIds) {
      final entry = snapshot.entries[entryId];
      if (entry == null || entry.isRead) {
        continue;
      }
      unreadCounter.update(
        entry.sourceId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    final updatedSources = snapshot.sources
        .map(
          (source) => source.copyWith(
            unreadCount: max(0, unreadCounter[source.id] ?? 0),
          ),
        )
        .toList(growable: false);
    await store.upsertSources(updatedSources);
  }

  Future<SessionData> _requireSession() async {
    final session = await store.loadSession();
    if (session == null) {
      throw const ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: 'Session not available',
      );
    }

    return session;
  }

  RssApiClient _clientFor(SessionData session) {
    return RssApiClient(baseUrl: session.baseUrl, token: session.token);
  }
}
