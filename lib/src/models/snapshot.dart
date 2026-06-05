import '../core/search_query.dart';
import 'entry_record.dart';
import 'entry_page_cursor.dart';
import 'feed_source.dart';
import 'settings_bundle.dart';

class ListKey {
  const ListKey._(this.value);

  final String value;

  static const feed = ListKey._('feed');
  static const noise = ListKey._('noise');
  static const saved = ListKey._('saved');
  static const all = ListKey._('all');

  static ListKey source(int sourceId) => ListKey._('source:$sourceId');

  static ListKey folderInView(String view, String folder) => ListKey._(
    'folder:view:$view:${Uri.encodeComponent(_normalizeFolderName(folder))}',
  );

  static ListKey sourceInView(String view, int sourceId) =>
      ListKey._('source:view:$view:$sourceId');

  static ListKey unreadInView(String view) => ListKey._('unread:view:$view');

  static ListKey unreadFolderInView(String view, String folder) => ListKey._(
    'unread:folder:$view:${Uri.encodeComponent(_normalizeFolderName(folder))}',
  );

  static ListKey unreadSourceInView(String view, int sourceId) =>
      ListKey._('unread:source-view:$view:$sourceId');

  static ListKey searchInView(String view, String query) => ListKey._(
    'search:view:$view:${Uri.encodeComponent(_normalizeSearchQuery(query))}',
  );

  static ListKey searchSource(int sourceId, String query) => ListKey._(
    'search:source:$sourceId:${Uri.encodeComponent(_normalizeSearchQuery(query))}',
  );

  static ListKey searchSourceInView(
    String view,
    int sourceId,
    String query,
  ) => ListKey._(
    'search:source-view:$view:$sourceId:${Uri.encodeComponent(_normalizeSearchQuery(query))}',
  );

  static ListKey searchUnreadInView(String view, String query) => ListKey._(
    'search:unread-view:$view:${Uri.encodeComponent(_normalizeSearchQuery(query))}',
  );

  static ListKey searchUnreadSourceInView(
    String view,
    int sourceId,
    String query,
  ) => ListKey._(
    'search:unread-source-view:$view:$sourceId:${Uri.encodeComponent(_normalizeSearchQuery(query))}',
  );

  static bool isSourceScopedValue(String value, Set<int> sourceIds) {
    if (sourceIds.isEmpty) {
      return false;
    }

    final parts = value.split(':');
    final sourceId = switch (parts) {
      ['source', final id] => int.tryParse(id),
      ['source', 'view', _, final id] => int.tryParse(id),
      ['unread', 'source-view', _, final id] => int.tryParse(id),
      ['search', 'source', final id, ...] => int.tryParse(id),
      ['search', 'source-view', _, final id, ...] => int.tryParse(id),
      ['search', 'unread-source-view', _, final id, ...] => int.tryParse(id),
      _ => null,
    };
    return sourceId != null && sourceIds.contains(sourceId);
  }

  static bool isFolderScopedValue(String value, Set<String> folders) {
    if (folders.isEmpty) {
      return false;
    }

    final parts = value.split(':');
    final folder = switch (parts) {
      ['folder', 'view', _, final name] => Uri.decodeComponent(name),
      ['unread', 'folder', _, final name] => Uri.decodeComponent(name),
      ['search', 'folder', _, final name, ...] => Uri.decodeComponent(name),
      ['search', 'unread-folder', _, final name, ...] => Uri.decodeComponent(
        name,
      ),
      _ => null,
    };
    return folder != null && folders.contains(folder);
  }

  static ListKey searchUnreadFolderInView(
    String view,
    String folder,
    String query,
  ) => ListKey._(
    'search:unread-folder:$view:${Uri.encodeComponent(_normalizeFolderName(folder))}:${Uri.encodeComponent(_normalizeSearchQuery(query))}',
  );

  static ListKey searchFolderInView(
    String view,
    String folder,
    String query,
  ) => ListKey._(
    'search:folder:$view:${Uri.encodeComponent(_normalizeFolderName(folder))}:${Uri.encodeComponent(_normalizeSearchQuery(query))}',
  );

  bool get isSearch => value.startsWith('search:');

  String? get searchQuery {
    if (!isSearch) {
      return null;
    }
    final parts = value.split(':');
    if (parts.length >= 5 && parts[1] == 'folder') {
      return Uri.decodeComponent(parts[4]);
    }
    if (parts.length >= 5 && parts[1] == 'source-view') {
      return Uri.decodeComponent(parts[4]);
    }
    if (parts.length >= 5 && parts[1] == 'unread-folder') {
      return Uri.decodeComponent(parts[4]);
    }
    if (parts.length >= 5 && parts[1] == 'unread-source-view') {
      return Uri.decodeComponent(parts[4]);
    }
    if (parts.length >= 4 && parts[1] == 'unread-view') {
      return Uri.decodeComponent(parts[3]);
    }
    if (parts.length < 4) {
      return null;
    }
    return Uri.decodeComponent(parts[3]);
  }

  String? get searchViewValue {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'search' || parts[1] != 'view') {
      return null;
    }
    return parts[2];
  }

  String? get searchUnreadViewValue {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'search' || parts[1] != 'unread-view') {
      return null;
    }
    return parts[2];
  }

  String? get searchSourceViewValue {
    final parts = value.split(':');
    if (parts.length < 5 || parts[0] != 'search' || parts[1] != 'source-view') {
      return null;
    }
    return parts[2];
  }

  int? get searchSourceViewSourceId {
    final parts = value.split(':');
    if (parts.length < 5 || parts[0] != 'search' || parts[1] != 'source-view') {
      return null;
    }
    return int.tryParse(parts[3]);
  }

  String? get searchUnreadSourceViewValue {
    final parts = value.split(':');
    if (parts.length < 5 ||
        parts[0] != 'search' ||
        parts[1] != 'unread-source-view') {
      return null;
    }
    return parts[2];
  }

  int? get searchUnreadSourceViewSourceId {
    final parts = value.split(':');
    if (parts.length < 5 ||
        parts[0] != 'search' ||
        parts[1] != 'unread-source-view') {
      return null;
    }
    return int.tryParse(parts[3]);
  }

  String? get searchFolderViewValue {
    final parts = value.split(':');
    if (parts.length < 5 || parts[0] != 'search' || parts[1] != 'folder') {
      return null;
    }
    return parts[2];
  }

  String? get searchFolderName {
    final parts = value.split(':');
    if (parts.length < 5 || parts[0] != 'search' || parts[1] != 'folder') {
      return null;
    }
    return Uri.decodeComponent(parts[3]);
  }

  String? get searchUnreadFolderViewValue {
    final parts = value.split(':');
    if (parts.length < 5 ||
        parts[0] != 'search' ||
        parts[1] != 'unread-folder') {
      return null;
    }
    return parts[2];
  }

  String? get searchUnreadFolderName {
    final parts = value.split(':');
    if (parts.length < 5 ||
        parts[0] != 'search' ||
        parts[1] != 'unread-folder') {
      return null;
    }
    return Uri.decodeComponent(parts[3]);
  }

  int? get searchSourceId {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'search' || parts[1] != 'source') {
      return null;
    }
    return int.tryParse(parts[2]);
  }

  String? get sourceViewValue {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'source' || parts[1] != 'view') {
      return null;
    }
    return parts[2];
  }

  int? get sourceViewSourceId {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'source' || parts[1] != 'view') {
      return null;
    }
    return int.tryParse(parts[3]);
  }

  String? get unreadViewValue {
    final parts = value.split(':');
    if (parts.length < 3 || parts[0] != 'unread' || parts[1] != 'view') {
      return null;
    }
    return parts[2];
  }

  String? get unreadSourceViewValue {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'unread' || parts[1] != 'source-view') {
      return null;
    }
    return parts[2];
  }

  int? get unreadSourceViewSourceId {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'unread' || parts[1] != 'source-view') {
      return null;
    }
    return int.tryParse(parts[3]);
  }

  String? get unreadFolderViewValue {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'unread' || parts[1] != 'folder') {
      return null;
    }
    return parts[2];
  }

  String? get unreadFolderName {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'unread' || parts[1] != 'folder') {
      return null;
    }
    return Uri.decodeComponent(parts[3]);
  }

  String? get folderViewValue {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'folder' || parts[1] != 'view') {
      return null;
    }
    return parts[2];
  }

  String? get folderName {
    final parts = value.split(':');
    if (parts.length < 4 || parts[0] != 'folder' || parts[1] != 'view') {
      return null;
    }
    return Uri.decodeComponent(parts[3]);
  }

  static String _normalizeSearchQuery(String query) =>
      normalizeSearchQuery(query);

  static String _normalizeFolderName(String folder) => folder.trim();

  @override
  bool operator ==(Object other) {
    return other is ListKey && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

class AppSnapshot {
  const AppSnapshot({
    required this.sources,
    required this.settings,
    required this.entries,
    required this.listSnapshots,
    required this.listHasMore,
    required this.listCursors,
  });

  final List<FeedSource> sources;
  final SettingsBundle settings;
  final Map<int, EntryRecord> entries;
  final Map<String, List<int>> listSnapshots;
  final Map<String, bool> listHasMore;
  final Map<String, EntryPageCursor> listCursors;

  const AppSnapshot.empty()
    : sources = const [],
      settings = const SettingsBundle.empty(),
      entries = const {},
      listSnapshots = const {},
      listHasMore = const {},
      listCursors = const {};

  List<int> listIds(ListKey key) {
    return List<int>.unmodifiable(listSnapshots[key.value] ?? const <int>[]);
  }

  bool hasListSnapshot(ListKey key) {
    return listSnapshots.containsKey(key.value);
  }

  bool hasMore(ListKey key) {
    return listHasMore[key.value] ?? false;
  }

  EntryPageCursor? cursorFor(ListKey key) {
    return listCursors[key.value];
  }

  FeedSource? sourceById(int sourceId) {
    for (final source in sources) {
      if (source.id == sourceId) {
        return source;
      }
    }
    return null;
  }

  AppSnapshot copyWith({
    List<FeedSource>? sources,
    SettingsBundle? settings,
    Map<int, EntryRecord>? entries,
    Map<String, List<int>>? listSnapshots,
    Map<String, bool>? listHasMore,
    Map<String, EntryPageCursor>? listCursors,
  }) {
    return AppSnapshot(
      sources: sources ?? this.sources,
      settings: settings ?? this.settings,
      entries: entries ?? this.entries,
      listSnapshots: listSnapshots ?? this.listSnapshots,
      listHasMore: listHasMore ?? this.listHasMore,
      listCursors: listCursors ?? this.listCursors,
    );
  }
}
