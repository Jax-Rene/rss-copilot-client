import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rss_copilot_client/src/data/api/api_client.dart';
import 'package:rss_copilot_client/src/data/api/api_exception.dart';
import 'package:rss_copilot_client/src/models/entry_page_cursor.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:test/test.dart';

void main() {
  group('RssApiClient health', () {
    test('checks server health without bearer token', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/health');
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response(
            jsonEncode({
              'service': 'rss-copilot-server',
              'apiVersion': 1,
              'status': 'UP',
              'serverTime': '2026-04-10T09:12:33.123Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final health = await client.health();

      expect(health.service, 'rss-copilot-server');
      expect(health.apiVersion, 1);
      expect(health.status, 'UP');
      expect(health.isUp, isTrue);
      expect(health.isExpectedService, isTrue);
      expect(health.isSupportedApi, isTrue);
      expect(health.serverTime, DateTime.utc(2026, 4, 10, 9, 12, 33, 123));
    });

    test('strips URL credentials from base URL before requests', () async {
      final client = RssApiClient(
        baseUrl: ' https://user:secret@reader.example/rss/?debug=true#login ',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), 'https://reader.example/rss/api/health');
          expect(request.url.userInfo, isEmpty);
          return http.Response(
            jsonEncode({
              'service': 'rss-copilot-server',
              'apiVersion': 1,
              'status': 'UP',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final health = await client.health();

      expect(client.baseUrl, 'https://reader.example/rss');
      expect(health.isExpectedService, isTrue);
    });

    test('normalizes copied health endpoint URLs before requests', () async {
      final client = RssApiClient(
        baseUrl: ' https://reader.example/rss/api/health?from=proxy#status ',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), 'https://reader.example/rss/api/health');
          return http.Response(
            jsonEncode({
              'service': 'rss-copilot-server',
              'apiVersion': 1,
              'status': 'UP',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final health = await client.health();

      expect(client.baseUrl, 'https://reader.example/rss');
      expect(health.isSupportedApi, isTrue);
    });
  });

  group('RssApiClient OPML', () {
    test('exports OPML as raw XML text', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/feed-sources/opml');
          expect(request.headers['accept'], 'application/xml');
          return http.Response(
            '<?xml version="1.0"?><opml version="2.0" />',
            200,
            headers: {'content-type': 'application/xml'},
          );
        }),
      );

      final opml = await client.exportOpml();

      expect(opml, contains('<opml version="2.0"'));
    });

    test('imports OPML and parses migration summary', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/feed-sources/opml/import');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['opml'], '<opml />');
          expect(payload['refreshAfterImport'], isTrue);
          return http.Response(
            jsonEncode({
              'importedCount': 1,
              'skippedCount': 2,
              'refreshAcceptedCount': 1,
              'sources': [
                {
                  'id': 8,
                  'name': 'Example',
                  'folder': 'Tech',
                  'rssUrl': 'https://example.com/feed.xml',
                  'siteUrl': null,
                  'iconUrl': null,
                  'enabled': true,
                  'lastFetchedAt': null,
                  'hasError': false,
                  'unreadCount': 0,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.importOpml(
        '<opml />',
        refreshAfterImport: true,
      );

      expect(result.importedCount, 1);
      expect(result.skippedCount, 2);
      expect(result.refreshAcceptedCount, 1);
      expect(result.sources.single.name, 'Example');
      expect(result.sources.single.folder, 'Tech');
    });

    test('preserves OPML payload too large errors', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/feed-sources/opml/import');
          return http.Response(
            jsonEncode({
              'code': 'PAYLOAD_TOO_LARGE',
              'message': 'opml document is too large',
              'timestamp': '2026-04-10T09:12:33.123Z',
            }),
            413,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        client.importOpml('<opml />', refreshAfterImport: false),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 413)
              .having((error) => error.code, 'code', 'PAYLOAD_TOO_LARGE')
              .having(
                (error) => error.message,
                'message',
                'opml document is too large',
              )
              .having(
                (error) => error.isPayloadTooLarge,
                'isPayloadTooLarge',
                isTrue,
              ),
        ),
      );
    });

    test('updates source folder with editable source fields', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/feed-sources/8');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['folder'], 'Tech');
          expect(payload.containsKey('iconUrl'), isTrue);
          expect(payload['iconUrl'], isNull);
          return http.Response(
            jsonEncode({
              'id': 8,
              'name': 'Example',
              'folder': 'Tech',
              'rssUrl': 'https://example.com/feed.xml',
              'siteUrl': null,
              'iconUrl': null,
              'enabled': true,
              'lastFetchedAt': null,
              'hasError': false,
              'lastErrorAt': '2026-04-10T11:00:00Z',
              'lastErrorMessage': 'previous timeout',
              'unreadCount': 0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final source = await client.updateSource(
        FeedSource(
          id: 8,
          name: 'Example',
          folder: 'Tech',
          rssUrl: 'https://example.com/feed.xml',
          siteUrl: null,
          iconUrl: null,
          enabled: true,
          lastFetchedAt: null,
          hasError: false,
          unreadCount: 0,
        ),
      );

      expect(source.folder, 'Tech');
      expect(source.lastErrorAt, DateTime.utc(2026, 4, 10, 11));
      expect(source.lastErrorMessage, 'previous timeout');
    });

    test('creates a source inside a folder', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/feed-sources');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['folder'], 'Tech');
          return http.Response(
            jsonEncode({
              'id': 9,
              'name': 'New Source',
              'folder': 'Tech',
              'rssUrl': 'https://example.com/new.xml',
              'siteUrl': null,
              'iconUrl': null,
              'enabled': true,
              'lastFetchedAt': null,
              'hasError': false,
              'unreadCount': 0,
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final source = await client.createSource(
        'https://example.com/new.xml',
        folder: 'Tech',
      );

      expect(source.folder, 'Tech');
    });

    test('keeps HTTP status for non JSON object endpoint errors', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/feed-sources');
          return http.Response(
            '<html><body>Bad Gateway</body></html>',
            502,
            headers: {'content-type': 'text/html'},
          );
        }),
      );

      await expectLater(
        client.createSource('https://example.com/feed.xml'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 502)
              .having((error) => error.code, 'code', 'UNKNOWN')
              .having((error) => error.message, 'message', 'Request failed'),
        ),
      );
    });

    test('preserves server bad request messages for endpoint errors', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/feed-sources');
          return http.Response(
            jsonEncode({
              'code': 'BAD_REQUEST',
              'message': 'request body is invalid',
              'timestamp': '2026-04-10T09:12:33.123Z',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        client.createSource('https://example.com/feed.xml'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.code, 'code', 'BAD_REQUEST')
              .having(
                (error) => error.message,
                'message',
                'request body is invalid',
              )
              .having((error) => error.isBadRequest, 'isBadRequest', isTrue),
        ),
      );
    });

    test('keeps HTTP status for non JSON list endpoint errors', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/feed-sources');
          return http.Response(
            'upstream unavailable',
            503,
            headers: {'content-type': 'text/plain'},
          );
        }),
      );

      await expectLater(
        client.fetchSources(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.code, 'code', 'UNKNOWN')
              .having((error) => error.message, 'message', 'Request failed'),
        ),
      );
    });

    test('requests entry pages with a keyset cursor', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/entries');
          expect(request.url.queryParameters['view'], 'feed');
          expect(request.url.queryParameters['limit'], '20');
          expect(request.url.queryParameters['folder'], 'Tech');
          expect(request.url.queryParameters['sourceId'], '8');
          expect(
            request.url.queryParameters['beforePublishedAt'],
            '2026-04-10T10:00:00.000Z',
          );
          expect(request.url.queryParameters['beforeId'], '42');
          expect(
            request.url.queryParameters['q'],
            'jane analyst unread feed item source summary extra',
          );
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 41,
                  'sourceId': 1,
                  'sourceName': 'Example',
                  'sourceIconUrl': null,
                  'author': 'Jane Analyst',
                  'title': 'Older',
                  'link': 'https://example.com/older',
                  'publishedAt': '2026-04-10T09:00:00Z',
                  'summary': null,
                  'isRead': false,
                  'isSaved': true,
                  'filterStatus': 'success',
                  'summaryStatus': 'pending',
                  'translationStatus': 'skipped',
                  'foreign': false,
                  'coverImageUrl': null,
                },
              ],
              'hasMore': false,
              'nextCursor': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final page = await client.fetchEntries(
        EntryView.feed,
        limit: 20,
        before: EntryPageCursor(
          publishedAt: DateTime.utc(2026, 4, 10, 10),
          id: 42,
        ),
        folder: ' Tech ',
        sourceId: 8,
        searchQuery:
            ' Jane  jane Analyst unread feed item source summary extra ignored ',
      );

      expect(page.items.single.id, 41);
      expect(page.items.single.author, 'Jane Analyst');
      expect(page.items.single.sourceIconUrl, isNull);
      expect(page.items.single.isSaved, isTrue);
      expect(page.items.single.filterStatus, 'SUCCESS');
      expect(page.items.single.summaryStatus, 'PENDING');
      expect(page.items.single.translationStatus, 'SKIPPED');
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    test('requests source entries with a search query', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/feed-sources/8/entries');
          expect(request.url.queryParameters['q'], 'android local');
          return http.Response(
            jsonEncode({
              'items': <Map<String, dynamic>>[],
              'hasMore': false,
              'nextCursor': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final page = await client.fetchSourceEntries(
        8,
        searchQuery: ' Android  android LOCAL ',
      );

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('parses cover image from entry detail responses', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/entries/42');
          expect(request.url.queryParameters['markRead'], 'true');
          return http.Response(
            jsonEncode({
              'id': 42,
              'sourceId': 1,
              'sourceName': 'Example',
              'sourceIconUrl': null,
              'author': 'Jane Analyst',
              'title': 'Analysis',
              'link': 'https://example.com/a',
              'publishedAt': '2026-04-10T09:00:00Z',
              'summary': 'detail summary',
              'isRead': true,
              'isSaved': false,
              'readingProgress': 0.25,
              'isNoise': false,
              'foreign': true,
              'filterStatus': 'SUCCESS',
              'summaryStatus': 'SUCCESS',
              'translationStatus': 'FAILED',
              'coverImageUrl': 'https://example.com/cover.png',
              'contentHtml': '<article><p>hello</p></article>',
              'filterReason': '有分析',
              'translationSegments': <Map<String, String>>[],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final detail = await client.fetchEntryDetail(42, markRead: true);

      expect(detail.coverImageUrl, 'https://example.com/cover.png');
      expect(detail.sourceIconUrl, isNull);
      expect(detail.readingProgress, 0.25);
      expect(detail.translationStatus, 'FAILED');
    });

    test('toggles saved state with dedicated endpoints', () async {
      final requestedPaths = <String>[];
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          requestedPaths.add(request.url.path);
          return http.Response('', 204);
        }),
      );

      await client.markSaved(42);
      await client.markUnsaved(42);

      expect(requestedPaths, [
        '/api/entries/42/saved',
        '/api/entries/42/unsaved',
      ]);
    });

    test(
      'toggles manual noise classification with dedicated endpoints',
      () async {
        final requestedPaths = <String>[];
        final client = RssApiClient(
          baseUrl: 'https://reader.example',
          token: 'token',
          httpClient: MockClient((request) async {
            requestedPaths.add(request.url.path);
            return http.Response('', 204);
          }),
        );

        await client.markNoise(42);
        await client.markFeed(42);

        expect(requestedPaths, [
          '/api/entries/42/noise',
          '/api/entries/42/feed',
        ]);
      },
    );

    test('reprocesses entry AI with the dedicated endpoint', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/entries/42/ai/reprocess');
          return http.Response('', 202);
        }),
      );

      await client.reprocessEntryAi(42);
    });

    test('updates entry reading progress', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/entries/42/progress');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['progress'], 0.64);
          return http.Response('', 204);
        }),
      );

      await client.updateReadingProgress(42, 0.64);
    });

    test('preserves AI key unless explicitly replaced or cleared', () async {
      final requestBodies = <Map<String, dynamic>>[];
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/settings/ai');
          requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'provider': 'DEEPSEEK',
              'configured': true,
              'apiKeyMasked': 'sk-***est',
              'filterPrompt': 'filter',
              'summaryPrompt': 'summary',
              'translationPrompt': 'translation',
              'autoSummaryEnabled': true,
              'autoTranslationEnabled': false,
              'outputLanguage': 'zh-CN',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.updateAiSettings(
        provider: 'DEEPSEEK',
        filterPrompt: 'filter',
        summaryPrompt: 'summary',
        translationPrompt: 'translation',
        autoSummaryEnabled: true,
        autoTranslationEnabled: false,
        outputLanguage: 'zh-CN',
      );
      await client.updateAiSettings(
        provider: 'DEEPSEEK',
        filterPrompt: 'filter',
        summaryPrompt: 'summary',
        translationPrompt: 'translation',
        autoSummaryEnabled: true,
        autoTranslationEnabled: false,
        outputLanguage: 'zh-CN',
        apiKey: ' sk-new ',
      );
      await client.updateAiSettings(
        provider: 'DEEPSEEK',
        filterPrompt: 'filter',
        summaryPrompt: 'summary',
        translationPrompt: 'translation',
        autoSummaryEnabled: true,
        autoTranslationEnabled: false,
        outputLanguage: 'zh-CN',
        clearApiKey: true,
      );

      expect(requestBodies[0].containsKey('apiKey'), isFalse);
      expect(requestBodies[0].containsKey('clearApiKey'), isFalse);
      expect(requestBodies[1]['apiKey'], 'sk-new');
      expect(requestBodies[1].containsKey('clearApiKey'), isFalse);
      expect(requestBodies[2].containsKey('apiKey'), isFalse);
      expect(requestBodies[2]['clearApiKey'], isTrue);
    });

    test('updates appearance theme mode', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/settings/appearance');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['themeMode'], 'DARK');
          return http.Response(
            jsonEncode({'themeMode': 'DARK'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final appearance = await client.updateAppearanceSettings(
        themeMode: AppThemeMode.dark,
      );

      expect(appearance.themeMode, AppThemeMode.dark);
    });

    test('updates feed default language', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/settings/feeds');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['defaultLanguage'], 'en-US');
          return http.Response(
            jsonEncode({
              'defaultLanguage': 'en-US',
              'refreshPolicyDescription': '固定每小时自动刷新一次',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final feeds = await client.updateFeedSettings(defaultLanguage: ' en-US ');

      expect(feeds.defaultLanguage, 'en-US');
      expect(feeds.refreshPolicyDescription, '固定每小时自动刷新一次');
    });

    test('marks a batch of entries read', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/entries/read');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['entryIds'], [1, 2, 3]);
          return http.Response(
            jsonEncode({'updatedCount': 3}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final count = await client.markEntriesRead([1, 2, 3]);

      expect(count, 3);
    });

    test('refreshes a single source with its dedicated endpoint', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/feed-sources/8/refresh');
          return http.Response(
            jsonEncode({
              'accepted': true,
              'acceptedCount': 1,
              'requestedCount': 1,
              'skippedCount': 0,
            }),
            202,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.refreshSource(8);

      expect(result.acceptedCount, 1);
      expect(result.requestedCount, 1);
      expect(result.skippedCount, 0);
    });

    test('refreshes selected sources with one batch request', () async {
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/feed-sources/refresh');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['sourceIds'], [2, 4, 8]);
          return http.Response(
            jsonEncode({
              'accepted': true,
              'acceptedCount': 2,
              'requestedCount': 3,
              'skippedCount': 1,
            }),
            202,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.refreshSources([2, 4, 8]);

      expect(result.acceptedCount, 2);
      expect(result.requestedCount, 3);
      expect(result.skippedCount, 1);
    });

    test(
      'uses a fallback accepted count for older refresh responses',
      () async {
        final client = RssApiClient(
          baseUrl: 'https://reader.example',
          token: 'token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/feed-sources/refresh');
            return http.Response(
              jsonEncode({'accepted': true}),
              202,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final result = await client.refreshSources([2, 4, 8]);

        expect(result.acceptedCount, 3);
        expect(result.requestedCount, 3);
        expect(result.skippedCount, 0);
      },
    );

    test('marks entries read within a source and folder', () async {
      final requestedQueries = <Map<String, String>>[];
      final client = RssApiClient(
        baseUrl: 'https://reader.example',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/entries/read-all');
          requestedQueries.add(request.url.queryParameters);
          return http.Response(
            jsonEncode({'updatedCount': 3}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final sourceCount = await client.markAllRead(EntryView.all, sourceId: 8);
      final folderCount = await client.markAllRead(
        EntryView.all,
        folder: ' Tech ',
      );

      expect(sourceCount, 3);
      expect(folderCount, 3);
      expect(requestedQueries, [
        {'view': 'all', 'sourceId': '8'},
        {'view': 'all', 'folder': 'Tech'},
      ]);
    });
  });
}
