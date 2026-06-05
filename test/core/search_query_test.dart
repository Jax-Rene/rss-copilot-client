import 'package:rss_copilot_client/src/core/search_query.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('search query normalization', () {
    test('normalizes case whitespace and duplicate tokens', () {
      expect(normalizeSearchQuery('  Jane   jane  Analyst  '), 'jane analyst');
    });

    test('keeps the first eight unique tokens', () {
      expect(
        normalizeSearchQuery(
          'one two two three four five six seven eight nine',
        ),
        'one two three four five six seven eight',
      );
    });

    test('normalizes search list keys', () {
      final key = ListKey.searchInView(
        'feed',
        ' Jane  jane Analyst unread feed item source summary extra ignored ',
      );

      expect(
        key.searchQuery,
        'jane analyst unread feed item source summary extra',
      );
      expect(
        key.value,
        'search:view:feed:jane%20analyst%20unread%20feed%20item%20source%20summary%20extra',
      );
    });
  });
}
