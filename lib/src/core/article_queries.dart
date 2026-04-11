import '../models/app_section.dart';
import '../models/entry_record.dart';
import '../models/snapshot.dart';

class ArticleQueries {
  static List<EntryRecord> resolve({
    required AppSnapshot snapshot,
    required AppSection section,
    required bool unreadOnly,
    int? selectedSourceId,
  }) {
    List<EntryRecord> entries;

    switch (section) {
      case AppSection.feed:
        entries = _resolveByListKey(snapshot, ListKey.feed);
      case AppSection.noise:
        entries = _resolveByListKey(snapshot, ListKey.noise);
      case AppSection.sourceEntries:
        entries = selectedSourceId == null
            ? const <EntryRecord>[]
            : _resolveSourceEntries(snapshot, selectedSourceId);
      case AppSection.sources:
      case AppSection.settings:
      case AppSection.account:
        entries = const <EntryRecord>[];
    }

    if (unreadOnly) {
      entries = entries.where((entry) => !entry.isRead).toList(growable: false);
    }

    return entries;
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
  ) {
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
}
