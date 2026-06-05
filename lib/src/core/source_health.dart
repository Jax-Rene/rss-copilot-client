import '../models/feed_source.dart';

const defaultSourceStaleAfter = Duration(hours: 24);

enum SourceHealthStatus { healthy, disabled, error, stale }

class SourceHealthSummary {
  const SourceHealthSummary({
    required this.totalCount,
    required this.healthyCount,
    required this.errorCount,
    required this.staleCount,
    required this.disabledCount,
    required this.totalUnreadCount,
  });

  final int totalCount;
  final int healthyCount;
  final int errorCount;
  final int staleCount;
  final int disabledCount;
  final int totalUnreadCount;

  int get issueCount => errorCount + staleCount + disabledCount;

  bool get hasIssues => issueCount > 0;

  factory SourceHealthSummary.fromSources(
    List<FeedSource> sources, {
    required DateTime now,
    Duration staleAfter = defaultSourceStaleAfter,
  }) {
    var healthyCount = 0;
    var errorCount = 0;
    var staleCount = 0;
    var disabledCount = 0;
    var totalUnreadCount = 0;

    for (final source in sources) {
      totalUnreadCount += source.unreadCount;
      switch (SourceHealthSummary.statusFor(
        source,
        now: now,
        staleAfter: staleAfter,
      )) {
        case SourceHealthStatus.healthy:
          healthyCount += 1;
        case SourceHealthStatus.disabled:
          disabledCount += 1;
        case SourceHealthStatus.error:
          errorCount += 1;
        case SourceHealthStatus.stale:
          staleCount += 1;
      }
    }

    return SourceHealthSummary(
      totalCount: sources.length,
      healthyCount: healthyCount,
      errorCount: errorCount,
      staleCount: staleCount,
      disabledCount: disabledCount,
      totalUnreadCount: totalUnreadCount,
    );
  }

  static SourceHealthStatus statusFor(
    FeedSource source, {
    required DateTime now,
    Duration staleAfter = defaultSourceStaleAfter,
  }) {
    if (!source.enabled) {
      return SourceHealthStatus.disabled;
    }
    if (source.hasError) {
      return SourceHealthStatus.error;
    }
    if (_isStale(source, now: now, staleAfter: staleAfter)) {
      return SourceHealthStatus.stale;
    }
    return SourceHealthStatus.healthy;
  }

  static bool _isStale(
    FeedSource source, {
    required DateTime now,
    required Duration staleAfter,
  }) {
    final lastFetchedAt = source.lastFetchedAt;
    if (lastFetchedAt == null) {
      return true;
    }
    return now.toUtc().difference(lastFetchedAt.toUtc()) > staleAfter;
  }
}
