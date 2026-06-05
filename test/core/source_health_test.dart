import 'package:rss_copilot_client/src/core/source_health.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:test/test.dart';

void main() {
  group('SourceHealthSummary', () {
    final now = DateTime.utc(2026, 5, 24, 12);

    test('summarizes source health and unread totals', () {
      final summary = SourceHealthSummary.fromSources([
        _source(
          id: 1,
          lastFetchedAt: now.subtract(const Duration(hours: 1)),
          unreadCount: 3,
        ),
        _source(
          id: 2,
          hasError: true,
          lastFetchedAt: now.subtract(const Duration(hours: 1)),
          unreadCount: 5,
        ),
        _source(
          id: 3,
          lastFetchedAt: now.subtract(const Duration(hours: 25)),
          unreadCount: 2,
        ),
        _source(
          id: 4,
          enabled: false,
          lastFetchedAt: now.subtract(const Duration(hours: 25)),
          unreadCount: 7,
        ),
      ], now: now);

      expect(summary.totalCount, 4);
      expect(summary.healthyCount, 1);
      expect(summary.errorCount, 1);
      expect(summary.staleCount, 1);
      expect(summary.disabledCount, 1);
      expect(summary.totalUnreadCount, 17);
      expect(summary.issueCount, 3);
      expect(summary.hasIssues, isTrue);
    });

    test('prioritizes disabled, then error, then stale', () {
      final disabled = _source(
        id: 1,
        enabled: false,
        hasError: true,
        lastFetchedAt: now.subtract(const Duration(hours: 25)),
      );
      final errored = _source(
        id: 2,
        hasError: true,
        lastFetchedAt: now.subtract(const Duration(hours: 25)),
      );

      expect(
        SourceHealthSummary.statusFor(disabled, now: now),
        SourceHealthStatus.disabled,
      );
      expect(
        SourceHealthSummary.statusFor(errored, now: now),
        SourceHealthStatus.error,
      );
    });

    test('treats never fetched sources as stale', () {
      final source = _source(id: 1);

      expect(
        SourceHealthSummary.statusFor(source, now: now),
        SourceHealthStatus.stale,
      );
    });

    test('does not mark source stale at the exact threshold', () {
      final source = _source(
        id: 1,
        lastFetchedAt: now.subtract(defaultSourceStaleAfter),
      );

      expect(
        SourceHealthSummary.statusFor(source, now: now),
        SourceHealthStatus.healthy,
      );
    });
  });
}

FeedSource _source({
  required int id,
  bool enabled = true,
  bool hasError = false,
  DateTime? lastFetchedAt,
  int unreadCount = 0,
}) {
  return FeedSource(
    id: id,
    name: 'Source $id',
    rssUrl: 'https://example.com/$id.xml',
    siteUrl: 'https://example.com/$id',
    iconUrl: null,
    enabled: enabled,
    lastFetchedAt: lastFetchedAt,
    hasError: hasError,
    unreadCount: unreadCount,
  );
}
