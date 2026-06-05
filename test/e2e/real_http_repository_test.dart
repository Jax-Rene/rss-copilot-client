import 'dart:io';

import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:rss_copilot_client/src/repositories/rss_repository.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runs repository workflow against a real RSS Copilot server',
    () async {
      final serverBaseUrl = Platform.environment['RSS_COPILOT_E2E_BASE_URL'];
      final feedUrl = Platform.environment['RSS_COPILOT_E2E_FEED_URL'];
      final jsonFeedUrl = Platform.environment['RSS_COPILOT_E2E_JSON_FEED_URL'];
      final email =
          Platform.environment['RSS_COPILOT_E2E_EMAIL'] ?? 'demo@example.com';
      final password =
          Platform.environment['RSS_COPILOT_E2E_PASSWORD'] ?? 'pass123456';
      if (serverBaseUrl == null ||
          serverBaseUrl.isEmpty ||
          feedUrl == null ||
          feedUrl.isEmpty ||
          jsonFeedUrl == null ||
          jsonFeedUrl.isEmpty) {
        return;
      }

      final store = await LocalStore.inMemory();
      final repository = RssRepository(
        store: store,
        refreshPollDelay: Duration.zero,
        refreshPollAttempts: 1,
      );
      addTearDown(store.close);

      final session = await repository.login(
        baseUrl: '$serverBaseUrl/api/health',
        email: email,
        password: password,
      );
      expect(session.baseUrl, serverBaseUrl);
      expect(session.user.email, email);

      final source = await repository.addSource(feedUrl, folder: 'E2E');
      expect(source.name, 'Sample Feed');

      await repository.refreshSourceAndPoll(source.id);
      final snapshot = await _waitForEntries(repository);
      expect(snapshot.sources, hasLength(1));
      expect(snapshot.sources.single.name, 'Sample Feed');
      expect(snapshot.listIds(ListKey.feed), hasLength(1));
      expect(snapshot.listIds(ListKey.noise), hasLength(1));

      final feedEntryId = snapshot.listIds(ListKey.feed).single;
      final detail = await repository.fetchEntryDetail(feedEntryId);
      expect(detail?.title, 'Long Analysis');
      expect(detail?.contentHtml, contains('First paragraph'));
      expect(detail?.translationSegments.first.translation, '第一段。');

      await repository.setSaved(feedEntryId, true);
      await repository.updateReadingProgress(feedEntryId, 0.42);
      var latest = await store.loadSnapshot();
      expect(latest.entries[feedEntryId]?.isSaved, isTrue);
      expect(latest.entries[feedEntryId]?.readingProgress, 0.42);

      await repository.markRead(feedEntryId);
      latest = await store.loadSnapshot();
      expect(latest.entries[feedEntryId]?.isRead, isTrue);
      expect(latest.entries[feedEntryId]?.readingProgress, 1);

      final opml = await repository.exportOpml();
      expect(opml, contains('Sample Feed'));
      expect(opml, contains(feedUrl));

      final importResult = await repository.importOpml(
        opml,
        refreshAfterImport: false,
      );
      expect(importResult.importedCount, 0);
      expect(importResult.skippedCount, greaterThanOrEqualTo(1));
      expect(await repository.pendingEntryActionCount(), 0);

      final jsonSource = await repository.addSource(
        jsonFeedUrl,
        folder: 'E2E / JSON',
      );
      expect(jsonSource.name, 'JSON Smoke Feed');

      await repository.refreshSourceAndPoll(jsonSource.id);
      await repository.sync();
      latest = await store.loadSnapshot();
      expect(
        latest.sources.where((source) => source.name == 'JSON Smoke Feed'),
        hasLength(1),
      );
      final jsonEntry = latest.entries.values.singleWhere(
        (entry) => entry.title == 'JSON Smoke Story',
      );
      expect(jsonEntry.sourceName, 'JSON Smoke Feed');
      expect(jsonEntry.author, 'JSON Author');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

Future<AppSnapshot> _waitForEntries(RssRepository repository) async {
  Object? lastError;
  for (var attempt = 0; attempt < 20; attempt += 1) {
    try {
      await repository.sync();
      final snapshot = await repository.loadSnapshot();
      if (snapshot.listIds(ListKey.feed).isNotEmpty &&
          snapshot.listIds(ListKey.noise).isNotEmpty) {
        return snapshot;
      }
    } catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  if (lastError != null) {
    throw StateError('entries did not sync before timeout: $lastError');
  }
  throw StateError('entries did not sync before timeout');
}
