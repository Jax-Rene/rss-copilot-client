import 'package:rss_copilot_client/src/data/api/api_client.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/auth_user.dart';
import 'package:rss_copilot_client/src/models/entry_detail.dart';
import 'package:rss_copilot_client/src/models/entry_list_item.dart';
import 'package:rss_copilot_client/src/models/entry_page_cursor.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:rss_copilot_client/src/models/translation_segment.dart';
import 'package:rss_copilot_client/src/repositories/rss_repository.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runs the personal reading workflow through repository and cache',
    () async {
      final store = await LocalStore.inMemory();
      final client = _SmokeApiClient();
      final repository = RssRepository(
        store: store,
        loginApiClientFactory: (baseUrl) {
          client.loginBaseUrl = baseUrl;
          return client;
        },
        apiClientFactory: (session) {
          client.sessionBaseUrl = session.baseUrl;
          return client;
        },
        refreshPollDelay: Duration.zero,
        refreshPollAttempts: 1,
      );
      addTearDown(store.close);

      final session = await repository.login(
        baseUrl: ' http://localhost:8080/api/health ',
        email: ' demo@rsscopilot.local ',
        password: 'changeme123',
      );

      expect(client.loginBaseUrl, 'http://localhost:8080');
      expect(session.baseUrl, 'http://localhost:8080');
      expect(session.user.email, 'demo@rsscopilot.local');
      expect((await store.loadSession())?.token, 'demo-token');

      final source = await repository.addSource(
        ' https://example.com/feed.xml ',
        folder: 'Tech',
      );
      expect(source.name, 'Example Feed');

      expect((await repository.refreshAllAndPoll()).acceptedCount, 1);

      var snapshot = await store.loadSnapshot();
      expect(snapshot.sources.map((source) => source.name), ['Example Feed']);
      expect(snapshot.listIds(ListKey.feed), [1]);
      expect(snapshot.listIds(ListKey.noise), [2]);
      expect(snapshot.entries[1]?.title, 'Long Analysis');
      expect(snapshot.entries[2]?.isNoise, isTrue);

      final detail = await repository.fetchEntryDetail(1);
      expect(detail?.contentHtml, contains('First paragraph'));
      expect(detail?.translationSegments.first.translation, '第一段。');

      await repository.setSaved(1, true);
      await repository.updateReadingProgress(1, 0.42);
      snapshot = await store.loadSnapshot();
      expect(snapshot.entries[1]?.isSaved, isTrue);
      expect(snapshot.entries[1]?.readingProgress, 0.42);
      expect(snapshot.listIds(ListKey.saved), [1]);

      await repository.markRead(1);
      snapshot = await store.loadSnapshot();
      expect(snapshot.entries[1]?.isRead, isTrue);
      expect(snapshot.entries[1]?.readingProgress, 1);
      expect(snapshot.sourceById(1)?.unreadCount, 0);

      final opml = await repository.exportOpml();
      expect(opml, contains('Example Feed'));
      expect(opml, contains('https://example.com/feed.xml'));

      final importResult = await repository.importOpml(
        '<opml version="2.0"></opml>',
        refreshAfterImport: false,
      );
      expect(importResult.importedCount, 1);
      expect(importResult.sources.single.name, 'Imported Feed');

      snapshot = await store.loadSnapshot();
      expect(
        snapshot.sources.map((source) => source.name),
        unorderedEquals(['Example Feed', 'Imported Feed']),
      );
      expect(snapshot.entries.length, 2);
      expect(await repository.pendingEntryActionCount(), 0);
      expect(
        client.calls,
        containsAllInOrder([
          'health',
          'login:demo@rsscopilot.local',
          'bootstrap',
          'create-source:https://example.com/feed.xml:Tech',
          'refresh-all',
          'sync-changes',
          'detail:1:false',
          'saved:1',
          'progress:1:0.42',
          'read:1',
          'import-opml:false',
          'bootstrap',
        ]),
      );
    },
  );
}

class _SmokeApiClient extends RssApiClient {
  _SmokeApiClient() : super(baseUrl: 'http://localhost:8080');

  final calls = <String>[];
  final _sources = <int, FeedSource>{};
  final _entries = <int, EntryDetail>{};
  var _nextSourceId = 1;
  var loginBaseUrl = '';
  var sessionBaseUrl = '';
  var _serverTime = DateTime.utc(2026, 5, 30, 0);

  @override
  Future<ServerHealth> health() async {
    calls.add('health');
    return ServerHealth(
      service: ServerHealth.expectedService,
      apiVersion: ServerHealth.minimumApiVersion,
      status: 'UP',
      serverTime: _serverTime,
    );
  }

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    calls.add('login:$email');
    expect(password, 'changeme123');
    return const LoginResponse(
      token: 'demo-token',
      user: AuthUser(
        id: 1,
        email: 'demo@rsscopilot.local',
        displayName: 'RSS Copilot Demo',
      ),
    );
  }

  @override
  Future<FeedSource> createSource(String rssUrl, {String? folder}) async {
    calls.add('create-source:$rssUrl:${folder ?? 'null'}');
    final source = FeedSource(
      id: _nextSourceId++,
      name: 'Example Feed',
      folder: folder ?? defaultSourceFolder,
      rssUrl: rssUrl,
      siteUrl: 'https://example.com',
      iconUrl: 'https://example.com/favicon.ico',
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 0,
    );
    _sources[source.id] = source;
    return source;
  }

  @override
  Future<RefreshAcceptedResult> refreshAllSources() async {
    calls.add('refresh-all');
    final source = _sources.values.first;
    final fetchedAt = DateTime.utc(2026, 5, 30, 1);
    _sources[source.id] = source.copyWith(
      lastFetchedAt: fetchedAt,
      unreadCount: 1,
    );
    _entries[1] = _entry(1, source, title: 'Long Analysis');
    _entries[2] = _entry(2, source, title: 'Quick News', isNoise: true);
    _serverTime = fetchedAt;
    return RefreshAcceptedResult(
      accepted: true,
      acceptedCount: _sources.length,
      requestedCount: _sources.length,
      skippedCount: 0,
    );
  }

  @override
  Future<SyncPayload> syncBootstrap() async {
    calls.add('bootstrap');
    return _syncPayload();
  }

  @override
  Future<SyncPayload> syncChanges(DateTime since) async {
    calls.add('sync-changes');
    return _syncPayload();
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
    calls.add('fetch:${view.wireValue}');
    final entries = _entries.values
        .where((entry) {
          if (sourceId != null && entry.sourceId != sourceId) {
            return false;
          }
          if (unreadOnly && entry.isRead) {
            return false;
          }
          return switch (view) {
            EntryView.feed => !entry.isNoise,
            EntryView.noise => entry.isNoise,
            EntryView.saved => entry.isSaved,
            EntryView.all => true,
          };
        })
        .map(_toListItem)
        .toList(growable: false);
    return EntryPage(items: entries, hasMore: false, nextCursor: null);
  }

  @override
  Future<EntryDetail> fetchEntryDetail(
    int entryId, {
    bool markRead = false,
  }) async {
    calls.add('detail:$entryId:$markRead');
    final entry = _entries[entryId]!;
    if (markRead) {
      _entries[entryId] = _copyEntry(entry, isRead: true, readingProgress: 1);
    }
    return _entries[entryId]!;
  }

  @override
  Future<void> markSaved(int entryId) async {
    calls.add('saved:$entryId');
    _entries[entryId] = _copyEntry(_entries[entryId]!, isSaved: true);
  }

  @override
  Future<void> updateReadingProgress(int entryId, double progress) async {
    calls.add('progress:$entryId:${progress.toStringAsFixed(2)}');
    _entries[entryId] = _copyEntry(
      _entries[entryId]!,
      readingProgress: progress,
    );
  }

  @override
  Future<void> markRead(int entryId) async {
    calls.add('read:$entryId');
    final entry = _entries[entryId]!;
    _entries[entryId] = _copyEntry(entry, isRead: true, readingProgress: 1);
    final source = _sources[entry.sourceId]!;
    _sources[entry.sourceId] = source.copyWith(unreadCount: 0);
  }

  @override
  Future<OpmlImportResult> importOpml(
    String opml, {
    required bool refreshAfterImport,
  }) async {
    calls.add('import-opml:$refreshAfterImport');
    final source = FeedSource(
      id: _nextSourceId++,
      name: 'Imported Feed',
      folder: 'Imported',
      rssUrl: 'https://imported.example/feed.xml',
      siteUrl: 'https://imported.example',
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 0,
    );
    _sources[source.id] = source;
    return OpmlImportResult(
      importedCount: 1,
      skippedCount: 0,
      refreshAcceptedCount: refreshAfterImport ? 1 : 0,
      sources: [source],
    );
  }

  SyncPayload _syncPayload() {
    return SyncPayload(
      serverTime: _serverTime,
      sources: _sources.values.toList(growable: false),
      entries: _entries.values.toList(growable: false),
      deletedSourceIds: const [],
      settings: const SettingsBundle.empty(),
    );
  }

  EntryDetail _entry(
    int id,
    FeedSource source, {
    required String title,
    bool isNoise = false,
  }) {
    return EntryDetail(
      id: id,
      sourceId: source.id,
      sourceName: source.name,
      sourceIconUrl: source.iconUrl,
      author: 'Jane Analyst',
      title: title,
      link: 'https://example.com/articles/$id',
      publishedAt: DateTime.utc(2026, 5, 30, 10 - id),
      summary: '$title summary',
      isRead: false,
      isSaved: false,
      readingProgress: 0,
      isNoise: isNoise,
      foreign: false,
      filterStatus: 'SUCCESS',
      summaryStatus: 'SUCCESS',
      translationStatus: 'SUCCESS',
      coverImageUrl: 'https://example.com/cover.png',
      contentHtml:
          '<article><p>First paragraph.</p><p>Second paragraph.</p></article>',
      filterReason: isNoise ? '内容过短' : '有分析',
      translationSegments: const [
        TranslationSegment(source: 'First paragraph.', translation: '第一段。'),
        TranslationSegment(source: 'Second paragraph.', translation: '第二段。'),
      ],
    );
  }

  EntryDetail _copyEntry(
    EntryDetail entry, {
    bool? isRead,
    bool? isSaved,
    double? readingProgress,
  }) {
    return EntryDetail(
      id: entry.id,
      sourceId: entry.sourceId,
      sourceName: entry.sourceName,
      sourceIconUrl: entry.sourceIconUrl,
      author: entry.author,
      title: entry.title,
      link: entry.link,
      publishedAt: entry.publishedAt,
      summary: entry.summary,
      isRead: isRead ?? entry.isRead,
      isSaved: isSaved ?? entry.isSaved,
      readingProgress: readingProgress ?? entry.readingProgress,
      isNoise: entry.isNoise,
      foreign: entry.foreign,
      filterStatus: entry.filterStatus,
      summaryStatus: entry.summaryStatus,
      translationStatus: entry.translationStatus,
      coverImageUrl: entry.coverImageUrl,
      contentHtml: entry.contentHtml,
      filterReason: entry.filterReason,
      translationSegments: entry.translationSegments,
    );
  }

  EntryListItem _toListItem(EntryDetail entry) {
    return EntryListItem(
      id: entry.id,
      sourceId: entry.sourceId,
      sourceName: entry.sourceName,
      sourceIconUrl: entry.sourceIconUrl,
      author: entry.author,
      title: entry.title,
      link: entry.link,
      publishedAt: entry.publishedAt,
      summary: entry.summary,
      isRead: entry.isRead,
      isSaved: entry.isSaved,
      readingProgress: entry.readingProgress,
      isNoise: entry.isNoise,
      foreign: entry.foreign,
      filterStatus: entry.filterStatus,
      summaryStatus: entry.summaryStatus,
      translationStatus: entry.translationStatus,
      coverImageUrl: entry.coverImageUrl,
    );
  }
}
