import 'entry_record.dart';
import 'feed_source.dart';
import 'settings_bundle.dart';

class ListKey {
  const ListKey._(this.value);

  final String value;

  static const feed = ListKey._('feed');
  static const noise = ListKey._('noise');
  static const all = ListKey._('all');

  static ListKey source(int sourceId) => ListKey._('source:$sourceId');
}

class AppSnapshot {
  const AppSnapshot({
    required this.sources,
    required this.settings,
    required this.entries,
    required this.listSnapshots,
  });

  final List<FeedSource> sources;
  final SettingsBundle settings;
  final Map<int, EntryRecord> entries;
  final Map<String, List<int>> listSnapshots;

  const AppSnapshot.empty()
    : sources = const [],
      settings = const SettingsBundle.empty(),
      entries = const {},
      listSnapshots = const {};

  List<int> listIds(ListKey key) {
    return List<int>.unmodifiable(listSnapshots[key.value] ?? const <int>[]);
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
  }) {
    return AppSnapshot(
      sources: sources ?? this.sources,
      settings: settings ?? this.settings,
      entries: entries ?? this.entries,
      listSnapshots: listSnapshots ?? this.listSnapshots,
    );
  }
}
