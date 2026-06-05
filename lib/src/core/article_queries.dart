import '../models/app_section.dart';
import '../models/entry_record.dart';
import '../models/feed_source.dart';
import '../models/snapshot.dart';
import 'search_query.dart';

class ArticleQueries {
  static List<EntryRecord> resolve({
    required AppSnapshot snapshot,
    required AppSection section,
    required bool unreadOnly,
    bool inProgressOnly = false,
    String searchQuery = '',
    int? selectedSourceId,
    int? sourceFilterId,
    String? folderFilter,
  }) {
    final normalizedFolderFilter = _normalizeFolder(folderFilter);
    List<EntryRecord> entries;

    switch (section) {
      case AppSection.feed:
        entries = _resolveViewEntries(
          snapshot,
          ListKey.feed,
          'feed',
          sourceFilterId,
          normalizedFolderFilter,
          unreadOnly,
        );
      case AppSection.noise:
        entries = _resolveViewEntries(
          snapshot,
          ListKey.noise,
          'noise',
          sourceFilterId,
          normalizedFolderFilter,
          unreadOnly,
        );
      case AppSection.saved:
        entries = _resolveViewEntries(
          snapshot,
          ListKey.saved,
          'saved',
          sourceFilterId,
          normalizedFolderFilter,
          unreadOnly,
        );
      case AppSection.sourceEntries:
        entries = selectedSourceId == null
            ? const <EntryRecord>[]
            : _resolveSourceEntries(snapshot, selectedSourceId, unreadOnly);
      case AppSection.sources:
      case AppSection.settings:
      case AppSection.account:
        entries = const <EntryRecord>[];
    }

    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final searchKey = _searchListKey(
        section,
        selectedSourceId,
        query,
        sourceFilterId,
        normalizedFolderFilter,
        unreadOnly,
      );
      if (searchKey != null && snapshot.hasListSnapshot(searchKey)) {
        entries = _resolveByListKey(snapshot, searchKey);
      } else {
        entries = entries
            .where((entry) => _matchesSearch(entry, query))
            .toList(growable: false);
      }
    }

    if (unreadOnly) {
      entries = entries.where((entry) => !entry.isRead).toList(growable: false);
    }

    if (inProgressOnly) {
      entries = entries
          .where((entry) => entry.isInProgress)
          .toList(growable: false);
    }

    if (sourceFilterId != null) {
      entries = entries
          .where((entry) => entry.sourceId == sourceFilterId)
          .toList(growable: false);
    }

    if (normalizedFolderFilter != null) {
      entries = entries
          .where(
            (entry) =>
                _normalizeFolder(snapshot.sourceById(entry.sourceId)?.folder) ==
                normalizedFolderFilter,
          )
          .toList(growable: false);
    }

    return entries;
  }

  static List<EntryRecord> _resolveViewEntries(
    AppSnapshot snapshot,
    ListKey defaultKey,
    String view,
    int? sourceFilterId,
    String? folderFilter,
    bool unreadOnly,
  ) {
    if (sourceFilterId != null) {
      final sourceKey = unreadOnly
          ? ListKey.unreadSourceInView(view, sourceFilterId)
          : ListKey.sourceInView(view, sourceFilterId);
      if (snapshot.hasListSnapshot(sourceKey)) {
        return _resolveByListKey(snapshot, sourceKey);
      }
    }
    if (folderFilter != null) {
      final folderKey = unreadOnly
          ? ListKey.unreadFolderInView(view, folderFilter)
          : ListKey.folderInView(view, folderFilter);
      if (snapshot.hasListSnapshot(folderKey)) {
        return _resolveByListKey(snapshot, folderKey);
      }
    }
    if (unreadOnly) {
      final unreadKey = ListKey.unreadInView(view);
      if (snapshot.hasListSnapshot(unreadKey)) {
        return _resolveByListKey(snapshot, unreadKey);
      }
    }
    return _resolveByListKey(snapshot, defaultKey);
  }

  static List<EntryRecord> _resolveByListKey(
    AppSnapshot snapshot,
    ListKey key,
  ) {
    return snapshot
        .listIds(key)
        .map((id) => snapshot.entries[id])
        .whereType<EntryRecord>()
        .toList(growable: false);
  }

  static List<EntryRecord> _resolveSourceEntries(
    AppSnapshot snapshot,
    int sourceId,
    bool unreadOnly,
  ) {
    if (unreadOnly) {
      final unreadKey = ListKey.unreadSourceInView('all', sourceId);
      if (snapshot.hasListSnapshot(unreadKey)) {
        final unreadIds = snapshot.listIds(unreadKey);
        return unreadIds
            .map((id) => snapshot.entries[id])
            .whereType<EntryRecord>()
            .toList(growable: false);
      }
    }

    final ids = snapshot.listIds(ListKey.source(sourceId));
    if (ids.isNotEmpty) {
      return ids
          .map((id) => snapshot.entries[id])
          .whereType<EntryRecord>()
          .toList(growable: false);
    }

    final fallback = snapshot.entries.values
        .where((entry) => entry.sourceId == sourceId)
        .toList();
    fallback.sort(
      (left, right) => right.publishedAt.compareTo(left.publishedAt),
    );
    return fallback;
  }

  static bool _matchesSearch(EntryRecord entry, String query) {
    final tokens = searchQueryTokens(query);
    if (tokens.isEmpty) {
      return true;
    }
    final searchableText = [
      entry.title,
      entry.sourceName,
      entry.author,
      entry.link,
      entry.summary,
      entry.filterReason,
      entry.contentHtml,
      ...entry.translationSegments.expand(
        (segment) => [segment.source, segment.translation],
      ),
    ].whereType<String>().join('\n').toLowerCase();

    return tokens.every(searchableText.contains);
  }

  static ListKey? _searchListKey(
    AppSection section,
    int? selectedSourceId,
    String query,
    int? sourceFilterId,
    String? folderFilter,
    bool unreadOnly,
  ) {
    return switch (section) {
      AppSection.feed =>
        sourceFilterId != null
            ? unreadOnly
                  ? ListKey.searchUnreadSourceInView(
                      'feed',
                      sourceFilterId,
                      query,
                    )
                  : ListKey.searchSourceInView('feed', sourceFilterId, query)
            : folderFilter == null
            ? unreadOnly
                  ? ListKey.searchUnreadInView('feed', query)
                  : ListKey.searchInView('feed', query)
            : unreadOnly
            ? ListKey.searchUnreadFolderInView('feed', folderFilter, query)
            : ListKey.searchFolderInView('feed', folderFilter, query),
      AppSection.noise =>
        sourceFilterId != null
            ? unreadOnly
                  ? ListKey.searchUnreadSourceInView(
                      'noise',
                      sourceFilterId,
                      query,
                    )
                  : ListKey.searchSourceInView('noise', sourceFilterId, query)
            : folderFilter == null
            ? unreadOnly
                  ? ListKey.searchUnreadInView('noise', query)
                  : ListKey.searchInView('noise', query)
            : unreadOnly
            ? ListKey.searchUnreadFolderInView('noise', folderFilter, query)
            : ListKey.searchFolderInView('noise', folderFilter, query),
      AppSection.saved =>
        sourceFilterId != null
            ? unreadOnly
                  ? ListKey.searchUnreadSourceInView(
                      'saved',
                      sourceFilterId,
                      query,
                    )
                  : ListKey.searchSourceInView('saved', sourceFilterId, query)
            : folderFilter == null
            ? unreadOnly
                  ? ListKey.searchUnreadInView('saved', query)
                  : ListKey.searchInView('saved', query)
            : unreadOnly
            ? ListKey.searchUnreadFolderInView('saved', folderFilter, query)
            : ListKey.searchFolderInView('saved', folderFilter, query),
      AppSection.sourceEntries =>
        selectedSourceId == null
            ? null
            : unreadOnly
            ? ListKey.searchUnreadSourceInView('all', selectedSourceId, query)
            : ListKey.searchSource(selectedSourceId, query),
      AppSection.sources || AppSection.settings || AppSection.account => null,
    };
  }

  static String? _normalizeFolder(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized == defaultSourceFolder ? defaultSourceFolder : normalized;
  }
}
