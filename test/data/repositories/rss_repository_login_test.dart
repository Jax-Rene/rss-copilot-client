import 'package:rss_copilot_client/src/data/api/api_client.dart';
import 'package:rss_copilot_client/src/data/api/api_exception.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/auth_user.dart';
import 'package:rss_copilot_client/src/models/entry_list_item.dart';
import 'package:rss_copilot_client/src/models/entry_page_cursor.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/pending_entry_action.dart';
import 'package:rss_copilot_client/src/models/session_data.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:rss_copilot_client/src/repositories/rss_repository.dart';
import 'package:test/test.dart';

void main() {
  group('RssRepository login', () {
    test('checks server health before sending credentials', () async {
      final store = await LocalStore.inMemory();
      final loginCalls = <String>[];
      final sessionCalls = <String>[];
      final repository = RssRepository(
        store: store,
        loginApiClientFactory: (baseUrl) =>
            _LoginApiClient(loginCalls, baseUrl: baseUrl),
        apiClientFactory: (_) => _BootstrapApiClient(sessionCalls),
      );
      addTearDown(store.close);

      final session = await repository.login(
        baseUrl: ' https://reader.example ',
        email: ' demo@rsscopilot.local ',
        password: 'changeme123',
      );

      expect(loginCalls, [
        'client:https://reader.example',
        'health',
        'login:demo@rsscopilot.local:changeme123',
      ]);
      expect(sessionCalls, [
        'bootstrap',
        'fetch:all',
        'fetch:feed',
        'fetch:noise',
        'fetch:saved',
      ]);
      expect(session.baseUrl, 'https://reader.example');
      expect(session.user.email, 'demo@rsscopilot.local');
    });

    test('normalizes copied API endpoint URLs before health check', () async {
      final store = await LocalStore.inMemory();
      final loginCalls = <String>[];
      final sessionCalls = <String>[];
      final repository = RssRepository(
        store: store,
        loginApiClientFactory: (baseUrl) =>
            _LoginApiClient(loginCalls, baseUrl: baseUrl),
        apiClientFactory: (_) => _BootstrapApiClient(sessionCalls),
      );
      addTearDown(store.close);

      final session = await repository.login(
        baseUrl: ' https://reader.example/rss/api/health?from=proxy#status ',
        email: 'demo@rsscopilot.local',
        password: 'changeme123',
      );

      expect(loginCalls, [
        'client:https://reader.example/rss',
        'health',
        'login:demo@rsscopilot.local:changeme123',
      ]);
      expect(session.baseUrl, 'https://reader.example/rss');
    });

    test(
      'strips URL credentials before health check and persistence',
      () async {
        final store = await LocalStore.inMemory();
        final loginCalls = <String>[];
        final sessionCalls = <String>[];
        final repository = RssRepository(
          store: store,
          loginApiClientFactory: (baseUrl) =>
              _LoginApiClient(loginCalls, baseUrl: baseUrl),
          apiClientFactory: (_) => _BootstrapApiClient(sessionCalls),
        );
        addTearDown(store.close);

        final session = await repository.login(
          baseUrl: ' https://user:secret@reader.example/rss/api/health ',
          email: 'demo@rsscopilot.local',
          password: 'changeme123',
        );

        expect(loginCalls, [
          'client:https://reader.example/rss',
          'health',
          'login:demo@rsscopilot.local:changeme123',
        ]);
        expect(session.baseUrl, 'https://reader.example/rss');
        expect(
          (await store.loadSession())?.baseUrl,
          'https://reader.example/rss',
        );
      },
    );

    test(
      'normalizes stored session URLs when loading old local data',
      () async {
        final store = await LocalStore.inMemory();
        final repository = RssRepository(store: store);
        addTearDown(store.close);

        await store.saveSession(
          const SessionData(
            baseUrl: 'https://user:secret@reader.example/rss/api/health',
            token: 'old-token',
            user: AuthUser(
              id: 1,
              email: 'demo@rsscopilot.local',
              displayName: 'RSS Copilot Demo',
            ),
            lastServerTime: null,
            themeOverride: null,
          ),
        );

        final session = await repository.loadSession();

        expect(session?.baseUrl, 'https://reader.example/rss');
        expect(
          (await store.loadSession())?.baseUrl,
          'https://reader.example/rss',
        );
      },
    );

    test(
      'uses normalized stored session URLs for authenticated requests',
      () async {
        final store = await LocalStore.inMemory();
        final calls = <String>[];
        final repository = RssRepository(
          store: store,
          apiClientFactory: (session) =>
              _SessionApiClient(calls, baseUrl: session.baseUrl),
        );
        addTearDown(store.close);

        await store.saveSession(
          const SessionData(
            baseUrl: 'https://user:secret@reader.example/rss/api/health',
            token: 'old-token',
            user: AuthUser(
              id: 1,
              email: 'demo@rsscopilot.local',
              displayName: 'RSS Copilot Demo',
            ),
            lastServerTime: null,
            themeOverride: null,
          ),
        );

        await repository.verifySession();

        expect(calls, ['client:https://reader.example/rss', 'me']);
        expect(
          (await store.loadSession())?.baseUrl,
          'https://reader.example/rss',
        );
      },
    );

    test(
      'clears stale cache and offline queue after successful login',
      () async {
        final store = await LocalStore.inMemory();
        final loginCalls = <String>[];
        final sessionCalls = <String>[];
        final repository = RssRepository(
          store: store,
          loginApiClientFactory: (baseUrl) =>
              _LoginApiClient(loginCalls, baseUrl: baseUrl),
          apiClientFactory: (_) => _BootstrapApiClient(sessionCalls),
        );
        addTearDown(store.close);

        await store.saveSession(
          const SessionData(
            baseUrl: 'https://old.example',
            token: 'old-token',
            user: AuthUser(
              id: 99,
              email: 'old@example.com',
              displayName: 'Old User',
            ),
            lastServerTime: null,
            themeOverride: AppThemeMode.dark,
          ),
        );
        await store.upsertSources([
          const FeedSource(
            id: 1,
            name: 'Old Feed',
            rssUrl: 'https://old.example/rss',
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
            sourceName: 'Old Feed',
            title: 'Old cached article',
            link: 'https://old.example/article',
            publishedAt: DateTime.utc(2026, 5, 24, 8),
            summary: null,
            isRead: false,
            foreign: false,
            coverImageUrl: null,
          ),
        ]);
        await store.savePendingEntryAction(
          const PendingEntryAction(
            type: PendingEntryActionType.readState,
            entryId: 1,
            updatedAtMicros: 1,
            boolValue: true,
          ),
        );

        final session = await repository.login(
          baseUrl: 'https://reader.example',
          email: 'demo@rsscopilot.local',
          password: 'changeme123',
        );

        final snapshot = await store.loadSnapshot();
        expect(session.themeOverride, AppThemeMode.dark);
        expect(await store.loadPendingEntryActions(), isEmpty);
        expect(snapshot.sources, isEmpty);
        expect(snapshot.entries, isEmpty);
        expect(snapshot.listIds(ListKey.feed), isEmpty);
        expect((await store.loadSession())?.themeOverride, AppThemeMode.dark);
      },
    );

    test(
      'does not send credentials when server health check is protected',
      () async {
        final store = await LocalStore.inMemory();
        final loginCalls = <String>[];
        final repository = RssRepository(
          store: store,
          loginApiClientFactory: (baseUrl) => _LoginApiClient(
            loginCalls,
            baseUrl: baseUrl,
            healthError: const ApiException(
              statusCode: 401,
              code: 'UNAUTHORIZED',
              message: 'missing bearer token',
            ),
          ),
        );
        addTearDown(store.close);

        await expectLater(
          repository.login(
            baseUrl: 'https://reader.example',
            email: 'demo@rsscopilot.local',
            password: 'changeme123',
          ),
          throwsA(
            isA<ServerHealthException>().having(
              (error) => error.message,
              'message',
              contains('未检测到 RSS Copilot 健康检查接口'),
            ),
          ),
        );

        expect(loginCalls, ['client:https://reader.example', 'health']);
      },
    );

    test('redacts sensitive health check failure details', () async {
      final store = await LocalStore.inMemory();
      final loginCalls = <String>[];
      final repository = RssRepository(
        store: store,
        loginApiClientFactory: (baseUrl) => _LoginApiClient(
          loginCalls,
          baseUrl: baseUrl,
          healthError: const ApiException(
            statusCode: 502,
            code: 'UPSTREAM_ERROR',
            message:
                'proxy failed https://health-user:health-pass@reader.example/api/health Authorization: Bearer sk-healthsecret123456 Cookie: sid=health-cookie token=health-token',
          ),
        ),
      );
      addTearDown(store.close);

      await expectLater(
        repository.login(
          baseUrl: 'https://reader.example',
          email: 'demo@rsscopilot.local',
          password: 'changeme123',
        ),
        throwsA(
          isA<ServerHealthException>()
              .having(
                (error) => error.message,
                'message',
                contains('https://redacted@reader.example/api/health'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('Authorization: Bearer [redacted]'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('Cookie: [redacted]'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('health-pass')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('sk-healthsecret123456')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('health-cookie')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('health-token')),
              ),
        ),
      );

      expect(loginCalls, ['client:https://reader.example', 'health']);
    });

    test('does not send credentials to an unexpected service', () async {
      final store = await LocalStore.inMemory();
      final loginCalls = <String>[];
      final repository = RssRepository(
        store: store,
        loginApiClientFactory: (baseUrl) => _LoginApiClient(
          loginCalls,
          baseUrl: baseUrl,
          healthResponse: ServerHealth(
            service: 'other-service',
            apiVersion: 1,
            status: 'UP',
            serverTime: DateTime.utc(2026, 4, 10),
          ),
        ),
      );
      addTearDown(store.close);

      await expectLater(
        repository.login(
          baseUrl: 'https://reader.example',
          email: 'demo@rsscopilot.local',
          password: 'changeme123',
        ),
        throwsA(
          isA<ServerHealthException>().having(
            (error) => error.message,
            'message',
            contains('未检测到 RSS Copilot 服务'),
          ),
        ),
      );

      expect(loginCalls, ['client:https://reader.example', 'health']);
    });

    test('does not send credentials to an unsupported API version', () async {
      final store = await LocalStore.inMemory();
      final loginCalls = <String>[];
      final repository = RssRepository(
        store: store,
        loginApiClientFactory: (baseUrl) => _LoginApiClient(
          loginCalls,
          baseUrl: baseUrl,
          healthResponse: ServerHealth(
            service: ServerHealth.expectedService,
            apiVersion: 0,
            status: 'UP',
            serverTime: DateTime.utc(2026, 4, 10),
          ),
        ),
      );
      addTearDown(store.close);

      await expectLater(
        repository.login(
          baseUrl: 'https://reader.example',
          email: 'demo@rsscopilot.local',
          password: 'changeme123',
        ),
        throwsA(
          isA<ServerHealthException>().having(
            (error) => error.message,
            'message',
            contains('服务端 API 版本过旧'),
          ),
        ),
      );

      expect(loginCalls, ['client:https://reader.example', 'health']);
    });
  });
}

class _LoginApiClient extends RssApiClient {
  _LoginApiClient(
    this.calls, {
    required String baseUrl,
    this.healthResponse,
    this.healthError,
  }) : super(baseUrl: baseUrl) {
    calls.add('client:$baseUrl');
  }

  final List<String> calls;
  final ServerHealth? healthResponse;
  final Object? healthError;

  @override
  Future<ServerHealth> health() async {
    calls.add('health');
    final error = healthError;
    if (error != null) {
      throw error;
    }
    return healthResponse ??
        ServerHealth(
          service: ServerHealth.expectedService,
          apiVersion: ServerHealth.minimumApiVersion,
          status: 'UP',
          serverTime: DateTime.utc(2026, 4, 10, 9, 12),
        );
  }

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    calls.add('login:$email:$password');
    return LoginResponse(
      token: 'token',
      user: AuthUser(id: 1, email: email, displayName: 'RSS Copilot Demo'),
    );
  }
}

class _BootstrapApiClient extends RssApiClient {
  _BootstrapApiClient(this.calls) : super(baseUrl: 'https://reader.example');

  final List<String> calls;

  @override
  Future<SyncPayload> syncBootstrap() async {
    calls.add('bootstrap');
    return SyncPayload(
      serverTime: DateTime.utc(2026, 5, 25),
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
    calls.add('fetch:${view.wireValue}');
    return const EntryPage(items: [], hasMore: false, nextCursor: null);
  }
}

class _SessionApiClient extends RssApiClient {
  _SessionApiClient(this.calls, {required String baseUrl})
    : super(baseUrl: baseUrl) {
    calls.add('client:$baseUrl');
  }

  final List<String> calls;

  @override
  Future<AuthUser> me() async {
    calls.add('me');
    return const AuthUser(
      id: 1,
      email: 'demo@rsscopilot.local',
      displayName: 'RSS Copilot Demo',
    );
  }
}
